import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/low_stock_threshold.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/home/home_section_settings.dart';
import 'package:storely/screens/store_screen.dart';
import 'package:storely/l10n/l10n.dart';

void main() {
  for (final entry in {
    '0': 0.0,
    ' \t1.2345\r\n': 1.2345,
    '0005.000000': 5.0,
    '999999999.0000': 999999999.0,
  }.entries) {
    test(
      'exact threshold accepts ${entry.key}',
      () => expect(LowStockThreshold.parse(entry.key)!.value, entry.value),
    );
  }
  for (final input in [
    '',
    ' ',
    '-1',
    '-0',
    '+1',
    '1e2',
    '1_0',
    'NaN',
    'Infinity',
    '.5',
    '5.',
    '1.00001',
    '999999999.0001',
    '1000000000',
    '٥',
    '\u00a05',
    '5\u00a0',
  ]) {
    test(
      'exact threshold rejects $input',
      () => expect(LowStockThreshold.parse(input), isNull),
    );
  }
  test(
    'warning comparison preserves four decimals, overrides and tiny SQL roundoff only',
    () {
      Product product(double qty, {double? reorder, bool tracked = true}) =>
          Product(
            name: 'Threshold',
            quantity: qty,
            reorderLevel: reorder,
            trackStock: tracked,
          );
      expect(product(1.2345).isLowStock(1.2345), isTrue);
      expect(product(1.2346).isLowStock(1.2345), isFalse);
      expect(product(5.0000001).isLowStock(5), isFalse);
      expect(product(.1 + .2 - .3).isLowStock(0), isTrue);
      expect(product(.0001).isLowStock(0), isFalse);
      expect(product(.0001, reorder: 0).isLowStock(5), isFalse);
      expect(product(0, reorder: 0).isLowStock(5), isTrue);
      expect(product(-5, tracked: false).isLowStock(5), isFalse);
      expect(product(double.infinity).isLowStock(5), isFalse);
      expect(stockQuantityEpsilon, 1e-6);
    },
  );
  final db = DatabaseHelper.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await db.close();
    DatabaseHelper.databaseFileName = 'low-stock-policy.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
  });
  tearDown(() async {
    db.assertAdminMutation = null;
    db.isAdminMutationAllowed = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  Future<void> raw(String value, {bool deleted = false}) async {
    final sql = await db.database;
    await sql.insert('app_settings', {
      'shop_id': await db.currentShopId(),
      'key': 'low_stock_threshold',
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_at': deleted ? DateTime.now().toUtc().toIso8601String() : null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  test(
    'active setting handles missing deleted invalid zero and decimal reopen',
    () async {
      expect(await db.getLowStockThreshold(), 5);
      for (final value in ['NaN', '-1', '1e0', '5.00001', '\u00a05']) {
        await raw(value);
        expect(await db.getLowStockThreshold(), 5, reason: value);
      }
      await raw('0');
      expect(await db.getLowStockThreshold(), 0);
      await raw('1.2345', deleted: true);
      expect(await db.getLowStockThreshold(), 5);
      await db.saveLowStockThreshold(1.2345);
      await db.close();
      expect(await db.getLowStockThreshold(), 1.2345);
    },
  );
  test(
    'scope baseline and role failures keep current persisted threshold',
    () async {
      await db.saveLowStockThreshold(2.5);
      final baseline = await db.captureSettingsEditBaseline();
      await raw('3.25');
      await expectLater(
        db.saveLowStockThreshold(1.2345, baseline: baseline),
        throwsStateError,
      );
      expect(await db.getLowStockThreshold(), 3.25);
      final current = await db.captureSettingsEditBaseline();
      db.isAdminMutationAllowed = () => false;
      await expectLater(
        db.saveLowStockThreshold(1.2345, baseline: current),
        throwsStateError,
      );
      expect(await db.getLowStockThreshold(), 3.25);
      await expectLater(
        db.saveLowStockThreshold(double.nan),
        throwsFormatException,
      );
    },
  );
  test(
    'threshold queries stay within active shop and SQLite fractional sums classify correctly',
    () async {
      await db.saveLowStockThreshold(.3);
      final sql = await db.database;
      await sql.insert('app_settings', {
        'shop_id': 'foreign-shop',
        'key': 'low_stock_threshold',
        'value': '99',
        'updated_at': DateTime.now().toIso8601String(),
      });
      expect(await db.getLowStockThreshold(), .3);
      final sum =
          (await sql.rawQuery('SELECT 0.1 + 0.2 AS qty')).single['qty']
              as double;
      expect(
        Product(
          name: 'SQL sum',
          quantity: sum,
        ).isLowStock(await db.getLowStockThreshold()),
        isTrue,
      );
      expect(
        Product(name: 'Actual above', quantity: sum + .0001).isLowStock(.3),
        isFalse,
      );
    },
  );
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets(
    'Home keeps invalid or failed raw entries and supports repeated decimal Done saves',
    (tester) async {
      var fail = false;
      final saved = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showNeedsAttentionSettings(
                context,
                threshold: 5,
                onThreshold: (value) async {
                  if (fail) throw StateError('Keep original shop');
                  saved.add(value);
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('low-stock-threshold-input'));
      expect(
        tester.widget<TextField>(input).keyboardType,
        const TextInputType.numberWithOptions(decimal: true),
      );
      await tester.enterText(input, '1e2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '1e2');
      expect(saved, isEmpty);
      expect(find.textContaining('up to 4 decimals'), findsOneWidget);
      fail = true;
      await tester.enterText(input, '1.2345');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '1.2345');
      expect(find.textContaining('Keep original shop'), findsOneWidget);
      expect(saved, isEmpty);
      fail = false;
      await tester.enterText(input, '1.2345');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.enterText(input, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(saved, [1.2345, 0]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Store editor keeps invalid and stale entries, then corrected decimal saves on reopen',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => db.saveLowStockThreshold(5));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const StoreScreen(),
        ),
      );
      await settle(tester);
      for (
        var attempt = 0;
        attempt < 150 &&
            find
                .byKey(const ValueKey('store-settings-search'))
                .evaluate()
                .isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.scrollUntilVisible(
        find.text('Low-stock alert'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Low-stock alert'));
      await settle(tester);
      final input = find.byKey(const ValueKey('low-stock-threshold-input'));
      await tester.enterText(input, '1.23456');
      await tester.tap(find.byKey(const ValueKey('low-stock-threshold-save')));
      await settle(tester);
      expect(tester.widget<TextFormField>(input).controller!.text, '1.23456');
      expect(await tester.runAsync(db.getLowStockThreshold), 5);
      await tester.enterText(input, '1.2345');
      await tester.runAsync(() => raw('3'));
      await tester.tap(find.byKey(const ValueKey('low-stock-threshold-save')));
      await settle(tester);
      expect(tester.widget<TextFormField>(input).controller!.text, '1.2345');
      expect(await tester.runAsync(db.getLowStockThreshold), 3);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Low-stock alert'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Low-stock alert'));
      await settle(tester);
      await tester.enterText(input, '1.2345');
      await tester.tap(find.byKey(const ValueKey('low-stock-threshold-save')));
      await settle(tester);
      expect(input, findsNothing);
      expect(await tester.runAsync(db.getLowStockThreshold), 1.2345);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
}
