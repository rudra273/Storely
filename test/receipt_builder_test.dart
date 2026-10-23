import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/services/thermal/receipt_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CapabilityProfile profile;

  setUpAll(() async => profile = await CapabilityProfile.load());

  final shop = ShopProfile(
    name: 'Sharma Kirana',
    address: 'MG Road, Pune',
    gstin: '27AAAAA0000A1Z5',
    gstScheme: GstScheme.regular,
  );

  // A credit note is stored negative throughout, like the database writes it.
  Bill bill({double paid = 315, String doc = Bill.documentInvoice}) {
    final sign = doc == Bill.documentCreditNote ? -1.0 : 1.0;
    return Bill(
      billNumber: doc == Bill.documentCreditNote
          ? 'CN/2627/0001'
          : 'INV/2627/0007',
      customerName: 'Ravi',
      subtotalAmount: 315 * sign,
      taxableAmount: 300 * sign,
      cgstAmount: 7.5 * sign,
      sgstAmount: 7.5 * sign,
      totalAmount: 315 * sign,
      itemCount: 1,
      paidAmount: doc == Bill.documentCreditNote ? -315 : paid,
      documentType: doc,
      originalBillNumber: doc == Bill.documentCreditNote
          ? 'INV/2627/0007'
          : null,
      items: [
        BillItem(
          productName: 'Basmati Rice 5kg',
          sellingPriceSnapshot: 157.5,
          taxableValueSnapshot: 150,
          gstSnapshot: 7.5,
          cgstAmountSnapshot: 3.75,
          sgstAmountSnapshot: 3.75,
          gstPercentSnapshot: 5,
          quantity: doc == Bill.documentCreditNote ? -2 : 2,
        ),
      ],
    );
  }

  String text(List<int> bytes) => latin1.decode(bytes, allowInvalid: true);

  bool hasSequence(List<int> bytes, List<int> seq) {
    for (var i = 0; i + seq.length <= bytes.length; i++) {
      var ok = true;
      for (var j = 0; j < seq.length && ok; j++) {
        ok = bytes[i + j] == seq[j];
      }
      if (ok) return true;
    }
    return false;
  }

  List<int> build(
    Bill b, {
    ReceiptPaper paper = ReceiptPaper.mm58,
    String upi = '',
  }) => ReceiptBuilder.build(
    bill: b,
    shop: shop,
    settings: BillSettings(upiId: upi),
    paper: paper,
    profile: profile,
  );

  test('Hindi text switches to image mode', () {
    expect(ReceiptBuilder.needsImageMode(bill(), shop), isFalse);
    expect(
      ReceiptBuilder.needsImageMode(bill(), ShopProfile(name: 'शर्मा किराना')),
      isTrue,
    );
  });

  test('a paid GST bill prints header, items, totals and a cut', () {
    final bytes = build(bill());
    final out = text(bytes);
    expect(out, contains('Sharma Kirana'));
    expect(out, contains('GSTIN: 27AAAAA0000A1Z5'));
    expect(out, contains('TAX INVOICE'));
    expect(out, contains('INV/2627/0007'));
    expect(out, contains('Basmati Rice 5kg'));
    expect(out, contains('CGST'));
    expect(out, contains('Rs.315.00'));
    expect(out, isNot(contains('Scan to pay')));
    expect(hasSequence(bytes, [0x1D, 0x56]), isTrue, reason: 'paper cut');
  });

  test('money due prints a UPI QR for the balance', () {
    final bytes = build(bill(paid: 115), upi: 'sharmakirana@okicici');
    final out = text(bytes);
    expect(out, contains('Balance due'));
    expect(out, contains('Scan to pay Rs.200.00'));
    expect(out, contains('upi://pay?pa=sharmakirana%40okicici'));
    expect(hasSequence(bytes, [0x1D, 0x28, 0x6B]), isTrue, reason: 'QR');
  });

  test('a credit note prints as CREDIT NOTE with positive amounts', () {
    final out = text(build(bill(doc: Bill.documentCreditNote)));
    expect(out, contains('CREDIT NOTE'));
    expect(out, contains('Against: INV/2627/0007'));
    expect(out, contains('Rs.315.00'));
    expect(out, isNot(contains('Rs.-')), reason: _lines(out, 'Rs.-'));
  });

  test('58 mm and 80 mm layouts differ', () {
    expect(
      build(bill(), paper: ReceiptPaper.mm80),
      isNot(equals(build(bill()))),
    );
  });
}

String _lines(String out, String needle) =>
    out.split('\n').where((l) => l.contains(needle)).join(' | ');
