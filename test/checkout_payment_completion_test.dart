import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/checkout_settlement.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/screens/reports_screens.dart';
import 'package:storely/screens/scan_screen.dart';
import 'package:storely/screens/shared/record_payment_dialog.dart';
import 'package:storely/utils/bill_pdf_generator.dart';
import 'package:storely/utils/test_keys.dart';

Future<void> settleIo(WidgetTester tester) async {
  for (var n = 0; n < 8; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitForCompletion(WidgetTester tester) async {
  for (
    var attempt = 0;
    attempt < 100 && find.text('Bill Created!').evaluate().isEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 50));
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

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await db.close();
    DatabaseHelper.databaseFileName = 'checkout-payment-completion.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await db.saveBillSettings(BillSettings());
  });

  tearDown(() async {
    db.onDatabaseChanged = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  group('checkout_settlement helpers', () {
    test('canonical methods and labels match contract', () {
      expect(checkoutPaymentMethods, ['cash', 'upi', 'card', 'bank', 'online']);
      expect(paymentMethodLabel('cash'), 'Cash');
      expect(paymentMethodLabel('upi'), 'UPI');
      expect(paymentMethodLabel('card'), 'Card');
      expect(paymentMethodLabel('bank'), 'Bank transfer');
      expect(paymentMethodLabel('bank_transfer'), 'Bank transfer');
      expect(paymentMethodLabel('online'), 'Online');
      expect(paymentMethodLabel(''), 'Cash');
      expect(paymentMethodLabel('wallet'), 'wallet');
    });

    test(
      'normalizeCheckoutPaymentMethod normalizes unknown values to cash',
      () {
        for (final method in checkoutPaymentMethods) {
          expect(normalizeCheckoutPaymentMethod(method), method);
        }
        expect(normalizeCheckoutPaymentMethod(null), 'cash');
        expect(normalizeCheckoutPaymentMethod('bank_transfer'), 'bank');
        expect(supplierPaymentMethodCode('bank'), 'bank_transfer');
        expect(supplierPaymentMethodCode('bank_transfer'), 'bank_transfer');
        expect(normalizeCheckoutPaymentMethod(''), 'cash');
        expect(normalizeCheckoutPaymentMethod('cheque'), 'cash');
        expect(normalizeCheckoutPaymentMethod(42), 'cash');
      },
    );

    test('checkoutChangePaise parses valid overpayments in exact paise', () {
      final total = BigInt.from(10049); // ₹100.49
      expect(checkoutChangePaise(cashText: '', totalPaise: total), isNull);
      expect(checkoutChangePaise(cashText: '  ', totalPaise: total), isNull);
      expect(checkoutChangePaise(cashText: '-10', totalPaise: total), isNull);
      expect(checkoutChangePaise(cashText: 'abc', totalPaise: total), isNull);
      expect(checkoutChangePaise(cashText: '150.', totalPaise: total), isNull);
      expect(checkoutChangePaise(cashText: '.50', totalPaise: total), isNull);
      expect(
        checkoutChangePaise(cashText: '150.001', totalPaise: total),
        isNull,
      );
      expect(
        checkoutChangePaise(cashText: '100.49', totalPaise: total),
        isNull,
      );
      expect(checkoutChangePaise(cashText: '90', totalPaise: total), isNull);

      expect(
        checkoutChangePaise(cashText: '150', totalPaise: total),
        BigInt.from(4951),
      );
      expect(
        checkoutChangePaise(cashText: ' 100.50 ', totalPaise: total),
        BigInt.from(1),
      );
      expect(
        checkoutChangePaise(cashText: '500.75', totalPaise: BigInt.from(11800)),
        BigInt.from(38275),
      );
    });
  });

  group('ScanScreen checkout payment & completion', () {
    Future<Product> seedProductWithDraft(
      WidgetTester tester, {
      double price = 118,
    }) async {
      final product = await tester.runAsync(() async {
        final id = await db.insertProduct(
          Product(
            name: 'Completion Rice',
            sellingPrice: price,
            purchasePrice: 80,
            directPriceToggle: true,
            manualPrice: price,
            quantity: 10,
          ),
        );
        final saved = (await db.getProductById(id))!;
        final item = await db.buildBillItemForProduct(saved);
        await db.saveCartDraft([item]);
        return saved;
      });
      return product!;
    }

    Future<void> mountScanScreen(
      WidgetTester tester, {
      Bill? duplicateFromBill,
    }) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ScanScreen(
            initialMode: BillingEntryMode.manual,
            duplicateFromBill: duplicateFromBill,
          ),
        ),
      );
      await settleIo(tester);
    }

    Future<void> unmountScanScreen(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    }

    testWidgets(
      'closing while raw writes are queued keeps the final reference and items step',
      (tester) async {
        await seedProductWithDraft(tester);
        await mountScanScreen(tester);
        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );
        await tapVisible(tester, find.text('Paid full'));
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-method-upi')),
        );
        final close = tester
            .widget<IconButton>(find.byKey(const ValueKey('checkout-close')))
            .onPressed!;
        final reference = tester
            .widget<TextField>(find.byKey(const ValueKey('checkout-reference')))
            .controller!;
        reference.text = 'LAST-QUEUED-REFERENCE';
        close();
        await settleIo(tester);
        final draft = await tester.runAsync(
          () async => db.loadCheckoutCart(await db.captureCheckoutScope()),
        );
        expect(draft!.state['step'], 'items');
        expect(
          (draft.state['raw'] as Map)['reference'],
          'LAST-QUEUED-REFERENCE',
        );
        await unmountScanScreen(tester);
      },
    );

    testWidgets(
      'cash change UI formats large accepted amounts without losing paise',
      (tester) async {
        await seedProductWithDraft(tester);
        await mountScanScreen(tester);
        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );
        await tapVisible(tester, find.text('Paid full'));
        await enterField(
          tester,
          find.byKey(const ValueKey('checkout-cash-received')),
          '123456789012345678901234567890.99',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('checkout-change-due')))
              .data,
          'Change to return ₹1,23,45,67,89,01,23,45,67,89,01,23,45,67,772.99',
        );
        await unmountScanScreen(tester);
      },
    );

    testWidgets(
      'supports all 5 methods, strips UPI reference on Cash switch, and shows exact change',
      (tester) async {
        await seedProductWithDraft(tester, price: 118);
        await mountScanScreen(tester);

        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );
        await tapVisible(tester, find.text('Paid full'));

        for (final method in checkoutPaymentMethods) {
          expect(
            find.byKey(ValueKey('checkout-method-$method')),
            findsOneWidget,
          );
          expect(find.text(paymentMethodLabel(method)), findsOneWidget);
        }

        const hintText =
            'Storely records the payment method and reference on the invoice; it does not collect the payment itself.';

        for (final method in ['upi', 'card', 'bank', 'online']) {
          await tapVisible(
            tester,
            find.byKey(ValueKey('checkout-method-$method')),
          );
          final refFinder = find.byKey(const ValueKey('checkout-reference'));
          expect(refFinder, findsOneWidget);
          expect(tester.widget<TextField>(refFinder).maxLength, 100);
          expect(find.text(hintText), findsOneWidget);
          expect(
            find.byKey(const ValueKey('checkout-cash-received')),
            findsNothing,
          );
        }

        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-method-upi')),
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('checkout-reference')),
          'UPI-999',
        );

        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-method-cash')),
        );
        expect(find.byKey(const ValueKey('checkout-reference')), findsNothing);
        final cashField = find.byKey(const ValueKey('checkout-cash-received'));
        expect(cashField, findsOneWidget);

        await enterField(tester, cashField, '118');
        expect(find.byKey(const ValueKey('checkout-change-due')), findsNothing);

        await enterField(tester, cashField, '200.50');
        final changeText = tester.widget<Text>(
          find.byKey(const ValueKey('checkout-change-due')),
        );
        expect(changeText.data, 'Change to return ₹82.50');

        await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
        await waitForCompletion(tester);
        expect(
          find.text('Bill Created!'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((widget) => widget.data)
              .join(' | '),
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('checkout-completion-total')),
              )
              .data,
          '₹118.00',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('checkout-completion-received')),
              )
              .data,
          '₹118.00',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('checkout-completion-balance')),
              )
              .data,
          '₹0.00',
        );
        expect(find.textContaining('Paid'), findsWidgets);

        final bills = (await tester.runAsync(db.getAllBills))!;
        expect(bills, hasLength(1));
        expect(bills.single.paymentMethod, 'cash');
        expect(bills.single.transactionReference, isNull);
        expect(bills.single.paidAmount, 118.0);
        expect(bills.single.balanceDue, 0.0);

        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-completion-done')),
        );
        await unmountScanScreen(tester);
      },
    );

    Future<CheckoutCart> loadActiveCart(WidgetTester tester) async {
      final cart = await tester.runAsync(
        () async => db.loadCheckoutCart(await db.captureCheckoutScope()),
      );
      return cart!;
    }

    testWidgets(
      'persists raw cash, method, reference, and checkout/items step across close and DB reopen',
      (tester) async {
        await seedProductWithDraft(tester, price: 118);
        await mountScanScreen(tester);

        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );
        var cart = await loadActiveCart(tester);
        expect(cart.state['step'], 'checkout');

        await tapVisible(tester, find.text('Paid full'));
        await enterField(
          tester,
          find.byKey(const ValueKey('checkout-cash-received')),
          '500.25',
        );
        cart = await loadActiveCart(tester);
        expect(cart.state['raw']['cash'], '500.25');
        expect(cart.state['raw']['method'], 'cash');

        await tapVisible(tester, find.byKey(const ValueKey('checkout-close')));
        expect(find.text('Create Bill'), findsNothing);
        cart = await loadActiveCart(tester);
        expect(cart.state['step'], 'items');
        expect(cart.state['raw']['cash'], '500.25');

        await unmountScanScreen(tester);
        await tester.runAsync(db.close);
        await mountScanScreen(tester);

        // Must not auto-open modal sheet on mount; scanBillBtn remains clickable.
        expect(find.text('Create Bill'), findsNothing);
        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );
        expect(find.text('Create Bill'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('checkout-cash-received')),
              )
              .controller!
              .text,
          '500.25',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('checkout-change-due')))
              .data,
          'Change to return ₹382.25',
        );

        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-method-bank')),
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('checkout-reference')),
          'NEFT-789',
        );
        await tapVisible(tester, find.byKey(const ValueKey('checkout-close')));
        cart = await loadActiveCart(tester);
        expect(cart.state['step'], 'items');
        expect(cart.state['raw']['method'], 'bank');
        expect(cart.state['raw']['reference'], 'NEFT-789');

        await unmountScanScreen(tester);
        await tester.runAsync(db.close);
        await mountScanScreen(tester);
        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );

        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('checkout-method-bank')),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('checkout-reference')),
              )
              .controller!
              .text,
          'NEFT-789',
        );
        await unmountScanScreen(tester);
      },
    );

    testWidgets(
      'partial bank checkout shows Partial status, totals, and View invoice opens quick sheet',
      (tester) async {
        await seedProductWithDraft(tester, price: 118);
        await mountScanScreen(tester);

        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );
        await tapVisible(tester, find.text('Partial'));
        await enterField(
          tester,
          find.byKey(const ValueKey('checkout-partial-amount')),
          '50.00',
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-method-bank')),
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('checkout-reference')),
          'NEFT-500',
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-unassigned-consent')),
        );
        await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));

        await waitForCompletion(tester);
        expect(
          find.text('Bill Created!'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((widget) => widget.data)
              .join(' | '),
        );
        expect(find.textContaining('Partial'), findsOneWidget);
        expect(find.textContaining('Bank transfer'), findsOneWidget);
        expect(find.textContaining('Unpaid'), findsNothing);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('checkout-completion-total')),
              )
              .data,
          '₹118.00',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('checkout-completion-received')),
              )
              .data,
          '₹50.00',
        );
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('checkout-completion-balance')),
              )
              .data,
          '₹68.00',
        );

        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-completion-view')),
        );
        expect(find.text('Bill Created!'), findsNothing);
        expect(find.text('Record payment'), findsOneWidget);
        expect(find.text('Share bill'), findsOneWidget);
        expect(find.text('₹68.00'), findsOneWidget);

        await tapVisible(
          tester,
          find.byKey(const ValueKey('quick-record-payment')),
        );
        for (final method in checkoutPaymentMethods) {
          expect(
            find.byKey(ValueKey('payment-method-$method')),
            findsOneWidget,
          );
        }
        await tapVisible(
          tester,
          find.byKey(const ValueKey('payment-method-card')),
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('payment-reference')),
          'CARD-AUTH-42',
        );
        await tapVisible(tester, find.bySemanticsIdentifier(TestKeys.saveBtn));

        final bills = (await tester.runAsync(db.getAllBills))!;
        expect(bills, hasLength(1));
        expect(bills.single.paidAmount, 118.0);
        expect(bills.single.balanceDue, 0.0);
        expect(bills.single.paymentStatus, Bill.statusPaid);
        expect(bills.single.transactionReference, 'CARD-AUTH-42');

        await unmountScanScreen(tester);
      },
    );

    testWidgets(
      'New Bill after duplicate clears cart, draft, settlement, method, cash/ref, and duplicate lineage',
      (tester) async {
        await tester.runAsync(() async {
          await db.insertProduct(
            Product(
              name: 'Fresh Milk',
              sellingPrice: 60,
              purchasePrice: 40,
              directPriceToggle: true,
              manualPrice: 60,
              quantity: 20,
            ),
          );
        });
        final sourceBill = Bill(
          uuid: 'dup-source-uuid',
          totalAmount: 60,
          itemCount: 1,
          paidAmount: 60,
          customerName: 'Original Duplicate Customer',
          discountPercent: 10,
          items: [
            BillItem(
              productName: 'Fresh Milk',
              quantity: 1,
              sellingPriceSnapshot: 60,
            ),
          ],
        );

        await mountScanScreen(tester, duplicateFromBill: sourceBill);
        expect(find.text('Duplicate Bill'), findsOneWidget);

        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );
        await tapVisible(tester, find.text('Paid full'));
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-method-upi')),
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('checkout-reference')),
          'DUP-UPI-01',
        );
        await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
        await waitForCompletion(tester);
        expect(
          find.text('Bill Created!'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((widget) => widget.data)
              .join(' | '),
        );

        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-completion-new')),
        );
        expect(find.text('Bill Created!'), findsNothing);
        expect(find.text('Manual Bill'), findsOneWidget);
        expect(await tester.runAsync(db.loadCartDraft), isEmpty);

        // Start a brand-new bill from the product list.
        await tapVisible(tester, find.text('Fresh Milk'));
        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );

        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('checkout-customer')),
              )
              .controller!
              .text,
          isEmpty,
        );
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('checkout-discount')),
              )
              .controller!
              .text,
          isEmpty,
        );
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

        await tapVisible(tester, find.text('Paid full'));
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey('checkout-method-cash')),
              )
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('checkout-cash-received')),
              )
              .controller!
              .text,
          isEmpty,
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-method-upi')),
        );
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('checkout-reference')),
              )
              .controller!
              .text,
          isEmpty,
        );
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-method-cash')),
        );
        await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-completion-done')),
        );

        final bills = (await tester.runAsync(db.getAllBills))!;
        expect(bills, hasLength(2));
        final firstBill = bills.singleWhere(
          (b) => b.duplicatedFromBillUuid == 'dup-source-uuid',
        );
        final secondBill = bills.singleWhere(
          (b) => b.duplicatedFromBillUuid == null,
        );
        expect(firstBill.paymentMethod, 'upi');
        expect(firstBill.transactionReference, 'DUP-UPI-01');
        expect(secondBill.customerName, 'Walk-in Customer');
        expect(secondBill.paymentMethod, 'cash');
        expect(secondBill.transactionReference, isNull);

        await unmountScanScreen(tester);
      },
    );

    testWidgets(
      'unpaid checkout normalizes method to cash and reference to null',
      (tester) async {
        await seedProductWithDraft(tester, price: 118);
        await mountScanScreen(tester);

        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );
        await tapVisible(tester, find.text('Partial'));
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-method-upi')),
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('checkout-reference')),
          'SHOULD-STRIP',
        );
        await tapVisible(tester, find.text('Unpaid'));
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-unassigned-consent')),
        );
        await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));

        await waitForCompletion(tester);
        expect(
          find.text('Bill Created!'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((widget) => widget.data)
              .join(' | '),
        );
        expect(find.textContaining('Unpaid'), findsOneWidget);

        final bills = (await tester.runAsync(db.getAllBills))!;
        expect(bills, hasLength(1));
        expect(bills.single.paymentStatus, Bill.statusUnpaid);
        expect(bills.single.paidAmount, 0.0);
        expect(bills.single.paymentMethod, 'cash');
        expect(bills.single.transactionReference, isNull);

        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-completion-done')),
        );
        await unmountScanScreen(tester);
      },
    );
  });

  group('Shared payment UI and formatters consistency', () {
    testWidgets(
      'RecordPaymentDialog offers all 5 methods and strips reference on cash',
      (tester) async {
        PaymentEntry? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<PaymentEntry>(
                    context: context,
                    builder: (_) => const RecordPaymentDialog(balanceDue: 250),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        for (final method in checkoutPaymentMethods) {
          expect(
            find.byKey(ValueKey('payment-method-$method')),
            findsOneWidget,
          );
          expect(find.text(paymentMethodLabel(method)), findsOneWidget);
        }

        await tester.tap(find.byKey(const ValueKey('payment-method-bank')));
        await tester.pumpAndSettle();
        final refField = find.byKey(const ValueKey('payment-reference'));
        expect(refField, findsOneWidget);
        expect(tester.widget<TextField>(refField).maxLength, 100);
        await tester.enterText(refField, '  UTR-123  ');
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('payment-method-cash')));
        await tester.pumpAndSettle();
        expect(refField, findsNothing);

        await tester.tap(find.bySemanticsIdentifier(TestKeys.saveBtn));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        expect(result!.method, 'cash');
        expect(result!.reference, isNull);
        expect(result!.amount, 250);
      },
    );

    test('BillPdfGenerator accepts all 5 canonical payment methods', () async {
      final shop = ShopProfile(name: 'Storely Hardware');
      for (final method in checkoutPaymentMethods) {
        final bill = Bill(
          billNumber: 'INV-$method',
          customerName: 'Asha',
          totalAmount: 100,
          paidAmount: 100,
          itemCount: 1,
          paymentMethod: method,
          items: [
            BillItem(
              productName: 'Paint',
              quantity: 1,
              sellingPriceSnapshot: 100,
            ),
          ],
        );
        final bytes = await BillPdfGenerator.generate(bill: bill, shop: shop);
        expect(bytes.length, greaterThan(1000), reason: method);
      }
    });

    testWidgets('DayBookScreen formats all 5 canonical payment methods', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (final method in checkoutPaymentMethods) {
          await db.insertBill(
            Bill(
              customerName: 'Customer $method',
              totalAmount: 100,
              paidAmount: 100,
              itemCount: 1,
              paymentMethod: method,
              items: [
                BillItem(
                  productName: 'Item $method',
                  quantity: 1,
                  sellingPriceSnapshot: 100,
                ),
              ],
            ),
            [
              BillItem(
                productName: 'Item $method',
                quantity: 1,
                sellingPriceSnapshot: 100,
              ),
            ],
          );
        }
      });

      await tester.pumpWidget(const MaterialApp(home: DayBookScreen()));
      await settleIo(tester);

      expect(find.text('Received · Cash'), findsOneWidget);
      expect(find.text('Received · UPI'), findsOneWidget);
      expect(find.text('Received · Card'), findsOneWidget);
      expect(find.text('Received · Bank transfer'), findsOneWidget);
      expect(find.text('Received · Online'), findsOneWidget);
    });
  });
}
