import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
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
            itemCount: item.quantity,
            isPaid: false,
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
        expect(savedItem.productId, productId);
        expect(savedItem.productName, 'Notebook');
        expect(savedItem.quantity, 3);
        expect(savedItem.unit, 'pcs');
        expect(savedItem.purchasePriceSnapshot, 100);
        expect(savedItem.sellingPriceSnapshot, 157.5);
        expect(savedItem.costSnapshot, 105);
        expect(savedItem.profitSnapshot, 52.5);
        expect(savedItem.wasDirectPrice, isFalse);
        expect(updatedProduct!.quantity, 7);
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
      expect(itemRows, isEmpty);
    });

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

    test('stock deduction never makes product quantity negative', () async {
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
      expect(product!.quantity, 0);
    });
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
