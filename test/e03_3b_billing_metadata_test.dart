import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/product_purchase.dart';
import 'package:storely/screens/products_screen.dart';
import 'package:storely/screens/scan_screen.dart';
import 'package:storely/screens/store/audit_log_screen.dart';
import 'package:storely/screens/store/bill_settings_screen.dart';
import 'package:storely/utils/test_keys.dart';

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
  late DatabaseHelper helper;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    helper = DatabaseHelper.instance;
    helper.isAdminMutationAllowed = null;
    helper.auditActor = null;
    await helper.close();
    DatabaseHelper.databaseFileName = 'e03-3b-billing-metadata.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
  });

  tearDown(() async {
    helper.isAdminMutationAllowed = null;
    helper.auditActor = null;
    await helper.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  group('SQLite v29 -> v30 upgrade & Bill notes model', () {
    test('upgrades v29 DB to v30 and adds bills.notes column', () async {
      final db = await helper.database;
      await db.execute('PRAGMA user_version = 29');
      await helper.close();

      final upgraded = await helper.database;
      expect(
        (await upgraded.rawQuery('PRAGMA user_version')).single.values.first,
        31,
      );
      final cols = (await upgraded.rawQuery('PRAGMA table_info(bills)'))
          .map((r) => r['name'])
          .toSet();
      expect(cols, contains('notes'));

      final bill = Bill(
        totalAmount: 100,
        itemCount: 1,
        notes: '  Deliver after 5pm  ',
      );
      expect(bill.notes, 'Deliver after 5pm');
      final roundTrip = Bill.fromMap(bill.toMap());
      expect(roundTrip.notes, 'Deliver after 5pm');

      final updated = roundTrip.copyWith(notes: 'Ring bell');
      expect(updated.notes, 'Ring bell');
      final cleared = updated.copyWith(clearNotes: true);
      expect(cleared.notes, isNull);
    });
  });

  group('F03: Next invoice number (nextSequence)', () {
    test('rejects nextSequence < 1 and allocates from updated nextSequence', () async {
      await expectLater(
        () => helper.saveDefaultInvoiceSeriesSettings(
          const InvoiceSeriesSettings(nextSequence: 0),
        ),
        throwsArgumentError,
      );

      await helper.saveDefaultInvoiceSeriesSettings(
        const InvoiceSeriesSettings(
          formatTemplate: 'INV/{SEQ}',
          sequencePadding: 4,
          resetPeriod: 'never',
          nextSequence: 42,
        ),
      );
      final series = await helper.getDefaultInvoiceSeriesSettings();
      expect(series.nextSequence, 42);

      final billId = await helper.insertBill(
        Bill(totalAmount: 100, itemCount: 1),
        [BillItem(productName: 'Item', quantity: 1, sellingPriceSnapshot: 100)],
      );
      final bill = (await helper.getBillById(billId))!;
      expect(bill.billNumber, endsWith('0042'));
    });

    testWidgets('BillSettingsScreen edits and saves nextSequence', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(home: BillSettingsScreen()),
      );
      await _settle(tester);

      final seqField = find.byKey(const ValueKey('settings-next-sequence'));
      expect(seqField, findsOneWidget);

      await tester.enterText(seqField, '0');
      await tester.pump();
      expect(find.text('Next invoice number must be 1 or more'), findsOneWidget);

      await tester.enterText(seqField, '125');
      await tester.pump();
      expect(find.text('Next invoice number must be 1 or more'), findsNothing);

      await _tapVisible(tester, find.text('Save Bill Settings'));
      await _settle(tester);

      final series = await tester.runAsync(
        helper.getDefaultInvoiceSeriesSettings,
      );
      expect(series!.nextSequence, 125);
    });
  });

  group('T19: Posted-bill notes & metadata edit with audit diff', () {
    test('persists notes and logs notes diff on updateBillCustomerDetails', () async {
      helper.auditActor = () => 'owner@shop.in';
      final id = await helper.insertBill(
        Bill(
          customerName: 'Ravi',
          totalAmount: 250,
          itemCount: 1,
          notes: 'Leave at gate',
        ),
        [BillItem(productName: 'Tea', quantity: 1, sellingPriceSnapshot: 250)],
      );
      final created = (await helper.getBillById(id))!;
      expect(created.notes, 'Leave at gate');

      await helper.updateBillCustomerDetails(
        id,
        customerName: 'Ravi Kumar',
        notes: 'Call before delivery',
        isB2b: false,
      );

      final edited = (await helper.getBillById(id))!;
      expect(edited.customerName, 'Ravi Kumar');
      expect(edited.notes, 'Call before delivery');

      final audit = await helper.getBillAudit(edited.uuid);
      expect(audit, hasLength(1));
      expect(audit.single.action, AuditAction.edited);
      expect(audit.single.details, contains('Name: Ravi → Ravi Kumar'));
      expect(
        audit.single.details,
        contains('Notes: Leave at gate → Call before delivery'),
      );
    });
  });

  group('F02 & T19: Checkout backdating and notes widget flow', () {
    testWidgets('admin can backdate bill and save notes via checkout sheet', (
      tester,
    ) async {
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
              totalAmount: 100,
              itemCount: 1,
              paidAmount: 100,
              customerName: 'Walk-in Customer',
              items: [
                BillItem(
                  productName: 'Sugar',
                  quantity: 1,
                  sellingPriceSnapshot: 100,
                ),
              ],
            ),
          ),
        ),
      );
      await _settle(tester);

      try {
        await tester.tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
        await _settle(tester);
        expect(find.text('Create Bill'), findsOneWidget);

        // Open bill date picker and pick day 1 of the current month (or previous
        // month if today is day 1) so it's strictly in the past.
        final now = DateTime.now();
        final past = now.day > 1
            ? DateTime(now.year, now.month, 1)
            : DateTime(now.year, now.month, 1).subtract(const Duration(days: 1));

        await _tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-bill-date')),
        );
        await _settle(tester);
        final picker = find.byType(DatePickerDialog);
        expect(picker, findsOneWidget);
        if (now.day == 1) {
          await tester.tap(
            find.descendant(
              of: picker,
              matching: find.byTooltip('Previous month'),
            ),
          );
          await _settle(tester);
        }
        await tester.tap(
          find.descendant(of: picker, matching: find.text('${past.day}')).last,
        );
        await tester.pump();
        await tester.tap(
          find.descendant(of: picker, matching: find.text('OK')),
        );
        await _settle(tester);

        // Enter bill notes
        await tester.enterText(
          find.byKey(const ValueKey('checkout-notes')),
          'Backdated counter sale',
        );
        await tester.pump();

        await _tapVisible(tester, find.text('Paid full'));
        await _settle(tester);
        await _tapVisible(tester, find.byKey(const ValueKey('checkout-save')));
        await _settle(tester);

        final bills = await tester.runAsync(helper.getAllBills);
        expect(bills, hasLength(1));
        final saved = bills!.single;
        expect(saved.createdAt.year, past.year);
        expect(saved.createdAt.month, past.month);
        expect(saved.createdAt.day, past.day);
        expect(saved.notes, 'Backdated counter sale');
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _settle(tester);
      }
    });
  });

  group('A10: Shop-wide Audit Log & AuditLogScreen', () {
    test('logs product edits and stock adjustments and filters getShopAuditLog', () async {
      helper.auditActor = () => 'admin@shop.in';
      final productId = await helper.insertProduct(
        Product(name: 'Coffee', sellingPrice: 120, purchasePrice: 80, quantity: 10),
      );
      final product = (await helper.getProductById(productId))!;

      await helper.updateProduct(
        product.copyWith(name: 'Filter Coffee', sellingPrice: 150),
      );
      await helper.adjustStock(
        productId,
        delta: -2,
        reason: StockAdjustmentReason.damage,
        note: 'Broken jar',
      );
      final billId = await helper.insertBill(
        Bill(customerName: 'Meera', totalAmount: 150, itemCount: 1),
        [
          BillItem(
            productId: productId,
            productUuid: product.uuid,
            productName: 'Filter Coffee',
            quantity: 1,
            sellingPriceSnapshot: 150,
          ),
        ],
      );
      await helper.updateBillCustomerDetails(
        billId,
        customerName: 'Meera Nair',
        isB2b: false,
      );

      final all = await helper.getShopAuditLog();
      expect(all.length, 3);
      expect(all.map((e) => e.entityType).toSet(), {'bill', 'product', 'stock'});

      final onlyProducts = await helper.getShopAuditLog(entityType: 'product');
      expect(onlyProducts, hasLength(1));
      expect(onlyProducts.single.details, contains('Filter Coffee'));

      final onlyStock = await helper.getShopAuditLog(entityType: 'stock');
      expect(onlyStock, hasLength(1));
      expect(onlyStock.single.details, contains('Broken jar'));

      final searched = await helper.getShopAuditLog(query: 'Meera');
      expect(searched, hasLength(1));
      expect(searched.single.entityType, 'bill');
    });

    testWidgets('AuditLogScreen displays entries and filters by entity type & search', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await helper.logAuditEvent(
          entityType: 'bill',
          entityUuid: 'bill-1',
          action: AuditAction.edited,
          details: 'Notes: old → Urgent',
        );
        await helper.logAuditEvent(
          entityType: 'product',
          entityUuid: 'prod-1',
          action: AuditAction.updated,
          details: 'Soap · Selling price: ₹20.00 → ₹25.00',
        );
        await helper.logAuditEvent(
          entityType: 'stock',
          entityUuid: 'prod-1',
          action: AuditAction.stockAdjusted,
          details: 'Soap: -3 · Damaged',
        );
      });

      await tester.pumpWidget(const MaterialApp(home: AuditLogScreen()));
      await _settle(tester);

      expect(find.text('Activity & audit'), findsOneWidget);
      expect(find.textContaining('Urgent'), findsOneWidget);
      expect(find.textContaining('Soap · Selling price'), findsOneWidget);
      expect(find.textContaining('Soap: -3'), findsOneWidget);

      // Filter by Stock
      await tester.tap(find.byKey(const ValueKey('audit-filter-stock')));
      await _settle(tester);
      expect(find.textContaining('Soap: -3'), findsOneWidget);
      expect(find.textContaining('Urgent'), findsNothing);

      // Switch back to All and search
      await tester.tap(find.byKey(const ValueKey('audit-filter-all')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('audit-log-search')),
        'Urgent',
      );
      await _settle(tester);
      expect(find.text('Notes: old → Urgent'), findsOneWidget);
      expect(find.textContaining('Soap: -3'), findsNothing);
    });
  });

  group('I10: StockMovementHistorySheet running balance & type filters', () {
    testWidgets('computes running balance backward and filters by movement type', (
      tester,
    ) async {
      // Movements newest-first:
      // 1) Sale -3 -> Bal: 15 (current quantity)
      // 2) Adjustment -2 -> Bal: 18 (15 - (-3))
      // 3) Purchase +20 -> Bal: 20 (18 - (-2))
      final now = DateTime(2026, 11, 27, 12, 0);
      final product = Product(
        id: 1,
        uuid: 'prod-1',
        name: 'Basmati Rice',
        sellingPrice: 90,
        purchasePrice: 70,
        quantity: 15,
        unit: 'kg',
      );
      final movements = [
        StockMovement(
          uuid: 'm3',
          shopId: 'shop',
          productId: 1,
          productUuid: 'prod-1',
          movementType: StockMovementType.sale,
          quantityDelta: -3,
          createdAt: now,
          updatedAt: now,
        ),
        StockMovement(
          uuid: 'm2',
          shopId: 'shop',
          productId: 1,
          productUuid: 'prod-1',
          movementType: StockMovementType.adjustment,
          quantityDelta: -2,
          reason: StockAdjustmentReason.damage,
          createdAt: now.subtract(const Duration(hours: 1)),
          updatedAt: now.subtract(const Duration(hours: 1)),
        ),
        StockMovement(
          uuid: 'm1',
          shopId: 'shop',
          productId: 1,
          productUuid: 'prod-1',
          movementType: StockMovementType.purchase,
          quantityDelta: 20,
          createdAt: now.subtract(const Duration(hours: 2)),
          updatedAt: now.subtract(const Duration(hours: 2)),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StockMovementHistorySheet(
              product: product,
              movements: movements,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bal: 15'), findsOneWidget);
      expect(find.text('Bal: 18'), findsOneWidget);
      expect(find.text('Bal: 20'), findsOneWidget);

      // Filter by Purchase: only purchase row visible, still showing true Bal: 20
      await tester.tap(find.byKey(const ValueKey('stock-filter-purchase')));
      await tester.pumpAndSettle();
      expect(find.text('Bal: 20'), findsOneWidget);
      expect(find.text('Bal: 15'), findsNothing);
      expect(find.text('Bal: 18'), findsNothing);

      // Filter by Return: empty state
      await tester.tap(find.byKey(const ValueKey('stock-filter-return')));
      await tester.pumpAndSettle();
      expect(find.text('No matching stock movements'), findsOneWidget);
    });
  });
}
