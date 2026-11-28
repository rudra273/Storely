import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/bill_totals.dart';
import 'package:storely/models/native_sale_posting.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/products_screen.dart';
import 'package:storely/screens/scan_screen.dart';

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
  await settleIo(tester);
}

Future<void> enterField(WidgetTester tester, Finder finder, String text) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.enterText(finder, text);
  await settleIo(tester);
}

/// Replays fixed digits so generated codes are predictable.
class _SequenceRandom implements Random {
  final List<int> digits;
  var _index = 0;

  _SequenceRandom(this.digits);

  @override
  int nextInt(int max) => digits[_index++ % digits.length] % max;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

BillItem _line({
  double price = 100,
  double qty = 1,
  double gst = 0,
  double cess = 0,
  String taxType = TaxType.taxable,
  String? taxMode,
}) => BillItem(
  productName: 'Line',
  sellingPriceSnapshot: price,
  quantity: qty,
  gstPercentSnapshot: gst,
  cessPercentSnapshot: cess,
  taxTypeSnapshot: taxType,
  taxMode: taxMode,
);

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db.onDatabaseChanged = null;
    db.assertAdminMutation = null;
    db.isAdminMutationAllowed = null;
    await db.close();
    DatabaseHelper.databaseFileName = 'm1-0-items.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await db.saveBillSettings(BillSettings());
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  group('cess math (ExactDecimal)', () {
    test('exclusive: GST and cess are added on the taxable value', () {
      final result = BillTotals.calculate(
        [_line(price: 100, qty: 2, gst: 28, cess: 12)],
        taxMode: Bill.taxModeExclusive,
        gstRegistered: true,
        interState: false,
        roundOffMode: Bill.roundOffNone,
      );
      final t = result.totals;
      expect(t.taxableAmount, 200);
      expect(t.gstAmount, 56);
      expect(t.cgstAmount, 28);
      expect(t.sgstAmount, 28);
      expect(t.cessAmount, 24);
      expect(t.grandTotal, 280);
      final line = result.items.single;
      expect(line.totalCess, 24);
      expect(line.totalGst, 56);
      expect(line.lineAmount, 280);
      expect(line.cessPercentSnapshot, 12);
    });

    test('inclusive: taxable = net / (1 + (gst + cess) / 100)', () {
      final result = BillTotals.calculate(
        [_line(price: 140, gst: 28, cess: 12)],
        taxMode: Bill.taxModeInclusive,
        gstRegistered: true,
        interState: true,
        roundOffMode: Bill.roundOffNone,
      );
      final t = result.totals;
      expect(t.taxableAmount, 100);
      expect(t.igstAmount, 28);
      expect(t.cessAmount, 12);
      expect(t.grandTotal, 140);
      expect(t.taxableAmount + t.gstAmount + t.cessAmount, 140);
    });

    test('inclusive rounding keeps taxable + GST + cess = line total', () {
      final result = BillTotals.calculate(
        [_line(price: 99.99, qty: 3, gst: 18, cess: 3)],
        gstRegistered: true,
        interState: false,
        roundOffMode: Bill.roundOffNone,
      );
      final t = result.totals;
      // 299.97 / 1.21 = 247.909...
      expect(t.taxableAmount, 247.91);
      expect(t.cessAmount, 7.44);
      expect(t.gstAmount, 44.62);
      expect(t.grandTotal, 299.97);
      final saved = BillTotals.fromTaxedItems(
        result.items,
        roundOff: false,
        roundOffMode: Bill.roundOffNone,
      );
      expect(saved.cessAmount, t.cessAmount);
      expect(saved.grandTotal, t.grandTotal);
    });

    test('inclusive cess-only line puts the rounding remainder into cess', () {
      final result = BillTotals.calculate(
        [_line(price: 10.01, qty: 3, gst: 0, cess: 12)],
        gstRegistered: true,
        interState: false,
        roundOffMode: Bill.roundOffNone,
      );
      final t = result.totals;
      expect(t.gstAmount, 0);
      expect(t.taxableAmount + t.cessAmount, closeTo(30.03, 1e-9));
      final line = result.items.single;
      expect(line.totalGst, 0);
      expect(line.totalTaxableValue + line.totalCess, closeTo(30.03, 1e-9));
    });

    test('unregistered shop never charges cess', () {
      final t = BillTotals.calculate(
        [_line(price: 100, gst: 28, cess: 12)],
        taxMode: Bill.taxModeExclusive,
        gstRegistered: false,
        interState: false,
        roundOffMode: Bill.roundOffNone,
      ).totals;
      expect(t.cessAmount, 0);
      expect(t.grandTotal, 100);
    });
  });

  group('None / Tax Exempt', () {
    for (final type in [TaxType.none, TaxType.exempt]) {
      for (final mode in [Bill.taxModeInclusive, Bill.taxModeExclusive]) {
        test('$type ($mode) carries zero GST and cess', () {
          final result = BillTotals.calculate(
            [_line(price: 250, qty: 2, gst: 18, cess: 12, taxType: type)],
            taxMode: mode,
            gstRegistered: true,
            interState: false,
            roundOffMode: Bill.roundOffNone,
          );
          final t = result.totals;
          expect(t.gstAmount, 0);
          expect(t.cessAmount, 0);
          expect(t.taxableAmount, 500);
          expect(t.grandTotal, 500);
          expect(result.items.single.taxTypeSnapshot, type);
        });
      }
    }

    test('pricing treats exempt items as GST-free', () async {
      final global = await db.getGlobalPricingSettings();
      final breakdown = PricingCalculator.resolveProductPrice(
        Product(
          name: 'Milk',
          sellingPrice: 50,
          directPriceToggle: true,
          manualPrice: 50,
          gstPercent: 5,
          taxType: TaxType.exempt,
          quantity: 1,
        ),
        GlobalPricingSettings(
          defaultGstPercent: global.defaultGstPercent,
          gstRegistered: true,
        ),
        null,
      );
      expect(breakdown.gstPercent, 0);
      expect(breakdown.outputGstAmount, 0);
    });
  });

  group('service items', () {
    test(
      'billing a service never moves stock or writes a ledger row',
      () async {
        final id = await db.insertProduct(
          Product(
            name: 'Repair Labour',
            itemType: ItemType.service,
            sellingPrice: 300,
            directPriceToggle: true,
            manualPrice: 300,
            gstPercent: 18,
            quantity: 0,
          ),
        );
        final service = (await db.getProductById(id))!;
        expect(service.isService, isTrue);
        expect(service.trackStock, isFalse);
        expect(service.quantity, 0);

        final item = await db.buildBillItemForProduct(service);
        item.quantity = 3;
        expect(item.itemTypeSnapshot, ItemType.service);
        final calc = BillTotals.calculate(
          [item],
          gstRegistered: false,
          interState: false,
          roundOffMode: Bill.roundOffNone,
        );
        await db.insertBill(
          Bill(totalAmount: calc.totals.grandTotal, itemCount: 1),
          calc.items,
        );

        final sql = await db.database;
        final movements = await sql.query(
          'stock_movements',
          where: 'product_id = ?',
          whereArgs: [id],
        );
        expect(movements, isEmpty);
        expect((await db.getProductById(id))!.quantity, 0);
        final lines = await sql.query('bill_items');
        expect(lines.single['item_type_snapshot'], ItemType.service);
      },
    );

    test('a product line on the same bill still deducts stock', () async {
      final id = await db.insertProduct(
        Product(name: 'Oil', sellingPrice: 100, quantity: 10),
      );
      final product = (await db.getProductById(id))!;
      final item = await db.buildBillItemForProduct(product);
      item.quantity = 4;
      await db.insertBill(Bill(totalAmount: 400, itemCount: 1), [item]);
      expect((await db.getProductById(id))!.quantity, 6);
    });
  });

  group('native sale payload (API M1.0 contract)', () {
    String id(int value) =>
        '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

    test('service + cess line: no movement_uuid, GST-only tax_amount', () {
      final created = DateTime(2026, 11, 28, 10, 0, 0, 1);
      final taxed = BillTotals.calculate(
        [
          BillItem(
            uuid: id(2),
            shopId: 'shop',
            billUuid: id(1),
            productUuid: id(3),
            productName: 'Hookah service',
            sellingPriceSnapshot: 140,
            gstPercentSnapshot: 28,
            cessPercentSnapshot: 12,
            itemTypeSnapshot: ItemType.service,
            createdAt: created,
          ),
        ],
        gstRegistered: true,
        interState: false,
        roundOffMode: Bill.roundOffNone,
      );
      final t = taxed.totals;
      final capture = {
        'version': 1,
        'device_id': 'device-001',
        'invoice':
            Bill(
                uuid: id(1),
                shopId: 'shop',
                billNumber: 'INV-1',
                subtotalAmount: t.subtotal,
                taxableAmount: t.taxableAmount,
                cgstAmount: t.cgstAmount,
                sgstAmount: t.sgstAmount,
                cessAmount: t.cessAmount,
                roundOffMode: Bill.roundOffNone,
                totalAmount: t.grandTotal,
                paidAmount: t.grandTotal,
                balanceDue: 0,
                itemCount: 1,
                createdAt: created,
                deviceId: 'device-001',
              ).toMap()
              ..remove('id')
              ..remove('customer_id'),
        'items': [
          taxed.items.single.toMap(1, billUuid: id(1))
            ..remove('id')
            ..remove('bill_id')
            ..remove('product_id'),
        ],
        'payments': [
          {
            'uuid': id(5),
            'shop_id': 'shop',
            'bill_uuid': id(1),
            'amount': t.grandTotal,
            'payment_method': 'cash',
            'payment_reference': null,
            'received_at': created.toIso8601String(),
            'deleted_at': null,
          },
        ],
        'movements': <dynamic>[],
      };
      final body = nativeSaleRequest(jsonEncode(capture))!;
      final line = (body['lines'] as List).single as Map;
      expect(line.containsKey('movement_uuid'), isFalse);
      expect(line['taxable_amount'], '100.00');
      expect(line['tax_amount'], '28.00');
      expect(line['cess_amount'], '12.00');
      expect(line['total_amount'], '140.00');
      expect(body['cess_amount'], '12.00');
    });
  });

  group('item codes', () {
    test('ean13 check digit', () {
      expect(ean13CheckDigit('400638133393'), 1);
      expect(ean13CheckDigit('590123412345'), 7);
    });

    test('generate skips codes already used as code or barcode', () async {
      // First attempt: 2 + eleven 1s; second attempt: 2 + eleven 3s.
      final taken = '211111111111${ean13CheckDigit('211111111111')}';
      await db.insertProduct(
        Product(name: 'Taken', sellingPrice: 10, quantity: 1, barcode: taken),
      );
      final code = await db.generateUniqueItemCode(
        random: _SequenceRandom([...List.filled(11, 1), ...List.filled(11, 3)]),
      );
      expect(code, isNot(taken));
      expect(code, '233333333333${ean13CheckDigit('233333333333')}');
      expect(code.length, 13);
      expect(await db.isItemCodeAvailable(code), isTrue);
      expect(await db.isItemCodeAvailable(taken), isFalse);
    });
  });

  group('bulk GST and category defaults', () {
    test('bulkSetProductTax updates tax only on selected items', () async {
      final a = await db.insertProduct(
        Product(name: 'A', sellingPrice: 10, quantity: 1, gstPercent: 5),
      );
      final b = await db.insertProduct(
        Product(name: 'B', sellingPrice: 10, quantity: 1, gstPercent: 5),
      );
      final c = await db.insertProduct(
        Product(name: 'C', sellingPrice: 10, quantity: 1, gstPercent: 5),
      );
      final changed = await db.bulkSetProductTax(
        [a, b],
        taxType: TaxType.taxable,
        gstPercent: 28,
        cessPercent: 12,
      );
      expect(changed, 2);
      for (final id in [a, b]) {
        final p = (await db.getProductById(id))!;
        expect(p.gstPercent, 28);
        expect(p.cessPercent, 12);
        expect(p.quantity, 1);
      }
      expect((await db.getProductById(c))!.gstPercent, 5);

      await db.bulkSetProductTax(
        [a],
        taxType: TaxType.exempt,
        gstPercent: 18,
        cessPercent: 3,
      );
      final exempt = (await db.getProductById(a))!;
      expect(exempt.taxType, TaxType.exempt);
      expect(exempt.gstPercent, 0);
      expect(exempt.cessPercent, 0);
    });

    test('category tax defaults round-trip', () async {
      await db.saveCategoryPricing(
        const CategoryPricingSettings(
          name: 'Tobacco',
          taxType: TaxType.taxable,
          gstPercent: 28,
          cessPercent: 5,
        ),
      );
      final saved = (await db.getCategoryPricing('Tobacco'))!;
      expect(saved.taxType, TaxType.taxable);
      expect(saved.gstPercent, 28);
      expect(saved.cessPercent, 5);
      expect(saved.hasTaxDefault, isTrue);
      final id = await db.insertProduct(
        Product(
          name: 'Pan',
          sellingPrice: 10,
          quantity: 1,
          category: 'Tobacco',
        ),
      );
      expect(await db.getProductIdsInCategory('tobacco'), [id]);
    });
  });

  group('full-screen item form', () {
    Future<void> pumpForm(
      WidgetTester tester, {
      Product? product,
      List<String> categories = const [],
    }) async {
      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ItemFormScreen(
            product: product,
            categories: categories,
            units: const [],
            scanBarcode: (_) async => '8901234567890',
          ),
        ),
      );
      await settleIo(tester);
    }

    testWidgets('is a full Scaffold page and saves a service with SAC', (
      tester,
    ) async {
      await pumpForm(tester);
      expect(find.text('Create Item'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('quick-add-name')),
          matching: find.byType(Scaffold),
        ),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);

      await enterField(
        tester,
        find.byKey(const ValueKey('quick-add-name')),
        'Haircut',
      );
      await enterField(
        tester,
        find.byKey(const ValueKey('quick-add-price')),
        '150',
      );
      await tapVisible(tester, find.text('Service'));
      await tapVisible(tester, find.byKey(const ValueKey('tax-gst-18')));
      await tapVisible(tester, find.byKey(const ValueKey('item-more-details')));
      expect(find.text('SAC code'), findsOneWidget);
      expect(find.text('HSN code'), findsNothing);
      expect(find.byKey(const ValueKey('quick-add-qty')), findsNothing);
      await enterField(
        tester,
        find.byKey(const ValueKey('item-hsn')),
        '999721',
      );
      await tapVisible(tester, find.byKey(const ValueKey('quick-add-save')));

      final saved = (await tester.runAsync(db.getAllProducts))!.single;
      expect(saved.name, 'Haircut');
      expect(saved.itemType, ItemType.service);
      expect(saved.trackStock, isFalse);
      expect(saved.gstPercent, 18);
      expect(saved.hsnCode, '999721');
      expect(saved.sellingPrice, 150);
    });

    testWidgets('Generate fills a unique code and asks before replacing', (
      tester,
    ) async {
      await pumpForm(tester);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('item-code-generate')),
      );
      final field = find.byKey(const ValueKey('quick-add-barcode'));
      final first = tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .controller
          .text;
      expect(first, matches(RegExp(r'^2\d{12}$')));
      expect(int.parse(first[12]), ean13CheckDigit(first.substring(0, 12)));

      await tapVisible(tester, find.byKey(const ValueKey('item-code-scan')));
      expect(find.text('Replace item code?'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('item-code-keep')));
      expect(find.text(first), findsOneWidget);

      await tapVisible(tester, find.byKey(const ValueKey('item-code-scan')));
      await tapVisible(tester, find.byKey(const ValueKey('item-code-replace')));
      expect(find.text('8901234567890'), findsOneWidget);
    });

    testWidgets('picking a category fills its default GST and cess', (
      tester,
    ) async {
      await tester.runAsync(
        () => db.saveCategoryPricing(
          const CategoryPricingSettings(
            name: 'Aerated Drinks',
            taxType: TaxType.taxable,
            gstPercent: 28,
            cessPercent: 12,
          ),
        ),
      );
      await pumpForm(tester, categories: const ['Aerated Drinks']);
      await tapVisible(tester, find.text('No Category'));
      await tapVisible(tester, find.text('Aerated Drinks').last);

      ChoiceChip chip(String key) =>
          tester.widget<ChoiceChip>(find.byKey(ValueKey(key)));
      expect(chip('tax-gst-28').selected, isTrue);
      expect(find.text('Cess 12%'), findsOneWidget);
      expect(
        find.textContaining('From category Aerated Drinks'),
        findsOneWidget,
      );

      // Still overridable per item.
      await tapVisible(tester, find.byKey(const ValueKey('tax-exempt')));
      expect(chip('tax-exempt').selected, isTrue);
      expect(find.text('Cess 12%'), findsNothing);

      await enterField(
        tester,
        find.byKey(const ValueKey('quick-add-name')),
        'Soda',
      );
      await enterField(
        tester,
        find.byKey(const ValueKey('quick-add-price')),
        '20',
      );
      await tapVisible(tester, find.byKey(const ValueKey('quick-add-save')));
      final saved = (await tester.runAsync(db.getAllProducts))!.single;
      expect(saved.category, 'Aerated Drinks');
      expect(saved.taxType, TaxType.exempt);
      expect(saved.cessPercent, 0);
    });
  });

  group('create bill party bar', () {
    testWidgets('defaults to Walk-in / Cash above item entry', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ScanScreen(initialMode: BillingEntryMode.manual),
        ),
      );
      await settleIo(tester);

      final bar = find.byKey(const ValueKey('bill-party-bar'));
      expect(bar, findsOneWidget);
      expect(find.text(walkInPartyLabel), findsOneWidget);
      final search = find.byKey(const ValueKey('checkout-product-search'));
      expect(search, findsOneWidget);
      expect(tester.getTopLeft(bar).dy, lessThan(tester.getTopLeft(search).dy));

      // Picking a party never blocks billing and survives into checkout.
      await tapVisible(tester, bar);
      await tapVisible(tester, find.byKey(const ValueKey('party-add-new')));
      await enterField(
        tester,
        find.byKey(const ValueKey('party-new-name')),
        'Ravi Traders',
      );
      await tapVisible(tester, find.byKey(const ValueKey('party-new-save')));
      expect(find.text('Ravi Traders'), findsOneWidget);

      await tapVisible(tester, bar);
      await tapVisible(tester, find.byKey(const ValueKey('party-walk-in')));
      expect(find.text(walkInPartyLabel), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    });
  });
}
