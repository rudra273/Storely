import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/services/bill_share.dart';
import 'package:storely/services/thermal/receipt_builder.dart';
import 'package:storely/utils/bill_pdf_generator.dart';

Bill _sampleBill({
  String lifecycleStatus = Bill.lifecycleFinalized,
  String? cancelReason,
  String discountMode = Bill.discountModeAmount,
  double discountValue = 10.0,
  double discountAmount = 10.0,
  String taxMode = Bill.taxModeExclusive,
  String? notes = 'Deliver before 6 PM',
}) {
  return Bill(
    id: 1,
    billNumber: 'INV/2627/0101',
    customerName: 'Acme Retail',
    customerPhone: '9876543210',
    subtotalAmount: 210.0,
    discountPercent: discountMode == Bill.discountModePercent ? discountValue : 0,
    discountMode: discountMode,
    discountValue: discountValue,
    discountAmount: discountAmount,
    taxMode: taxMode,
    taxableAmount: 200.0,
    cgstAmount: 18.0,
    sgstAmount: 18.0,
    igstAmount: 0.0,
    roundOffAmount: 0.0,
    totalAmount: 236.0,
    paidAmount: 100.0,
    paymentMethod: 'upi',
    itemCount: 1,
    lifecycleStatus: lifecycleStatus,
    cancelReason: cancelReason,
    notes: notes,
    createdAt: DateTime(2026, 11, 27, 11, 30),
    items: [
      BillItem(
        productId: 1,
        productName: 'Organic Tea 500g',
        quantity: 2,
        unit: 'pkt',
        sellingPriceSnapshot: 120.0,
        purchasePriceSnapshot: 80.0,
        discountMode: Bill.discountModePercent,
        discountValue: 10,
        discountAmount: 24.0,
        gstPercentSnapshot: 18,
        taxableValueSnapshot: 100.0,
        gstSnapshot: 18.0,
      ),
    ],
  );
}

ShopProfile _sampleShop() => ShopProfile(
  name: 'Storely Mart',
  address: 'FC Road, Pune',
  phone: '9999999999',
  gstin: '27AABCU9603R1ZM',
  gstScheme: GstScheme.regular,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('E12.1-E12.2 invoice output parity', () {
    test('BillSettings supports A4, A5, 80mm, and 58mm paper sizes', () {
      for (final size in [
        BillSettings.paperA4,
        BillSettings.paperA5,
        BillSettings.paper80mm,
        BillSettings.paper58mm,
      ]) {
        final settings = BillSettings.fromMap({'paper_size': size});
        expect(settings.paperSize, size);
        expect(settings.toMap()['paper_size'], size);
      }
    });

    test('BillPdfGenerator produces valid PDF bytes for A4, A5, 80mm, 58mm and VOID bills', () async {
      final bill = _sampleBill();
      final voidBill = _sampleBill(
        lifecycleStatus: Bill.lifecycleCancelled,
        cancelReason: 'Duplicate bill',
      );
      final shop = _sampleShop();

      for (final paper in [
        BillSettings.paperA4,
        BillSettings.paperA5,
        BillSettings.paper80mm,
        BillSettings.paper58mm,
      ]) {
        final bytes = await BillPdfGenerator.generate(
          bill: bill,
          shop: shop,
          settings: BillSettings(paperSize: paper, termsText: 'No returns'),
        );
        expect(bytes.length, greaterThan(500));
        expect(utf8.decode(bytes.sublist(0, 5)), '%PDF-');

        final voidBytes = await BillPdfGenerator.generate(
          bill: voidBill,
          shop: shop,
          settings: BillSettings(paperSize: paper),
        );
        expect(voidBytes.length, greaterThan(500));
        expect(utf8.decode(voidBytes.sublist(0, 5)), '%PDF-');
      }
    });

    test('ReceiptBuilder emits line discounts, fixed-Rs doc discount, notes, and VOID without balance due', () async {
      final profile = await CapabilityProfile.load();
      final settings = BillSettings(
        upiId: 'storely@upi',
        termsText: 'Goods once sold will not be returned.',
      );

      final liveBytes = ReceiptBuilder.build(
        bill: _sampleBill(),
        shop: _sampleShop(),
        settings: settings,
        paper: ReceiptPaper.mm80,
        profile: profile,
      );
      final liveText = latin1.decode(liveBytes, allowInvalid: true);
      expect(liveText, contains('Prices excl. GST'));
      expect(liveText, contains('Disc: Rs.24.00'));
      expect(liveText, contains('Disc (Rs.10.00 off)'));
      expect(liveText, contains('Balance due'));
      expect(liveText, contains('Notes: Deliver before 6 PM'));

      final voidBytes = ReceiptBuilder.build(
        bill: _sampleBill(
          lifecycleStatus: Bill.lifecycleCancelled,
          cancelReason: 'Wrong party',
        ),
        shop: _sampleShop(),
        settings: settings,
        paper: ReceiptPaper.mm58,
        profile: profile,
      );
      final voidText = latin1.decode(voidBytes, allowInvalid: true);
      expect(voidText, contains('VOID: Wrong party'));
      expect(voidText, isNot(contains('Balance due')));
      expect(voidText, isNot(contains('Scan to pay')));
    });

    test('ReceiptBuilder.needsImageMode inspects bill notes, footer, and terms', () {
      final base = _sampleBill(notes: 'Plain ASCII note');
      final shop = _sampleShop();
      expect(
        ReceiptBuilder.needsImageMode(base, shop, BillSettings()),
        isFalse,
      );
      expect(
        ReceiptBuilder.needsImageMode(
          _sampleBill(notes: 'शाम 6 बजे से पहले'),
          shop,
          BillSettings(),
        ),
        isTrue,
      );
      expect(
        ReceiptBuilder.needsImageMode(
          base,
          shop,
          BillSettings(termsText: 'धन्यवाद'),
        ),
        isTrue,
      );
    });

    test('BillShare.buildWhatsAppMessage formats line discounts, fixed doc discount, notes, and VOID', () {
      final msg = BillShare.buildWhatsAppMessage(_sampleBill(), _sampleShop());
      expect(msg, contains('Disc: ₹24.00'));
      expect(msg, contains('Discount (₹10.00 off): -₹10.00'));
      expect(msg, contains('Notes: Deliver before 6 PM'));

      final voidMsg = BillShare.buildWhatsAppMessage(
        _sampleBill(
          lifecycleStatus: Bill.lifecycleCancelled,
          cancelReason: 'Duplicate',
        ),
        _sampleShop(),
      );
      expect(voidMsg, contains('VOID INV/2627/0101 (Duplicate)'));
      expect(voidMsg, contains('Status: Voided'));
      expect(voidMsg, isNot(contains('Balance:')));
    });
  });
}
