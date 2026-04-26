import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/utils/bill_pdf_generator.dart';

void main() {
  test('generates printable bill PDF bytes', () async {
    final bill = Bill(
      billNumber: 'SHOP-LOCAL-local-20260426-0001',
      customerName: 'Ravi Traders',
      customerPhone: '919876543210',
      subtotalAmount: 1180,
      totalAmount: 1180,
      itemCount: 2,
      paymentMethod: 'online',
      items: [
        BillItem(
          productName: 'Paint Bucket',
          unit: 'ltr',
          quantity: 2,
          sellingPriceSnapshot: 590,
          gstSnapshot: 90,
        ),
      ],
    );
    final shop = ShopProfile(
      name: 'Storely Hardware',
      gstin: '22AAAAA0000A1Z5',
      address: 'Main Road',
      gstRegistered: true,
    );

    final bytes = await BillPdfGenerator.generate(bill: bill, shop: shop);

    expect(bytes.length, greaterThan(1000));
    expect(BillPdfGenerator.filename(bill), contains('SHOP-LOCAL-local'));
  });
}
