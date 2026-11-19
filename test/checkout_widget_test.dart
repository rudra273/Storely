import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/screens/scan_screen.dart';
import 'package:storely/utils/test_keys.dart';

Future<void> settleIo(WidgetTester tester) async {
  for (var n = 0; n < 8; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  final db = DatabaseHelper.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await db.close();
    DatabaseHelper.databaseFileName = 'checkout-widget.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await db.saveBillSettings(BillSettings());
  });
  tearDown(() async {
    db.onDatabaseChanged = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScanScreen(
          initialMode: BillingEntryMode.manual,
          duplicateFromBill: Bill(
            uuid: 'original',
            totalAmount: 100,
            itemCount: 1,
            paidAmount: 100,
            customerName: 'Original customer',
            items: [
              BillItem(
                productName: 'Item',
                quantity: 1,
                sellingPriceSnapshot: 100.49,
              ),
            ],
          ),
        ),
      ),
    );
    await settleIo(tester);
    await tester.tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
    await settleIo(tester);
    expect(find.text('Create Bill'), findsOneWidget);
  }

  testWidgets(
    'duplicate requires explicit settlement and raw invalid partial remains entered',
    (tester) async {
      await open(tester);
      await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
      expect(
        find.text('Choose full, partial or unpaid settlement.'),
        findsOneWidget,
      );
      expect(await tester.runAsync(db.getAllBills), isEmpty);
      await tapVisible(tester, find.text('Partial'));
      expect(
        find.textContaining(
          'Unassigned balances can be collected from the invoice.',
        ),
        findsOneWidget,
      );
      final amount = find.byKey(const ValueKey('checkout-partial-amount'));
      await tester.enterText(amount, '50.000');
      await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
      expect(tester.widget<TextField>(amount).controller!.text, '50.000');
      expect(find.textContaining('at most two decimal places'), findsOneWidget);
      expect(await tester.runAsync(db.getAllBills), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
  testWidgets(
    'failed commit freezes exact request and retries once without losing fields',
    (tester) async {
      await open(tester);
      final sql = await db.database;
      await tester.runAsync(
        () => sql.execute(
          "CREATE TRIGGER fail_checkout BEFORE INSERT ON checkout_acceptances BEGIN SELECT RAISE(ABORT, 'fixture failed save'); END",
        ),
      );
      await tapVisible(tester, find.text('Partial'));
      final amount = find.byKey(const ValueKey('checkout-partial-amount'));
      await tester.enterText(amount, '25.01');
      await tapVisible(
        tester,
        find.byKey(const ValueKey('checkout-unassigned-consent')),
      );
      await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
      await settleIo(tester);
      expect(tester.widget<TextField>(amount).controller!.text, '25.01');
      expect(find.text('Original customer'), findsOneWidget);
      expect(find.textContaining('Checkout details are kept.'), findsOneWidget);
      expect(await tester.runAsync(db.getAllBills), isEmpty);
      await tester.runAsync(() => sql.execute('DROP TRIGGER fail_checkout'));
      await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
      // A second tap while save is pending must not enqueue a second invoice.
      await tester.tap(find.byKey(const ValueKey('checkout-save')));
      await settleIo(tester);
      final bills = await tester.runAsync(db.getAllBills);
      expect(bills, hasLength(1));
      expect(bills!.single.paidAmount, 25.01);
      expect(bills.single.balanceDue, 74.99);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
  testWidgets(
    'settings change retains entries and explicit review requires new settlement',
    (tester) async {
      await open(tester);
      final sql = await db.database;
      await tester.runAsync(
        () => sql.update('bill_settings', {'round_off_total': 0}),
      );
      await tapVisible(tester, find.text('Paid full'));
      await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
      await settleIo(tester);
      expect(await tester.runAsync(db.getAllBills), isEmpty);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('checkout-review-latest')),
      );
      await settleIo(tester);
      expect(find.text('Original customer'), findsOneWidget);
      final settlement = tester
          .widgetList<SegmentedButton<String>>(
            find.byType(SegmentedButton<String>),
          )
          .where(
            (widget) => widget.segments.any(
              (segment) => segment.value == Bill.statusPaid,
            ),
          )
          .single;
      expect(settlement.selected, isEmpty);
      expect(find.text('₹100.49'), findsWidgets);
      await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Choose full, partial or unpaid settlement.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
}
