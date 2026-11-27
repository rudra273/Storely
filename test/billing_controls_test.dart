import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/bill_totals.dart';
import 'package:storely/models/held_bill.dart';
import 'package:storely/models/native_sale_posting.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/screens/scan_screen.dart';
import 'package:storely/utils/exact_decimal.dart';
import 'package:storely/utils/test_keys.dart';

String _uuid(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';

Future<void> _settle(WidgetTester tester) async {
  for (var n = 0; n < 8; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ExactDecimal', () {
    test('avoids binary float traps and rounds half away from zero', () {
      final price = ExactDecimal.parse('19.99');
      final qty = ExactDecimal.fromInt(3);
      final taxable = (price * qty).roundMoney();
      expect(taxable.toFixed(2), '59.97');

      final gst = (price * ExactDecimal.parse('0.18') * qty).roundMoney();
      expect(gst.toFixed(2), '10.79');

      expect(ExactDecimal.parse('1.005').roundMoney().toFixed(2), '1.01');
      expect(ExactDecimal.parse('-1.005').roundMoney().toFixed(2), '-1.01');
      expect(ExactDecimal.parse('2.675').roundMoney().toFixed(2), '2.68');
      expect(
        ExactDecimal.parse('100.01')
            .roundUpToMultiple(ExactDecimal.fromInt(1))
            .toFixed(2),
        '101.00',
      );
      expect(
        ExactDecimal.parse('-101.00')
            .roundUpToMultiple(ExactDecimal.fromInt(10))
            .toFixed(2),
        '-110.00',
      );
      expect(
        ExactDecimal.parse('100.99')
            .roundDownToMultiple(ExactDecimal.fromInt(1))
            .toFixed(2),
        '100.00',
      );
      expect(
        ExactDecimal.parse('102.50')
            .roundNearestToMultiple(ExactDecimal.fromInt(5))
            .toFixed(2),
        '105.00',
      );
      expect(
        ExactDecimal.parse('100.25')
            .roundNearestToMultiple(ExactDecimal.parse('0.50'))
            .toFixed(2),
        '100.50',
      );
    });
  });

  group('BillTotals validation & BillSettings sync', () {
    test('rejects fixed document discount exceeding subtotal', () {
      final items = [
        BillItem(
          productName: 'Rice',
          sellingPriceSnapshot: 100,
          quantity: 1,
          gstPercentSnapshot: 0,
        ),
      ];
      expect(
        () => BillTotals.calculate(
          items,
          discountMode: Bill.discountModeAmount,
          discountValue: 100.01,
          gstRegistered: false,
          interState: false,
        ),
        throwsArgumentError,
      );
    });

    test('rejects fixed line discount exceeding line subtotal', () {
      final items = [
        BillItem(
          productName: 'Rice',
          sellingPriceSnapshot: 50,
          quantity: 1,
          discountMode: Bill.discountModeAmount,
          discountValue: 55,
        ),
      ];
      expect(
        () => BillTotals.calculate(
          items,
          gstRegistered: false,
          interState: false,
        ),
        throwsArgumentError,
      );
    });

    test('BillSettings keeps roundOffTotal synchronized with roundOffMode', () {
      final off = BillSettings(roundOffTotal: false);
      expect(off.roundOffMode, BillSettings.roundOffNone);
      expect(off.roundOffTotal, isFalse);

      final up = off.copyWith(
        roundOffMode: BillSettings.roundOffUp,
        roundOffIncrement: 5.0,
        defaultTaxMode: BillSettings.taxModeExclusive,
      );
      expect(up.roundOffTotal, isTrue);
      expect(up.roundOffMode, BillSettings.roundOffUp);
      expect(up.roundOffIncrement, 5.0);
      expect(up.defaultTaxMode, BillSettings.taxModeExclusive);

      final roundTripped = BillSettings.fromMap(up.toMap());
      expect(roundTripped.roundOffTotal, isTrue);
      expect(roundTripped.roundOffMode, BillSettings.roundOffUp);
      expect(roundTripped.roundOffIncrement, 5.0);
      expect(roundTripped.defaultTaxMode, BillSettings.taxModeExclusive);
    });
  });

  group('Native sale posting with E03.3A controls', () {
    test(
      'accepts exclusive tax, line discount, fixed doc discount, and up ₹5 round-off',
      () {
        final created = DateTime(2026, 11, 22, 12, 34, 56, 123);
        final rawItems = [
          BillItem(
            uuid: _uuid(2),
            shopId: 'shop',
            billUuid: _uuid(1),
            productUuid: _uuid(3),
            productName: 'Widget',
            sellingPriceSnapshot: 100,
            gstPercentSnapshot: 18,
            quantity: 2,
            discountMode: Bill.discountModePercent,
            discountValue: 10,
            taxMode: Bill.taxModeExclusive,
            createdAt: created,
          ),
        ];
        final calc = BillTotals.calculate(
          rawItems,
          discountMode: Bill.discountModeAmount,
          discountValue: 10,
          taxMode: Bill.taxModeExclusive,
          gstRegistered: true,
          interState: false,
          roundOffMode: Bill.roundOffUp,
          roundOffIncrement: 5.0,
        );
        // 2x100=200 -> 10% line disc = 180 -> ₹10 doc disc = 170 taxable
        // 18% GST = 30.60 (15.30 + 15.30) -> net 200.60 -> up ₹5 = 205.00 (+4.40)
        expect(calc.totals.taxableAmount, 170.00);
        expect(calc.totals.cgstAmount, 15.30);
        expect(calc.totals.sgstAmount, 15.30);
        expect(calc.totals.netAmount, 200.60);
        expect(calc.totals.roundOffAmount, 4.40);
        expect(calc.totals.grandTotal, 205.00);

        final taxedItem = calc.items.single;
        final bill = Bill(
          uuid: _uuid(1),
          shopId: 'shop',
          billNumber: 'INV-E03',
          customerName: 'Walk-in Customer',
          subtotalAmount: calc.totals.subtotal,
          discountPercent: 0,
          discountMode: Bill.discountModeAmount,
          discountValue: 10,
          discountAmount: calc.totals.discountAmount,
          taxMode: Bill.taxModeExclusive,
          taxableAmount: calc.totals.taxableAmount,
          cgstAmount: calc.totals.cgstAmount,
          sgstAmount: calc.totals.sgstAmount,
          igstAmount: calc.totals.igstAmount,
          roundOffAmount: calc.totals.roundOffAmount,
          roundOffMode: Bill.roundOffUp,
          roundOffIncrement: 5.0,
          totalAmount: calc.totals.grandTotal,
          paidAmount: calc.totals.grandTotal,
          balanceDue: 0,
          isPaid: true,
          itemCount: 2,
          createdAt: created,
          deviceId: 'device-001',
        );
        final capture = {
          'version': 1,
          'device_id': 'device-001',
          'invoice': bill.toMap()
            ..remove('id')
            ..remove('customer_id'),
          'items': [
            taxedItem.toMap(1, billUuid: _uuid(1))
              ..remove('id')
              ..remove('bill_id')
              ..remove('product_id'),
          ],
          'payments': [
            {
              'uuid': _uuid(5),
              'shop_id': 'shop',
              'bill_uuid': _uuid(1),
              'amount': calc.totals.grandTotal,
              'payment_method': 'cash',
              'payment_reference': null,
              'received_at': created.toIso8601String(),
              'deleted_at': null,
            },
          ],
          'movements': [
            {
              'uuid': _uuid(4),
              'shop_id': 'shop',
              'product_uuid': _uuid(3),
              'quantity_delta': -2.0,
              'movement_type': 'sale',
              'source_type': 'bill',
              'source_document_type': 'bill',
              'source_document_uuid': _uuid(1),
              'deleted_at': null,
            },
          ],
        };

        final req = nativeSaleRequest(jsonEncode(capture));
        expect(req, isNotNull);
        expect(req!['subtotal'], '200.00');
        expect(req['discount_amount'], '30.00');
        expect(req['taxable_amount'], '170.00');
        expect(req['cgst_amount'], '15.30');
        expect(req['sgst_amount'], '15.30');
        expect(req['round_off_amount'], '4.40');
        expect(req['total_amount'], '205.00');
        expect(req['cart']['discount_mode'], 'amount');
        expect(req['cart']['discount_value'], '10');
        expect(req['cart']['tax_mode'], 'exclusive');
        expect(req['cart']['round_off_mode'], 'up');
        expect(req['cart']['round_off_increment'], '5.00');
        expect(req['cart']['items'].single, {
          'product_uuid': _uuid(3),
          'quantity': '2',
          'discount_mode': 'percent',
          'discount_value': '10',
          'tax_mode': 'exclusive',
        });

        // Reject round_off_amount exceeding round_off_increment.
        final bad = jsonDecode(jsonEncode(capture)) as Map<String, dynamic>;
        bad['invoice']['round_off_increment'] = 1.0;
        expect(nativeSaleRequest(jsonEncode(bad)), isNull);
      },
    );
  });

  group('SQLite v28 -> v29 upgrade & HeldBill draft persistence', () {
    late DatabaseHelper helper;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      helper = DatabaseHelper.instance;
      await helper.close();
      DatabaseHelper.databaseFileName = 'billing-controls-v29.db';
      await deleteDatabase(await DatabaseHelper.databasePath());
    });

    tearDown(() async {
      await helper.close();
      await deleteDatabase(await DatabaseHelper.databasePath());
      DatabaseHelper.databaseFileName = 'storely.db';
    });

    test('v29 migration adds columns and backfills round_off_mode', () async {
      await helper.saveBillSettings(BillSettings(roundOffTotal: false));
      final db = await helper.database;
      // Simulate a v28 DB state where migration marker has not run yet and
      // round_off_mode was defaulted to 'nearest' even though round_off_total=0.
      await db.rawUpdate(
        "UPDATE bill_settings SET round_off_mode = 'nearest', round_off_total = 0",
      );
      await db.delete(
        'cloud_sync_state',
        where: 'key = ?',
        whereArgs: ['migration_done:v29_billing_controls_backfill'],
      );
      await db.execute('PRAGMA user_version = 28');
      await helper.close();

      final upgraded = await helper.database;
      expect(
        (await upgraded.rawQuery('PRAGMA user_version')).single.values.first,
        30,
      );
      final settings = await helper.getBillSettings();
      expect(settings.roundOffTotal, isFalse);
      expect(settings.roundOffMode, BillSettings.roundOffNone);
      expect(settings.defaultTaxMode, BillSettings.taxModeInclusive);
      expect(settings.roundOffIncrement, 1.0);

      final billCols = (await upgraded.rawQuery('PRAGMA table_info(bills)'))
          .map((r) => r['name'])
          .toSet();
      expect(
        billCols,
        containsAll([
          'discount_mode',
          'discount_value',
          'tax_mode',
          'round_off_mode',
          'round_off_increment',
        ]),
      );
      final itemCols = (await upgraded.rawQuery('PRAGMA table_info(bill_items)'))
          .map((r) => r['name'])
          .toSet();
      expect(
        itemCols,
        containsAll([
          'discount_mode',
          'discount_value',
          'discount_amount',
          'tax_mode',
        ]),
      );
    });

    test('HeldBill encodes and decodes per-line discount and tax mode', () {
      final items = [
        BillItem(
          productName: 'Tea',
          sellingPriceSnapshot: 100,
          quantity: 2,
          gstPercentSnapshot: 18,
          discountMode: Bill.discountModeAmount,
          discountValue: 15,
          discountAmount: 15,
          taxMode: Bill.taxModeExclusive,
        ),
      ];
      final decoded = HeldBill.decodeItems(HeldBill.encodeItems(items));
      expect(decoded, hasLength(1));
      expect(decoded.single.discountMode, Bill.discountModeAmount);
      expect(decoded.single.discountValue, 15);
      expect(decoded.single.discountAmount, 15);
      expect(decoded.single.taxMode, Bill.taxModeExclusive);
    });

    testWidgets(
      'checkout widget computes exclusive tax + line discount + fixed doc discount + up ₹5 round-off and saves exact totals',
      (tester) async {
        await tester.runAsync(() async {
          await helper.saveShopProfile(
            ShopProfile(
              name: 'Test GST Shop',
              gstin: '27AAAAA0000A1Z5',
              gstScheme: GstScheme.regular,
            ),
          );
          await helper.saveBillSettings(
            BillSettings(
              defaultTaxMode: BillSettings.taxModeInclusive,
              roundOffMode: BillSettings.roundOffNearest,
              roundOffIncrement: 1.0,
            ),
          );
        });

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
                uuid: 'src-bill',
                totalAmount: 200,
                itemCount: 2,
                paidAmount: 200,
                customerName: 'Walk-in Customer',
                items: [
                  BillItem(
                    productName: 'Widget',
                    quantity: 2,
                    sellingPriceSnapshot: 100,
                    gstPercentSnapshot: 18,
                  ),
                ],
              ),
            ),
          ),
        );
        await _settle(tester);

        // Edit per-line controls: 10% line discount
        await _tapVisible(tester, find.byKey(const ValueKey('cart-item-edit-0')));
        await _settle(tester);
        await tester.enterText(
          find.byKey(const ValueKey('line-discount-value')),
          '10',
        );
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('line-controls-apply')),
        );
        await _settle(tester);
        expect(find.text('10% off'), findsOneWidget);

        // Open checkout sheet
        await tester.tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
        await _settle(tester);
        expect(find.text('Create Bill'), findsOneWidget);

        // Switch document discount mode to ₹ and enter 10
        await _tapVisible(tester, find.text('₹'));
        await tester.enterText(
          find.byKey(const ValueKey('checkout-discount')),
          '10',
        );
        await tester.pump();

        // Switch document tax mode to Tax exclusive
        await _tapVisible(tester, find.text('Tax exclusive'));
        await tester.pump();

        // Switch round-off mode to Up and increment to ₹5
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-round-off-mode-up')),
        );
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-round-off-increment-5.00')),
        );
        await _settle(tester);

        // Expected: 2x100=200 -> -10% line=180 -> -₹10 doc=170 taxable
        // + 18% GST (30.60) = 200.60 -> Up ₹5 = ₹205.00
        final grandTotalText = tester.widget<Text>(
          find.byKey(const ValueKey('checkout-grand-total')),
        );
        expect(grandTotalText.data, contains('205'));

        // Select Paid full and save
        await _tapVisible(tester, find.text('Paid full'));
        await _settle(tester);
        await _tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
        await _settle(tester);

        final bills = await tester.runAsync(helper.getAllBills);
        expect(bills, hasLength(1));
        final saved = bills!.single;
        expect(saved.taxMode, Bill.taxModeExclusive);
        expect(saved.discountMode, Bill.discountModeAmount);
        expect(saved.discountValue, 10.0);
        expect(saved.discountAmount, 30.0);
        expect(saved.taxableAmount, 170.0);
        expect(saved.cgstAmount, 15.30);
        expect(saved.sgstAmount, 15.30);
        expect(saved.roundOffMode, Bill.roundOffUp);
        expect(saved.roundOffIncrement, 5.0);
        expect(saved.roundOffAmount, 4.40);
        expect(saved.totalAmount, 205.0);
        expect(saved.items.single.discountMode, Bill.discountModePercent);
        expect(saved.items.single.discountValue, 10.0);
        expect(saved.items.single.discountAmount, 20.0);

        await tester.pumpWidget(const SizedBox());
        await _settle(tester);
      },
    );
  });
}
