import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/utils/bill_pdf_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('generates bill PDF with optional sections hidden', () async {
    final bill = Bill(
      billNumber: 'INV-20260603-0001',
      customerName: 'Ravi Traders',
      customerPhone: '919876543210',
      billType: Bill.typeB2b,
      customerGstin: '27AAAAA0000A1Z5',
      customerAddressSnapshot: 'Industrial Estate',
      placeOfSupplyStateCode: '27',
      subtotalAmount: 1180,
      taxableAmount: 1000,
      cgstAmount: 90,
      sgstAmount: 90,
      totalAmount: 1180,
      itemCount: 1,
      items: [
        BillItem(
          productName: 'Paint Bucket',
          hsnCodeSnapshot: '3208',
          quantity: 1,
          sellingPriceSnapshot: 1180,
          taxableValueSnapshot: 1000,
          gstPercentSnapshot: 18,
          gstSnapshot: 180,
        ),
      ],
    );
    final shop = ShopProfile(
      name: 'Storely Hardware',
      gstin: '27BBBBB0000B1Z5',
      gstRegistered: true,
    );
    final settings = BillSettings(
      showInvoiceTitle: false,
      showShopName: false,
      showCustomerPhone: false,
      showInvoiceSupplyType: false,
      showItemSerialColumn: false,
      showHsnColumn: false,
      showGstPercentColumn: false,
      showFooterText: false,
    );

    final bytes = await BillPdfGenerator.generate(
      bill: bill,
      shop: shop,
      settings: settings,
    );

    expect(bytes.length, greaterThan(1000));
  });
}
