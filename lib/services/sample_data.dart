import '../db/database_helper.dart';
import '../models/product.dart';

/// A handful of everyday kirana items so a new shop can try billing at
/// once. Normal products: edit or delete them like any other.
class SampleData {
  static final products = [
    Product(
      name: 'Rice (1 kg)',
      sellingPrice: 60,
      purchasePrice: 52,
      quantity: 25,
      unit: 'kg',
      hsnCode: '1006',
    ),
    Product(
      name: 'Toor Dal (1 kg)',
      sellingPrice: 140,
      purchasePrice: 120,
      quantity: 15,
      unit: 'kg',
      hsnCode: '0713',
    ),
    Product(
      name: 'Sugar (1 kg)',
      sellingPrice: 45,
      purchasePrice: 40,
      quantity: 20,
      unit: 'kg',
      hsnCode: '1701',
    ),
    Product(
      name: 'Tea (250 g)',
      sellingPrice: 110,
      purchasePrice: 92,
      quantity: 12,
      unit: 'pkt',
      hsnCode: '0902',
    ),
    Product(
      name: 'Biscuits',
      sellingPrice: 10,
      purchasePrice: 8,
      quantity: 48,
      unit: 'pcs',
      hsnCode: '1905',
    ),
    Product(
      name: 'Bath Soap',
      sellingPrice: 35,
      purchasePrice: 29,
      quantity: 24,
      unit: 'pcs',
      hsnCode: '3401',
    ),
  ];

  static Future<void> addProducts() async {
    final db = DatabaseHelper.instance;
    for (final product in products) {
      await db.insertProduct(
        product.copyWith(
          directPriceToggle: true,
          manualPrice: product.sellingPrice,
        ),
      );
    }
  }
}
