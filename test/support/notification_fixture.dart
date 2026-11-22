import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/product.dart';

Future<void> seedNotificationFixture() async {
  final db = DatabaseHelper.instance;
  final shop = await db.currentShopId();
  final sql = await db.database;
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  for (final age in [7, 8, 30, 31, 60, 61]) {
    await sql.insert(
      'bills',
      Bill(
        uuid: 'age-$age',
        shopId: shop,
        billNumber: 'AGE-$age',
        customerName: 'Age $age',
        totalAmount: 118.25,
        paidAmount: 0,
        balanceDue: 118.25,
        isPaid: false,
        itemCount: 0,
        createdAt: day.subtract(Duration(days: age)),
      ).toMap()..remove('id'),
    );
  }
  await sql.insert(
    'bills',
    Bill(
      uuid: 'foreign-alert',
      shopId: 'foreign-shop',
      billNumber: 'FOREIGN',
      customerName: 'Foreign Customer',
      totalAmount: 999,
      paidAmount: 0,
      balanceDue: 999,
      isPaid: false,
      itemCount: 0,
      createdAt: day.subtract(const Duration(days: 90)),
    ).toMap()..remove('id'),
  );
  for (final days in [-1, 7, 8]) {
    await db.insertProduct(
      Product(
        uuid: 'expiry-$days',
        name: 'Expiry $days',
        purchasePrice: 100,
        sellingPrice: 118,
        quantity: 2,
        purchaseExpiry: day.add(Duration(days: days)),
        purchaseBatchNo: 'BATCH-$days',
      ),
    );
  }
}
