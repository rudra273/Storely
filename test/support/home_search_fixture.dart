import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/customer.dart';
import 'package:storely/models/product.dart';

Future<void> seedHomeSearchFixture() async {
  final db = DatabaseHelper.instance;
  final shop = await db.currentShopId();
  final sql = await db.database;
  for (var index = 5; index >= 0; index--) {
    final letter = String.fromCharCode(65 + index);
    await db.insertProduct(
      Product(
        uuid: 'product-$letter',
        name: 'Match Product $letter',
        purchasePrice: 100,
        sellingPrice: 118,
        quantity: 10,
        productCode: 'CODE-$letter',
        barcode: 'BAR-$letter',
        category: 'Tools',
        supplier: 'Secret Vendor',
      ),
    );
    await sql.insert(
      'bills',
      Bill(
        uuid: 'bill-$letter',
        shopId: shop,
        billNumber: 'MATCH-$letter',
        customerName: 'Buyer $letter',
        customerPhone: '',
        totalAmount: 118,
        paidAmount: 118,
        balanceDue: 0,
        isPaid: true,
        itemCount: 0,
        createdAt: DateTime(2026, 1, index + 1),
      ).toMap()..remove('id'),
    );
    await db.saveCustomerProfile(
      Customer(
        totalPurchaseAmount: 0,
        billCount: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        uuid: 'customer-$letter',
        shopId: shop,
        name: 'Match Customer $letter',
        phone: '555000000$index',
        address: 'Road $letter',
        gstin: 'GST-$letter',
      ),
    );
  }
  await sql.insert(
    'products',
    Product(
      quantity: 0,
      uuid: 'foreign-product',
      shopId: 'foreign-shop',
      name: 'Match Foreign Product',
    ).toMap()..remove('id'),
  );
  await sql.insert(
    'bills',
    Bill(
      uuid: 'foreign-bill',
      shopId: 'foreign-shop',
      billNumber: 'MATCH-FOREIGN',
      customerName: 'Foreign Buyer',
      customerPhone: '5550000000',
      paidAmount: 0,
      balanceDue: 118,
      isPaid: false,
      totalAmount: 118,
      itemCount: 0,
    ).toMap()..remove('id'),
  );
  await sql.insert(
    'customers',
    Customer(
      totalPurchaseAmount: 0,
      billCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      uuid: 'foreign-customer',
      shopId: 'foreign-shop',
      name: 'Match Foreign Customer',
      phone: '5550000009',
    ).toMap()..remove('id'),
  );
  await sql.insert(
    'bills',
    Bill(
      uuid: 'foreign-bill-only',
      shopId: 'foreign-shop',
      billNumber: 'FOREIGN-ONLY',
      customerName: 'Match Foreign Only Buyer',
      customerPhone: '5559999999',
      totalAmount: 118,
      itemCount: 0,
    ).toMap()..remove('id'),
  );
}
