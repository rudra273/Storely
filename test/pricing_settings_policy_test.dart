import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/pricing_default_input.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/screens/pricing_screen.dart';

void main() {
  group('effective legacy numeric policy', () {
    for (final input in [
      'NaN',
      'Infinity',
      '-1',
      '1_0',
      '١٨',
      '1,000',
      '',
      ' ',
      '101',
      '100.000000000000000001',
      '1e-19',
    ]) {
      test('rejects rate $input before double conversion', () {
        expect(PricingDefaultNumber.parse(input, maximum: 100), isNull);
      });
    }
    for (final entry in {
      '  +1e1  ': 10.0,
      '.5': .5,
      '1.': 1.0,
      '1e-18': 1e-18,
      '1.230000000000000000000': 1.23,
      '-0e9999': 0.0,
      '100.000000000000000000000': 100.0,
    }.entries) {
      test(
        'accepts exact legacy ${entry.key}',
        () => expect(
          PricingDefaultNumber.parse(entry.key, maximum: 100)!.value,
          entry.value,
        ),
      );
    }
    test('overhead has an independent exact bound', () {
      expect(
        PricingDefaultNumber.parse('999999999', maximum: 999999999)!.value,
        999999999,
      );
      expect(
        PricingDefaultNumber.parse('999999999.000000001', maximum: 999999999),
        isNull,
      );
    });
    test('explicit exact scheme wins and only literal legacy 1 falls back', () {
      for (final scheme in ['regular', 'composition', 'unregistered']) {
        for (final flag in ['0', '1']) {
          expect(
            GlobalPricingSettings.fromStoredValues({
              'gst_scheme': scheme,
              'gst_registered': flag,
            }).gstRegistered,
            scheme == 'regular',
          );
        }
      }
      expect(
        GlobalPricingSettings.fromStoredValues({
          'gst_scheme': 'REGULAR',
          'gst_registered': '1',
        }).gstRegistered,
        isTrue,
      );
      expect(
        GlobalPricingSettings.fromStoredValues({
          'gst_registered': 'true',
        }).gstRegistered,
        isFalse,
      );
      expect(
        GlobalPricingSettings.fromStoredValues({
          'gst_registered': ' 1 ',
        }).gstRegistered,
        isFalse,
      );
    });
    test(
      'unchanged legacy custom GST and deeper precision do not block a margin edit',
      () {
        final stored = GlobalPricingSettings.fromStoredValues({
          'default_gst_percent': '2.5000',
          'default_overhead_cost': '10.123456789012345678',
          'default_profit_margin_percent': '12.345678901234567890',
        });
        final edited = stored.editedDefaults(
          gst: stored.gstInput,
          overhead: stored.overheadInput,
          margin: '12.345',
        );
        expect(edited.defaultProfitMarginPercent, 12.345);
        expect(edited.gstInput, '2.5000');
        expect(edited.overheadInput, '10.123456789012345678');
        expect(
          () => stored.editedDefaults(
            gst: '7',
            overhead: stored.overheadInput,
            margin: stored.marginInput,
          ),
          throwsFormatException,
        );
        expect(
          () => stored.editedDefaults(
            gst: stored.gstInput,
            overhead: '1.001',
            margin: stored.marginInput,
          ),
          throwsFormatException,
        );
        expect(
          () => stored.editedDefaults(
            gst: stored.gstInput,
            overhead: stored.overheadInput,
            margin: '12.3456',
          ),
          throwsFormatException,
        );
      },
    );
  });

  final db = DatabaseHelper.instance;
  Future<void> put(String key, String value) async {
    final sql = await db.database;
    final source = (await sql.query('app_settings', limit: 1)).single;
    await sql.insert(
      'app_settings',
      {...source, 'key': key, 'value': value}..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> raw(String key) async =>
      (await (await db.database).query(
            'app_settings',
            columns: ['value'],
            where: 'key = ?',
            whereArgs: [key],
          )).single['value']
          as String;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await db.close();
    DatabaseHelper.databaseFileName = 'pricing-settings-policy.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await db.saveGlobalPricingSettings(const GlobalPricingSettings());
  });
  tearDown(() async {
    db.assertAdminMutation = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  for (final scheme in ['regular', 'composition', 'unregistered']) {
    test(
      'public and product transaction agree for $scheme with conflicting legacy flag',
      () async {
        await put('gst_scheme', scheme);
        await put('gst_registered', scheme == 'regular' ? '0' : '1');
        await put('default_gst_percent', '18');
        await put('default_overhead_cost', '10');
        await put('default_profit_margin_percent', '12.345');
        final product = Product(
          name: 'Scheme $scheme',
          purchasePrice: 1000,
          quantity: 1,
        );
        final expected = scheme == 'regular' ? 1338.92771 : 1336.90550;
        expect(
          (await db.resolveProductPrice(product)).sellingPrice,
          closeTo(expected, 1e-8),
        );
        final inserted = (await db.getProductById(
          await db.insertProduct(product),
        ))!;
        expect(inserted.sellingPrice, closeTo(expected, 1e-8));
      },
    );
  }
  test(
    'both contexts use effective numeric defaults without rewriting malformed legacy rows',
    () async {
      await put('default_gst_percent', 'NaN');
      await put('default_overhead_cost', 'Infinity');
      await put('default_profit_margin_percent', '100.000000000000000001');
      final settings = await db.getGlobalPricingSettings();
      expect(settings.defaultGstPercent, 18);
      expect(settings.defaultOverheadCost, 0);
      expect(settings.defaultProfitMarginPercent, 0);
      final product = Product(
        name: 'Fallback',
        purchasePrice: 100,
        quantity: 1,
      );
      expect((await db.resolveProductPrice(product)).sellingPrice, 118);
      expect(
        (await db.getProductById(
          await db.insertProduct(product),
        ))!.sellingPrice,
        118,
      );
      await db.saveGlobalPricingSettings(
        settings.copyWith(showPurchasePriceGlobally: true),
      );
      expect(await raw('default_gst_percent'), 'NaN');
      expect(await raw('default_overhead_cost'), 'Infinity');
      expect(
        await raw('default_profit_margin_percent'),
        '100.000000000000000001',
      );
    },
  );
  test(
    'edited field writes preserve other exact legacy text and stale baseline rolls back all edits',
    () async {
      await put('default_gst_percent', '2.5000');
      await put('default_overhead_cost', '10.123456789012345678');
      await put('default_profit_margin_percent', '12.345678901234567890');
      final baseline = await db.captureSettingsEditBaseline();
      final original = await db.getGlobalPricingSettings();
      final edited = original.editedDefaults(
        gst: original.gstInput,
        overhead: original.overheadInput,
        margin: '12.345',
      );
      await db.savePricingSettingsWithBaseline(edited, baseline: baseline);
      expect(await raw('default_gst_percent'), '2.5000');
      expect(await raw('default_overhead_cost'), '10.123456789012345678');
      expect(await raw('default_profit_margin_percent'), '12.345');
      await expectLater(
        db.savePricingSettingsWithBaseline(
          edited.copyWith(defaultOverheadCost: 20),
          baseline: baseline,
        ),
        throwsStateError,
      );
      expect(await raw('default_overhead_cost'), '10.123456789012345678');
    },
  );
  test(
    'refreshing formula prices preserves finalized bill and item snapshots',
    () async {
      final id = await db.insertProduct(
        Product(name: 'Historical', purchasePrice: 100, quantity: 10),
      );
      final item = await db.buildBillItemForProduct(
        (await db.getProductById(id))!,
      );
      final billId = await db.insertBill(
        Bill(totalAmount: item.subtotal, itemCount: 1),
        [item],
      );
      final before = (await db.getBillById(billId))!;
      await put('gst_scheme', 'regular');
      await put('gst_registered', '0');
      await put('default_profit_margin_percent', '12.345');
      await db.refreshAllProductSellingPrices();
      final after = (await db.getBillById(billId))!;
      expect(after.toMap(), before.toMap());
      expect(
        after.items.single.toMap(billId),
        before.items.single.toMap(billId),
      );
    },
  );
  testWidgets(
    'existing editor retains three decimals, rejects invalid edits atomically, then saves corrected margin',
    (tester) async {
      await tester.runAsync(
        () => put('default_profit_margin_percent', '12.345'),
      );
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 80));
        }
      }

      await tester.pumpWidget(const MaterialApp(home: PricingScreen()));
      await settle();
      Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      expect(
        tester
            .widget<TextField>(field('Default Profit Margin %'))
            .controller!
            .text,
        '12.345',
      );
      await tester.enterText(field('Default Overhead ₹'), '10');
      await tester.enterText(field('Default Profit Margin %'), 'NaN');
      await tester.tap(find.text('Save Defaults'));
      await settle();
      expect(await tester.runAsync(() => raw('default_overhead_cost')), '0.0');
      expect(
        tester
            .widget<TextField>(field('Default Profit Margin %'))
            .controller!
            .text,
        'NaN',
      );
      await tester.enterText(field('Default Profit Margin %'), '12.345');
      await tester.tap(find.text('Save Defaults'));
      await settle();
      expect(await tester.runAsync(() => raw('default_overhead_cost')), '10');
      expect(
        await tester.runAsync(() => raw('default_profit_margin_percent')),
        '12.345',
      );
      await tester.pumpWidget(const SizedBox());
      await settle();
    },
  );
}
