import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/product_purchase.dart';
import 'package:storely/utils/csv_importer.dart';

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
  });

  test('MRP is kept on the product and snapshotted on the bill', () async {
    final id = await db.insertProduct(
      Product(
        name: 'Shampoo',
        sellingPrice: 90,
        manualPrice: 90,
        directPriceToggle: true,
        printedMrp: 99,
        purchasePrice: 70,
        quantity: 5,
      ),
    );
    final product = (await db.getProductById(id))!;
    expect(product.printedMrp, 99);

    final item = await db.buildBillItemForProduct(product);
    item.quantity = 2;
    expect(item.mrpSnapshot, 99);
    expect(item.mrpSaving, 18);
    final billId = await db.insertBill(
      Bill(customerName: 'A', totalAmount: 180, itemCount: 1, isPaid: true),
      [item],
    );
    final bill = (await db.getBillById(billId))!;
    expect(bill.items.single.mrpSnapshot, 99);

    // MRP at or below the selling price is not a saving.
    final plain = await db.buildBillItemForProduct(
      product.copyWith(printedMrp: 90),
    );
    expect(plain.mrpSnapshot, isNull);
  });

  test(
    'expiring stock follows newest-purchase-in-stock and writes off',
    () async {
      final now = DateTime.now();
      final soon = DateTime(now.year, now.month, now.day + 5);
      final later = DateTime(now.year, now.month + 6, now.day);
      final past = DateTime(now.year, now.month, now.day - 2);

      final id = await db.insertProduct(
        Product(
          name: 'Milk',
          sellingPrice: 30,
          purchasePrice: 25,
          quantity: 10,
          purchaseBatchNo: 'B1',
          purchaseExpiry: past,
        ),
      );
      var milk = (await db.getProductById(id))!;
      await db.restockProduct(
        milk.copyWith(purchaseBatchNo: 'B2', purchaseExpiry: soon),
        quantityAdded: 10,
        purchaseDate: now.add(const Duration(minutes: 1)),
      );
      await db.restockProduct(
        milk.copyWith(purchaseBatchNo: 'B3', purchaseExpiry: later),
        quantityAdded: 10,
        purchaseDate: now.add(const Duration(minutes: 2)),
      );

      // 30 in stock: all three batches are on the shelf.
      var batches = await db.expiringStock(days: 30);
      expect(batches.map((b) => b.batchNo), ['B1', 'B2']);
      expect(batches.first.isExpired(now), isTrue);

      // Sell 15: the oldest batch (B1) is assumed sold, half of B2 left.
      await db.adjustStock(id, delta: -15, reason: StockAdjustmentReason.count);
      batches = await db.expiringStock(days: 30);
      expect(batches.single.batchNo, 'B2');
      expect(batches.single.quantity, 5);

      // Writing off removes it from the list.
      await db.adjustStock(
        id,
        delta: -batches.single.quantity,
        reason: StockAdjustmentReason.expired,
      );
      expect(await db.expiringStock(days: 30), isEmpty);
      milk = (await db.getProductById(id))!;
      expect(milk.quantity, 10);
    },
  );

  test(
    'import: MRP column next to a selling price is the printed MRP',
    () async {
      final both = await CsvImporter.parseBytesDetailed(
        Uint8List.fromList(
          utf8.encode('Item,Qty,Cost,Sale Price,MRP\nSoap,5,20,28,30\n'),
        ),
        fileName: 'a.csv',
      );
      expect(both.products.single.sellingPrice, 28);
      expect(both.products.single.printedMrp, 30);

      final alone = await CsvImporter.parseBytesDetailed(
        Uint8List.fromList(utf8.encode('Item,Qty,Cost,MRP\nSoap,5,20,30\n')),
        fileName: 'b.csv',
      );
      expect(alone.products.single.sellingPrice, 30);
      expect(alone.products.single.printedMrp, isNull);
    },
  );
}
