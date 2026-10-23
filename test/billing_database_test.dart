import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/customer.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/product.dart';

void main() {
  late DatabaseHelper db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = DatabaseHelper.instance;
    await db.close();
    await _deleteStorelyDb();
  });

  tearDown(() async {
    db.assertAdminMutation = null;
    await db.close();
    await _deleteStorelyDb();
  });

  group('Billing database flow', () {
    test(
      'inserts bill with item snapshots and deducts product stock',
      () async {
        await db.saveGlobalPricingSettings(
          const GlobalPricingSettings(
            defaultGstPercent: 0,
            defaultOverheadCost: 5,
            defaultProfitMarginPercent: 50,
            gstRegistered: false,
          ),
        );
        final productId = await db.insertProduct(
          Product(
            name: 'Notebook',
            mrp: 0,
            purchasePrice: 100,
            quantity: 10,
            unit: 'pcs',
          ),
        );
        final product = await db.getProductById(productId);
        final item = await db.buildBillItemForProduct(product!);
        item.quantity = 3;

        final billId = await db.insertBill(
          Bill(
            customerName: 'Anita Store',
            customerPhone: '+91 9876543210',
            subtotalAmount: item.subtotal,
            discountPercent: 10,
            discountAmount: item.subtotal * 0.10,
            totalAmount: item.subtotal * 0.90,
            itemCount: item.quantity.round(),
            isPaid: false,
            paymentMethod: 'online',
          ),
          [item],
        );

        final bills = await db.getAllBills();
        final bill = bills.single;
        final savedItem = bill.items.single;
        final updatedProduct = await db.getProductById(productId);
        final customerRows = await _customerRows();

        expect(bill.id, billId);
        expect(bill.customerId, isNotNull);
        expect(bill.customerName, 'Anita Store');
        expect(bill.customerPhone, '+91 9876543210');
        expect(bill.subtotalAmount, 472.5);
        expect(bill.discountPercent, 10);
        expect(bill.discountAmount, 47.25);
        expect(bill.totalAmount, 425.25);
        expect(bill.itemCount, 3);
        expect(bill.isPaid, isFalse);
        expect(bill.paymentMethod, 'online');
        expect(savedItem.productId, productId);
        expect(savedItem.productName, 'Notebook');
        expect(savedItem.quantity, 3);
        expect(savedItem.unit, 'pcs');
        expect(savedItem.purchasePriceSnapshot, 100);
        expect(savedItem.sellingPriceSnapshot, 157.5);
        expect(savedItem.costSnapshot, 105);
        expect(savedItem.profitSnapshot, 52.5);
        expect(savedItem.wasDirectPrice, isFalse);
        expect(updatedProduct!.sellingPrice, 157.5);
        expect(updatedProduct.quantity, 7);
        expect(customerRows, hasLength(1));
        expect(customerRows.single['id'], bill.customerId);
        expect(customerRows.single['name'], 'Anita Store');
        expect(customerRows.single['phone'], '919876543210');
        expect(customerRows.single['total_purchase_amount'], 425.25);
        expect(customerRows.single['bill_count'], 1);
      },
    );

    test('manual direct-price bill item uses product price snapshot', () async {
      final productId = await db.insertProduct(
        Product(
          name: 'Paint Bucket',
          mrp: 250,
          purchasePrice: 180,
          directPriceToggle: true,
          manualPrice: 250,
          quantity: 4,
          unit: 'ltr',
        ),
      );
      final product = await db.getProductById(productId);
      final item = await db.buildBillItemForProduct(product!);

      expect(item.productId, productId);
      expect(item.productName, 'Paint Bucket');
      expect(item.unit, 'ltr');
      expect(item.sellingPriceSnapshot, 250);
      expect(item.wasDirectPrice, isTrue);
      expect(item.priceLabel, '₹250.00 / ltr');
    });

    test('local shop id is generated and used by business rows', () async {
      final shopId = await db.currentShopId();
      expect(shopId, isNot('local-shop'));
      expect(shopId, isNotEmpty);

      final productId = await db.insertProduct(
        Product(name: 'Generated Shop Item', mrp: 10, quantity: 1),
      );
      await db.insertBill(
        Bill(customerName: 'Customer', totalAmount: 10, itemCount: 1),
        [
          BillItem(
            productId: productId,
            productName: 'Generated Shop Item',
            mrp: 10,
          ),
        ],
      );

      final database = await db.database;
      final productRows = await database.query('products');
      final billRows = await database.query('bills');
      expect(productRows.single['shop_id'], shopId);
      expect(billRows.single['shop_id'], shopId);
    });

    test('bill numbers allocate from invoice series without reuse', () async {
      final firstId = await db.insertBill(
        Bill(customerName: 'Customer', totalAmount: 10, itemCount: 1),
        [BillItem(productName: 'Item A', mrp: 10)],
      );
      await db.insertBill(
        Bill(customerName: 'Customer', totalAmount: 20, itemCount: 1),
        [BillItem(productName: 'Item B', mrp: 20)],
      );
      await db.deleteBill(firstId);
      await db.insertBill(
        Bill(customerName: 'Customer', totalAmount: 30, itemCount: 1),
        [BillItem(productName: 'Item C', mrp: 30)],
      );

      final bills = await db.getAllBills();
      final numbers = bills.map((bill) => bill.billNumber).toList();
      expect(numbers, contains(endsWith('/0002')));
      expect(numbers, contains(endsWith('/0003')));
      expect(numbers, isNot(contains(endsWith('/0001'))));
    });

    test('sequence reset onto an existing bill number skips forward', () async {
      // A pattern without date tokens on a daily reset restarts at 0001
      // every day. That number already exists, which used to fail the
      // insert and roll back the sequence, blocking all later bills.
      // Bill Settings now rejects this pattern, so write it directly the
      // way an older install could have stored it.
      await db.getDefaultInvoiceSeriesSettings();
      final raw = await db.database;
      await raw.update('invoice_series', {
        'format_template': 'INV-{SEQ}',
        'reset_period': 'daily',
      });
      Future<void> billOn(DateTime day) => db.insertBill(
        Bill(
          customerName: 'Customer',
          totalAmount: 10,
          itemCount: 1,
          createdAt: day,
        ),
        [BillItem(productName: 'Item', mrp: 10)],
      );

      await billOn(DateTime(2026, 10, 22, 10));
      final cancelled = (await db.getAllBills()).single;
      await db.cancelBill(cancelled.id!, reason: 'test');
      await billOn(DateTime(2026, 10, 22, 11));
      await billOn(DateTime(2026, 10, 23, 10));
      await billOn(DateTime(2026, 10, 23, 11));

      final numbers = (await db.getAllBills())
          .map((bill) => bill.billNumber)
          .toList();
      expect(numbers, containsAll(['INV-0002', 'INV-0003', 'INV-0004']));
    });

    test('round-off amount is stored and loaded with the bill', () async {
      await db.insertBill(
        Bill(
          customerName: 'Customer',
          subtotalAmount: 58.6,
          roundOffAmount: 0.4,
          totalAmount: 59,
          itemCount: 1,
        ),
        [BillItem(productName: 'Item', mrp: 58.6)],
      );
      final bill = (await db.getAllBills()).single;
      expect(bill.roundOffAmount, 0.4);
      expect(bill.totalAmount, 59);
      expect(bill.paidAmount, 59);
      expect(bill.balanceDue, 0);
    });

    test('payment and stock dates are stored in local time', () async {
      final productId = await db.insertProduct(
        Product(name: 'Tea', mrp: 0, purchasePrice: 10, quantity: 5),
      );
      final product = await db.getProductById(productId);
      final item = await db.buildBillItemForProduct(product!);
      final billId = await db.insertBill(
        Bill(
          customerName: 'Customer',
          subtotalAmount: item.subtotal,
          totalAmount: item.subtotal,
          itemCount: 1,
          isPaid: false,
        ),
        [item],
      );
      // An instant given in UTC must land on the shop's local calendar day.
      final paidAt = DateTime.utc(2026, 1, 10, 20, 0);
      await db.recordBillPayment(billId, amount: 1, receivedAt: paidAt);
      await db.updateBillPaidStatus(billId, true);

      final raw = await db.database;
      final received = (await raw.query(
        'bill_payments',
        orderBy: 'id',
      )).map((row) => row['received_at'] as String).toList();
      expect(received.first, paidAt.toLocal().toIso8601String());
      expect(received.every((value) => !value.endsWith('Z')), isTrue);

      final movements = await raw.query('stock_movements');
      expect(
        movements.every((row) => !(row['created_at'] as String).endsWith('Z')),
        isTrue,
      );

      final day = paidAt.toLocal().toIso8601String().substring(0, 10);
      expect(await db.kpiCollected(from: day, to: day), 1);
    });

    test('getBillById and frequently-sold counts', () async {
      final tea = await db.insertProduct(
        Product(name: 'Tea', mrp: 0, purchasePrice: 10, quantity: 50),
      );
      final salt = await db.insertProduct(
        Product(name: 'Salt', mrp: 0, purchasePrice: 10, quantity: 50),
      );
      Future<int> sell(int productId) async {
        final item = await db.buildBillItemForProduct(
          (await db.getProductById(productId))!,
        );
        return db.insertBill(
          Bill(
            customerName: 'C',
            subtotalAmount: item.subtotal,
            totalAmount: item.subtotal,
            itemCount: 1,
          ),
          [item],
        );
      }

      final first = await sell(tea);
      await sell(tea);
      await sell(salt);

      final bill = await db.getBillById(first);
      expect(bill!.items.single.productId, tea);
      expect(await db.getBillById(99999), isNull);
      expect(await db.getProductSaleCounts(), {tea: 2, salt: 1});
    });

    test('held bills and the auto-saved cart', () async {
      final items = [
        BillItem(productName: 'Tea', mrp: 120, quantity: 2),
        BillItem(productName: 'Sugar', mrp: 45, quantity: 1.5, unit: 'kg'),
      ];
      final id = await db.holdBill('12:30 PM · Tea +1', items);
      final held = await db.getHeldBills();
      expect(held.single.id, id);
      expect(held.single.label, '12:30 PM · Tea +1');
      expect(held.single.items.map((i) => i.productName), ['Tea', 'Sugar']);
      expect(held.single.items.last.quantity, 1.5);
      expect(held.single.total, 307.5);
      await db.deleteHeldBill(id);
      expect(await db.getHeldBills(), isEmpty);

      await db.saveCartDraft(items);
      expect((await db.loadCartDraft()).length, 2);
      expect(await db.getHeldBills(), isEmpty, reason: 'draft is not held');
      await db.saveCartDraft(const []);
      expect(await db.loadCartDraft(), isEmpty);
    });

    test('only admins can mark a paid bill unpaid', () async {
      final billId = await db.insertBill(
        Bill(customerName: 'Customer', totalAmount: 50, itemCount: 1),
        [BillItem(productName: 'Item', mrp: 50)],
      );
      db.assertAdminMutation = () async =>
          throw StateError('Only shop admins can do this');

      await expectLater(
        db.updateBillPaidStatus(billId, false),
        throwsA(isA<StateError>()),
      );
      final stillPaid = (await db.getAllBills()).single;
      expect(stillPaid.isPaid, isTrue);
      expect(stillPaid.paidAmount, 50);

      db.assertAdminMutation = null;
      await db.updateBillPaidStatus(billId, false);
      final unpaid = (await db.getAllBills()).single;
      expect(unpaid.isPaid, isFalse);

      // Staff can still collect payment.
      db.assertAdminMutation = () async =>
          throw StateError('Only shop admins can do this');
      await db.updateBillPaidStatus(billId, true);
      expect((await db.getAllBills()).single.isPaid, isTrue);
    });

    test('default bill numbers are GST-safe and reset each April', () async {
      Future<void> billOn(DateTime day) => db.insertBill(
        Bill(
          customerName: 'Customer',
          totalAmount: 10,
          itemCount: 1,
          createdAt: day,
        ),
        [BillItem(productName: 'Item', mrp: 10)],
      );
      await billOn(DateTime(2026, 3, 30));
      await billOn(DateTime(2026, 3, 31));
      await billOn(DateTime(2026, 4, 1));

      final numbers = (await db.getAllBills())
          .map((bill) => bill.billNumber)
          .toList();
      expect(
        numbers,
        containsAll(['INV/2526/0001', 'INV/2526/0002', 'INV/2627/0001']),
      );
      expect(numbers.every((n) => n.length <= 16), isTrue);
    });

    test('invalid bill number patterns are rejected on save', () async {
      await expectLater(
        db.saveDefaultInvoiceSeriesSettings(
          const InvoiceSeriesSettings(
            formatTemplate: 'INV-{YYYY}{MM}{DD}-{SEQ}',
            resetPeriod: 'daily',
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
      await db.saveDefaultInvoiceSeriesSettings(
        const InvoiceSeriesSettings(
          formatTemplate: 'SK/{FY}/{SEQ}',
          resetPeriod: 'financial_year',
        ),
      );
      final saved = await db.getDefaultInvoiceSeriesSettings();
      expect(saved.formatTemplate, 'SK/{FY}/{SEQ}');
    });

    test(
      'selling decimal stock down to zero is not blocked by drift',
      () async {
        final productId = await db.insertProduct(
          Product(
            name: 'Loose Dal',
            mrp: 0,
            purchasePrice: 100,
            quantity: 0.3,
            unit: 'kg',
          ),
        );
        for (var i = 0; i < 3; i++) {
          final product = await db.getProductById(productId);
          final item = await db.buildBillItemForProduct(product!);
          item.quantity = 0.1;
          await db.insertBill(
            Bill(
              customerName: 'Customer',
              subtotalAmount: item.subtotal,
              totalAmount: item.subtotal,
              itemCount: 1,
            ),
            [item],
          );
        }

        final product = await db.getProductById(productId);
        expect(product!.quantity, closeTo(0, 1e-9));
      },
    );

    test('non-GST shop bill items do not snapshot output GST', () async {
      await db.saveGlobalPricingSettings(
        const GlobalPricingSettings(
          defaultGstPercent: 18,
          gstRegistered: false,
        ),
      );
      final productId = await db.insertProduct(
        Product(name: 'Input Tax Item', purchasePrice: 100, quantity: 1),
      );

      final product = await db.getProductById(productId);
      final item = await db.buildBillItemForProduct(product!);

      expect(item.gstSnapshot, 0);
      expect(item.cgstAmountSnapshot, 0);
      expect(item.sgstAmountSnapshot, 0);
      expect(item.igstAmountSnapshot, 0);
    });

    test('paid status can be updated after bill creation', () async {
      final billId = await db.insertBill(
        Bill(
          customerName: 'Walk-in Customer',
          totalAmount: 80,
          itemCount: 1,
          isPaid: false,
        ),
        [BillItem(productName: 'Loose Item', mrp: 80)],
      );

      await db.updateBillPaidStatus(billId, true);

      final bill = (await db.getAllBills()).single;
      expect(bill.isPaid, isTrue);
    });

    test('paid status records only the remaining balance', () async {
      final billId = await db.insertBill(
        Bill(
          customerName: 'Walk-in Customer',
          totalAmount: 100,
          paidAmount: 30,
          balanceDue: 70,
          paymentStatus: Bill.statusPartial,
          itemCount: 1,
          isPaid: false,
        ),
        [BillItem(productName: 'Loose Item', mrp: 100)],
      );

      await db.updateBillPaidStatus(billId, true);

      final bill = (await db.getAllBills()).single;
      expect(bill.isPaid, isTrue);
      expect(bill.paidAmount, 100);
      expect(bill.balanceDue, 0);
    });

    test('bill payment method defaults to cash', () async {
      await db.insertBill(
        Bill(customerName: 'Customer', totalAmount: 80, itemCount: 1),
        [BillItem(productName: 'Loose Item', mrp: 80)],
      );

      final bill = (await db.getAllBills()).single;
      expect(bill.paymentMethod, 'cash');
    });

    test('partial bill payment is tracked with balance due', () async {
      final billId = await db.insertBill(
        Bill(
          customerName: 'B2B Buyer',
          customerPhone: '9876543210',
          billType: Bill.typeB2b,
          customerGstin: '27AAAAA0000A1Z5',
          customerGstLegalName: 'B2B Buyer Private Limited',
          customerGstTradeName: 'B2B Buyer',
          customerAddressSnapshot: 'Industrial Estate, Mumbai',
          placeOfSupplyStateCode: '27',
          totalAmount: 1000,
          itemCount: 1,
          isPaid: false,
          paidAmount: 400,
          paymentMethod: 'online',
        ),
        [
          BillItem(
            productName: 'Taxed Item',
            mrp: 1000,
            hsnCodeSnapshot: '123456',
            gstPercentSnapshot: 18,
            taxableValueSnapshot: 847.46,
            gstSnapshot: 152.54,
          ),
        ],
      );

      var bill = (await db.getAllBills()).single;
      expect(bill.paymentStatus, Bill.statusPartial);
      expect(bill.paidAmount, 400);
      expect(bill.balanceDue, 600);
      expect(bill.customerGstin, '27AAAAA0000A1Z5');
      expect(bill.customerGstLegalName, 'B2B Buyer Private Limited');
      expect(bill.customerGstTradeName, 'B2B Buyer');
      expect(bill.customerAddressSnapshot, 'Industrial Estate, Mumbai');
      expect(bill.placeOfSupplyStateCode, '27');
      expect(bill.items.single.hsnCodeSnapshot, '123456');

      await db.recordBillPayment(billId, amount: 600);
      bill = (await db.getAllBills()).single;
      expect(bill.paymentStatus, Bill.statusPaid);
      expect(bill.isPaid, isTrue);
      expect(bill.balanceDue, 0);
    });

    test('same customer phone is unique and accumulates bill totals', () async {
      await db.insertBill(
        Bill(
          customerName: 'Ravi',
          customerPhone: '9876543210',
          totalAmount: 100,
          itemCount: 1,
        ),
        [BillItem(productName: 'Item A', mrp: 100)],
      );
      await db.insertBill(
        Bill(
          customerName: 'Ravi Traders',
          customerPhone: '+91 98765 43210',
          totalAmount: 250,
          itemCount: 2,
        ),
        [BillItem(productName: 'Item B', mrp: 125, quantity: 2)],
      );

      final customerRows = await _customerRows();
      final bills = await db.getAllBills();

      expect(customerRows, hasLength(1));
      expect(customerRows.single['name'], 'Ravi Traders');
      expect(customerRows.single['phone'], '919876543210');
      expect(customerRows.single['total_purchase_amount'], 350);
      expect(customerRows.single['bill_count'], 2);
      expect(bills.map((bill) => bill.customerId).toSet(), hasLength(1));
    });

    test(
      'customer ledger is recalculated on reopen without doubling',
      () async {
        await db.insertBill(
          Bill(
            customerName: 'Ravi',
            customerPhone: '9876543210',
            totalAmount: 100,
            itemCount: 1,
          ),
          [BillItem(productName: 'Item A', mrp: 100)],
        );
        await db.insertBill(
          Bill(
            customerName: 'Ravi Traders',
            customerPhone: '+91 98765 43210',
            totalAmount: 250,
            itemCount: 2,
          ),
          [BillItem(productName: 'Item B', mrp: 125, quantity: 2)],
        );

        final database = await db.database;
        await database.update('customers', {
          'total_purchase_amount': 700,
          'bill_count': 4,
        });
        await db.close();

        final customers = await DatabaseHelper.instance.getAllCustomers();

        expect(customers, hasLength(1));
        expect(customers.single.name, 'Ravi Traders');
        expect(customers.single.phone, '919876543210');
        expect(customers.single.totalPurchaseAmount, 350);
        expect(customers.single.billCount, 2);
      },
    );

    test('customer data remains optional for walk-in bills', () async {
      await db.insertBill(
        Bill(customerName: 'Walk-in Customer', totalAmount: 50, itemCount: 1),
        [BillItem(productName: 'Loose Item', mrp: 50)],
      );

      final bills = await db.getAllBills();
      final customerRows = await _customerRows();

      expect(bills.single.customerId, isNull);
      expect(customerRows, isEmpty);
    });

    test('deleting a bill removes its stored line items', () async {
      final billId = await db.insertBill(
        Bill(customerName: 'Customer', totalAmount: 120, itemCount: 2),
        [
          BillItem(productName: 'Item A', mrp: 50),
          BillItem(productName: 'Item B', mrp: 70),
        ],
      );

      await db.deleteBill(billId);

      expect(await db.getAllBills(), isEmpty);
      final database = await db.database;
      final itemRows = await database.query(
        'bill_items',
        where: 'bill_id = ?',
        whereArgs: [billId],
      );
      expect(itemRows, hasLength(2));
      expect(itemRows.every((row) => row['deleted_at'] != null), isTrue);
    });

    test(
      'cancel bill stores reason and removes it from active bills',
      () async {
        final billId = await db.insertBill(
          Bill(customerName: 'Customer', totalAmount: 120, itemCount: 1),
          [BillItem(productName: 'Item A', mrp: 120)],
        );

        await db.cancelBill(billId, reason: 'Wrong customer selected');

        expect(await db.getAllBills(), isEmpty);
        final database = await db.database;
        final rows = await database.query(
          'bills',
          where: 'id = ?',
          whereArgs: [billId],
        );
        expect(rows.single['lifecycle_status'], Bill.lifecycleCancelled);
        expect(rows.single['cancel_reason'], 'Wrong customer selected');
        expect(rows.single['cancelled_at'], isNotNull);
        expect(rows.single['deleted_at'], isNotNull);
      },
    );

    test('cancelled bills stay traceable via getCancelledBills', () async {
      final billId = await db.insertBill(
        Bill(customerName: 'Customer', totalAmount: 120, itemCount: 1),
        [BillItem(productName: 'Item A', mrp: 120)],
      );

      await db.cancelBill(billId, reason: 'Customer returned');

      // Absent from active bills, but recoverable for reference/audit.
      expect(await db.getAllBills(), isEmpty);
      final cancelled = await db.getCancelledBills();
      expect(cancelled, hasLength(1));
      expect(cancelled.single.id, billId);
      expect(cancelled.single.cancelReason, 'Customer returned');
      expect(cancelled.single.lifecycleStatus, Bill.lifecycleCancelled);
      // Line items are preserved on the cancelled record.
      expect(cancelled.single.items, hasLength(1));
    });

    test(
      'saved bill customer snapshots are not changed by customer edit',
      () async {
        await db.insertBill(
          Bill(
            customerName: 'Original Buyer',
            customerPhone: '9876543210',
            billType: Bill.typeB2b,
            customerGstin: '27AAAAA0000A1Z5',
            customerGstLegalName: 'Original Legal Name',
            customerAddressSnapshot: 'Old Address',
            placeOfSupplyStateCode: '27',
            totalAmount: 500,
            itemCount: 1,
          ),
          [BillItem(productName: 'Item A', mrp: 500)],
        );
        final customer = (await db.getAllCustomers()).single;
        final now = DateTime.now();

        await db.saveCustomerProfile(
          Customer(
            id: customer.id,
            uuid: customer.uuid,
            shopId: customer.shopId,
            name: 'Updated Buyer',
            phone: customer.phone,
            address: 'New Address',
            gstin: '29BBBBB0000B1Z5',
            gstLegalName: 'Updated Legal Name',
            totalPurchaseAmount: customer.totalPurchaseAmount,
            billCount: customer.billCount,
            createdAt: customer.createdAt,
            updatedAt: now,
          ),
        );

        final bill = (await db.getAllBills()).single;
        expect(bill.customerName, 'Original Buyer');
        expect(bill.customerGstin, '27AAAAA0000A1Z5');
        expect(bill.customerGstLegalName, 'Original Legal Name');
        expect(bill.customerAddressSnapshot, 'Old Address');
        expect(bill.placeOfSupplyStateCode, '27');
      },
    );

    test('deleting a customer bill reduces customer purchase total', () async {
      final firstBillId = await db.insertBill(
        Bill(
          customerName: 'Asha',
          customerPhone: '9123456789',
          totalAmount: 300,
          itemCount: 1,
        ),
        [BillItem(productName: 'Item A', mrp: 300)],
      );
      await db.insertBill(
        Bill(
          customerName: 'Asha',
          customerPhone: '9123456789',
          totalAmount: 150,
          itemCount: 1,
        ),
        [BillItem(productName: 'Item B', mrp: 150)],
      );

      await db.deleteBill(firstBillId);

      final customerRows = await _customerRows();
      expect(customerRows, hasLength(1));
      expect(customerRows.single['total_purchase_amount'], 150);
      expect(customerRows.single['bill_count'], 1);
    });

    test(
      'deleting last customer bill keeps customer identity with zero total',
      () async {
        final billId = await db.insertBill(
          Bill(
            customerName: 'Nila',
            customerPhone: '9876500000',
            totalAmount: 200,
            itemCount: 1,
          ),
          [BillItem(productName: 'Item A', mrp: 200)],
        );

        await db.deleteBill(billId);
        final customers = await db.getAllCustomers();

        expect(customers, hasLength(1));
        expect(customers.single.name, 'Nila');
        expect(customers.single.phone, '919876500000');
        expect(customers.single.totalPurchaseAmount, 0);
        expect(customers.single.billCount, 0);
      },
    );

    test(
      'selling more than the recorded stock is allowed and goes negative',
      () async {
        final productId = await db.insertProduct(
          Product(name: 'Low Stock Item', mrp: 25, quantity: 2),
        );

        await db.insertBill(
          Bill(customerName: 'Customer', totalAmount: 125, itemCount: 5),
          [
            BillItem(
              productId: productId,
              productName: 'Low Stock Item',
              mrp: 25,
              quantity: 5,
            ),
          ],
        );

        final product = await db.getProductById(productId);
        expect(product!.quantity, -3);
        expect(await db.getAllBills(), hasLength(1));

        // Restocking from negative: the new purchase sets the cost.
        await db.restockProduct(
          product.copyWith(purchasePrice: 20),
          quantityAdded: 10,
          purchaseDate: DateTime(2026, 10, 23),
        );
        final restocked = await db.getProductById(productId);
        expect(restocked!.quantity, 7);
        expect(restocked.purchasePrice, 20);
      },
    );
  });
}

Future<void> _deleteStorelyDb() async {
  final dbPath = await getDatabasesPath();
  await deleteDatabase(p.join(dbPath, 'storely.db'));
}

Future<List<Map<String, Object?>>> _customerRows() async {
  final database = await DatabaseHelper.instance.database;
  return database.query('customers', orderBy: 'id ASC');
}
