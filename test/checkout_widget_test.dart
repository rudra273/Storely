import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/sale_quantity.dart';
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
  Future<void> reopenSheet(WidgetTester tester) async {
    await tester.tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
    await settleIo(tester);
  }

  Future<void> mountRestored(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ScanScreen(initialMode: BillingEntryMode.manual),
      ),
    );
    await settleIo(tester);
    await reopenSheet(tester);
  }

  test('sale quantity accepts only supported positive exact decimals', () {
    expect(saleQuantityThousandths(' 0001.12500 '), BigInt.from(1125));
    expect(saleQuantityThousandths('1000000.0000'), BigInt.from(1000000000));
    for (final input in [
      '',
      '0',
      '0.0001',
      '1.2345',
      '1000000.001',
      '1e3',
      '+1',
      '-1',
    ]) {
      expect(saleQuantityThousandths(input), isNull, reason: input);
    }
    expect(adjustSaleQuantity(1.001, 1), 2.001);
    expect(adjustSaleQuantity(1000000, 1), isNull);
  });

  testWidgets('invalid sale quantity survives reopening and blocks review', (
    tester,
  ) async {
    await open(tester);
    await tapVisible(tester, find.byKey(const ValueKey('checkout-close')));
    await settleIo(tester);
    final quantity = find.byKey(const ValueKey('sale-quantity-input'));
    await tester.enterText(quantity, '1.2345');
    await settleIo(tester);
    await reopenSheet(tester);
    expect(find.text('Create Bill'), findsNothing);
    expect(await tester.runAsync(db.getAllBills), isEmpty);

    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
    await tester.runAsync(db.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ScanScreen(initialMode: BillingEntryMode.manual),
      ),
    );
    await settleIo(tester);
    expect(tester.widget<TextField>(quantity).controller!.text, '1.2345');
    await tester.enterText(quantity, '1.1250');
    FocusManager.instance.primaryFocus?.unfocus();
    await settleIo(tester);
    final scope = await tester.runAsync(db.captureCheckoutScope);
    final cart = await tester.runAsync(() => db.loadCheckoutCart(scope!));
    expect(cart!.cart.items.single.quantity, 1.125);
    expect(cart.cart.items.single.draftQuantityInput, isNull);
    await reopenSheet(tester);
    expect(find.text('Create Bill'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester);
  });

  testWidgets(
    'raw checkout fields survive sheet close and physical database reopen',
    (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('checkout-customer')),
        ' Asha raw ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('checkout-discount')),
        '12.50',
      );
      await tapVisible(tester, find.text('Partial'));
      await tester.enterText(
        find.byKey(const ValueKey('checkout-partial-amount')),
        '50.000',
      );
      await tapVisible(tester, find.text('Online'));
      await tester.enterText(
        find.byKey(const ValueKey('checkout-reference')),
        ' KEEP reference ',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('checkout-unassigned-consent')),
      );
      await settleIo(tester);
      await tapVisible(tester, find.byKey(const ValueKey('checkout-close')));
      await settleIo(tester);
      await reopenSheet(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('checkout-customer')))
            .controller!
            .text,
        ' Asha raw ',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('checkout-partial-amount')),
            )
            .controller!
            .text,
        '50.000',
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('checkout-unassigned-consent')),
            )
            .value,
        isTrue,
      );
      await tapVisible(tester, find.byKey(const ValueKey('checkout-close')));
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
      await tester.runAsync(db.close);
      await mountRestored(tester);
      final savedCart = await tester.runAsync(
        () async => db.loadCheckoutCart(await db.captureCheckoutScope()),
      );
      expect(savedCart!.state['source_bill_uuid'], 'original');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('checkout-customer')))
            .controller!
            .text,
        ' Asha raw ',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('checkout-discount')))
            .controller!
            .text,
        '12.50',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('checkout-reference')))
            .controller!
            .text,
        ' KEEP reference ',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('checkout-partial-amount')),
            )
            .controller!
            .text,
        '50.000',
      );
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
  testWidgets(
    'frozen failed attempt restores exact identity and permits only same save',
    (tester) async {
      await open(tester);
      final sql = await db.database;
      await tester.runAsync(
        () => sql.execute(
          "CREATE TRIGGER fail_checkout BEFORE INSERT ON checkout_acceptances BEGIN SELECT RAISE(ABORT, 'pending restart'); END",
        ),
      );
      await tapVisible(tester, find.text('Partial'));
      await tester.enterText(
        find.byKey(const ValueKey('checkout-partial-amount')),
        '25.01',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('checkout-unassigned-consent')),
      );
      await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
      await settleIo(tester);
      final before = await tester.runAsync(
        () async =>
            (await db.loadCheckoutCart(await db.captureCheckoutScope()))!,
      );
      final key = (before!.state['pending'] as Map)['attempt_id'];
      expect(key, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
      await tester.runAsync(db.close);
      await tester.runAsync(
        () async => (await db.database).execute('DROP TRIGGER fail_checkout'),
      );
      await mountRestored(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('checkout-partial-amount')),
            )
            .readOnly,
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('checkout-close')))
            .onPressed,
        isNull,
      );
      await tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
      await settleIo(tester);
      final bills = await tester.runAsync(db.getAllBills);
      expect(bills, hasLength(1));
      expect(bills!.single.paidAmount, 25.01);
      final accepted = await tester.runAsync(
        () async => (await db.database).query('checkout_acceptances'),
      );
      expect(accepted!.single['attempt_id'], key);
      expect(await tester.runAsync(db.loadCartDraft), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
  testWidgets(
    'restored review context drift preserves text but clears settlement and consent',
    (tester) async {
      await open(tester);
      await tapVisible(tester, find.text('Partial'));
      await tester.enterText(
        find.byKey(const ValueKey('checkout-partial-amount')),
        '25.01',
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('checkout-unassigned-consent')),
      );
      await settleIo(tester);
      await tapVisible(tester, find.byKey(const ValueKey('checkout-close')));
      final sql = await db.database;
      await tester.runAsync(
        () => sql.update('bill_settings', {'round_off_total': 0}),
      );
      await reopenSheet(tester);
      final choice = tester
          .widgetList<SegmentedButton<String>>(
            find.byType(SegmentedButton<String>),
          )
          .where(
            (widget) => widget.segments.any(
              (segment) => segment.value == Bill.statusPaid,
            ),
          )
          .single;
      expect(choice.selected, isEmpty);
      await tapVisible(tester, find.text('Partial'));
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('checkout-partial-amount')),
            )
            .controller!
            .text,
        '25.01',
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('checkout-unassigned-consent')),
            )
            .value,
        isFalse,
      );
      expect(find.text('₹100.49'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    },
  );
}
