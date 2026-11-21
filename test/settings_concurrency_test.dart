import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/screens/store/bill_settings_screen.dart';

void main() {
  final db = DatabaseHelper.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await db.close();
    DatabaseHelper.databaseFileName = 'settings-concurrency.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await db.saveBillSettings(BillSettings(invoiceTitle: 'Original'));
  });
  tearDown(() async {
    db.isAdminMutationAllowed = null;
    db.assertAdminMutation = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  test(
    'sync-changed settings reject frozen editor without touching bill or series',
    () async {
      final baseline = await db.captureSettingsEditBaseline();
      final settings = await db.getBillSettings();
      final series = await db.getDefaultInvoiceSeriesSettings();
      final sql = await db.database;
      await sql.update('bill_settings', {
        'footer_text': 'Fresh sync value',
        'sync_dirty': 2,
      });
      await expectLater(
        db.saveInvoiceSettings(
          settings.copyWith(invoiceTitle: 'Stale'),
          series.copyWith(name: 'Stale series'),
          baseline: baseline,
        ),
        throwsStateError,
      );
      expect((await db.getBillSettings()).footerText, 'Fresh sync value');
      expect((await db.getBillSettings()).invoiceTitle, 'Original');
      expect((await db.getDefaultInvoiceSeriesSettings()).name, series.name);
    },
  );

  test(
    'second settings write failure rolls back the entire invoice editor',
    () async {
      final baseline = await db.captureSettingsEditBaseline();
      final settings = await db.getBillSettings();
      final series = await db.getDefaultInvoiceSeriesSettings();
      final sql = await db.database;
      final before = await sql.query('bill_settings');
      await sql.execute(
        "CREATE TRIGGER fail_series BEFORE UPDATE ON invoice_series BEGIN SELECT RAISE(ABORT, 'series failure'); END",
      );
      await expectLater(
        db.saveInvoiceSettings(
          settings.copyWith(invoiceTitle: 'Partial'),
          series.copyWith(name: 'New series'),
          baseline: baseline,
        ),
        throwsA(isA<DatabaseException>()),
      );
      expect(await sql.query('bill_settings'), before);
      expect((await db.getDefaultInvoiceSeriesSettings()).name, series.name);
    },
  );

  test(
    'runtime counters and transport flags do not invalidate configuration edits',
    () async {
      final baseline = await db.captureSettingsEditBaseline();
      final settings = await db.getBillSettings();
      final series = await db.getDefaultInvoiceSeriesSettings();
      final sql = await db.database;
      await sql.update('invoice_series', {
        'next_sequence': 42,
        'last_sequence_key': '2627',
        'sync_dirty': 0,
      });
      await sql.update('bill_settings', {
        'sync_dirty': 0,
        'updated_at': '2026-11-19T00:00:00Z',
      });
      await db.saveInvoiceSettings(
        settings.copyWith(invoiceTitle: 'Allowed'),
        series,
        baseline: baseline,
      );
      expect((await db.getBillSettings()).invoiceTitle, 'Allowed');
      expect((await sql.query('invoice_series')).single['next_sequence'], 42);
    },
  );

  test(
    'profile and pricing share persisted baseline and retain new edits on conflict',
    () async {
      final baseline = await db.captureSettingsEditBaseline();
      final pricing = await db.getGlobalPricingSettings();
      await db.saveShopProfile(ShopProfile(name: 'Current shop'));
      final sql = await db.database;
      final before = await sql.query('app_settings');
      await expectLater(
        db.saveGlobalPricingSettings(
          pricing.copyWith(defaultOverheadCost: 99),
          baseline: baseline,
        ),
        throwsStateError,
      );
      await expectLater(
        db.saveShopProfile(ShopProfile(name: 'Stale shop'), baseline: baseline),
        throwsStateError,
      );
      expect(await sql.query('app_settings'), before);
      expect((await db.getShopProfile())!.name, 'Current shop');
      final fresh = await db.captureSettingsEditBaseline();
      final saved = await db.savePricingSettingsWithBaseline(
        pricing.copyWith(defaultOverheadCost: 2),
        baseline: fresh,
      );
      await db.savePricingSettingsWithBaseline(
        pricing.copyWith(defaultOverheadCost: 3),
        baseline: saved,
      );
      expect((await db.getGlobalPricingSettings()).defaultOverheadCost, 3);
    },
  );

  test(
    'shop change and revoked edit rights cannot reuse a frozen settings baseline',
    () async {
      final baseline = await db.captureSettingsEditBaseline();
      final settings = await db.getBillSettings();
      final series = await db.getDefaultInvoiceSeriesSettings();
      db.assertAdminMutation = () async {
        throw StateError('No permission');
      };
      await expectLater(
        db.saveInvoiceSettings(
          settings.copyWith(invoiceTitle: 'Denied'),
          series,
          baseline: baseline,
        ),
        throwsStateError,
      );
      db.assertAdminMutation = null;
      expect((await db.getBillSettings()).invoiceTitle, 'Original');
      await db.adoptCloudShopId('new-shop');
      await expectLater(
        db.saveInvoiceSettings(
          settings.copyWith(invoiceTitle: 'Wrong shop'),
          series,
          baseline: baseline,
        ),
        throwsStateError,
      );
      expect((await (await db.database).query('bill_settings')), isEmpty);
    },
  );

  testWidgets('stale invoice editor keeps typed text and remains open', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: BillSettingsScreen()));
    for (
      var i = 0;
      i < 20 && find.text('Save Bill Settings').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    final title = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Invoice title',
    );
    expect(find.text('Save Bill Settings'), findsOneWidget);
    await tester.scrollUntilVisible(
      title,
      250,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(title, 'Typed unsaved title');
    await tester.runAsync(() async {
      final current = await db.getBillSettings();
      await db.saveBillSettings(
        current.copyWith(footerText: 'Concurrent settings'),
      );
    });
    await tester.tap(find.text('Save Bill Settings'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Bill Settings'), findsOneWidget);
    expect(
      tester.widget<TextField>(title).controller!.text,
      'Typed unsaved title',
    );
    expect(
      find.textContaining('settings changed while you were editing'),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      expect((await db.getBillSettings()).invoiceTitle, 'Original');
    });
    await tester.pumpWidget(const SizedBox());
  });
}
