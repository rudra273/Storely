import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import '../../models/bill.dart';
import '../../models/bill_settings.dart';
import '../../models/shop_profile.dart';
import '../../utils/upi.dart';

/// Thermal paper widths supported by the printer setup.
enum ReceiptPaper {
  mm58(PaperSize.mm58, 32),
  mm80(PaperSize.mm80, 48);

  final PaperSize size;

  /// Characters per line in the default font.
  final int columns;

  const ReceiptPaper(this.size, this.columns);
}

/// Builds ESC/POS bytes for a bill receipt in text mode.
///
/// Printer code pages are Latin-only, so text mode prints "Rs." for the
/// rupee sign; receipts with Hindi or other non-Latin text are printed as an
/// image instead (see [needsImageMode]).
class ReceiptBuilder {
  /// True when any text on the receipt can't be printed in a Latin code page.
  static bool needsImageMode(Bill bill, ShopProfile? shop) {
    final texts = [
      shop?.name,
      shop?.address,
      bill.customerName,
      for (final item in bill.items) item.productName,
    ];
    return texts.any((text) => text != null && text.runes.any((r) => r > 0xFF));
  }

  static List<int> build({
    required Bill bill,
    required ShopProfile? shop,
    required BillSettings settings,
    required ReceiptPaper paper,
    required CapabilityProfile profile,
  }) {
    if (bill.isCreditNote && bill.totalAmount < 0) bill = bill.negated();
    final gen = Generator(paper.size, profile);
    final bytes = <int>[...gen.reset()];
    String money(num v) => 'Rs.${v.toStringAsFixed(2)}';
    void kv(String label, String value, {bool bold = false}) {
      bytes.addAll(
        gen.row([
          PosColumn(
            text: label,
            width: 7,
            styles: PosStyles(bold: bold),
          ),
          PosColumn(
            text: value,
            width: 5,
            styles: PosStyles(align: PosAlign.right, bold: bold),
          ),
        ]),
      );
    }

    // Header
    bytes.addAll(
      gen.text(
        _latin(shop?.name ?? 'Storely'),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    );
    for (final line in [
      shop?.address,
      if ((shop?.phone ?? '').isNotEmpty) 'Ph: ${shop!.phone}',
      if ((shop?.gstin ?? '').isNotEmpty) 'GSTIN: ${shop!.gstin}',
    ]) {
      if (line == null || line.trim().isEmpty) continue;
      bytes.addAll(
        gen.text(_latin(line), styles: const PosStyles(align: PosAlign.center)),
      );
    }
    final hasGst = bill.cgstAmount + bill.sgstAmount + bill.igstAmount > 0.005;
    final title = bill.isCreditNote
        ? 'CREDIT NOTE'
        : settings.documentTitle(
            billHasGst: hasGst,
            gstScheme: shop?.gstScheme ?? GstScheme.unregistered,
          );
    bytes.addAll(gen.hr());
    bytes.addAll(
      gen.text(
        title,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(gen.text('No: ${bill.billNumber}'));
    if (bill.isCreditNote && bill.originalBillNumber != null) {
      bytes.addAll(gen.text('Against: ${bill.originalBillNumber}'));
    }
    bytes.addAll(
      gen.text(DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt)),
    );
    if (bill.customerName.trim().isNotEmpty) {
      bytes.addAll(gen.text('Customer: ${_latin(bill.customerName)}'));
    }
    bytes.addAll(gen.hr());

    // Items: name on its own line, then qty x rate and amount.
    for (final item in bill.items) {
      bytes.addAll(
        gen.text(_latin(item.productName), styles: const PosStyles(bold: true)),
      );
      final qty = item.quantity == item.quantity.roundToDouble()
          ? item.quantity.toStringAsFixed(0)
          : item.quantity.toStringAsFixed(3);
      bytes.addAll(
        gen.row([
          PosColumn(
            text:
                '  $qty ${item.unitLabel} x ${item.sellingPriceSnapshot.toStringAsFixed(2)}',
            width: 8,
          ),
          PosColumn(
            text: (hasGst ? item.lineAmount : item.subtotal).toStringAsFixed(2),
            width: 4,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]),
      );
    }
    bytes.addAll(gen.hr());

    // Totals
    if (hasGst) {
      kv('Taxable', money(bill.taxableAmount));
      if (bill.cgstAmount > 0) kv('CGST', money(bill.cgstAmount));
      if (bill.sgstAmount > 0) kv('SGST', money(bill.sgstAmount));
      if (bill.igstAmount > 0) kv('IGST', money(bill.igstAmount));
    } else {
      kv('Subtotal', money(bill.subtotalAmount));
    }
    if (bill.discountAmount > 0.005) {
      kv('Discount', '-${money(bill.discountAmount)}');
    }
    if (bill.roundOffAmount.abs() > 0.004) {
      kv('Round off', money(bill.roundOffAmount));
    }
    bytes.addAll(
      gen.row([
        PosColumn(
          text: 'TOTAL',
          width: 5,
          styles: const PosStyles(bold: true, height: PosTextSize.size2),
        ),
        PosColumn(
          text: money(bill.totalAmount),
          width: 7,
          styles: const PosStyles(
            bold: true,
            align: PosAlign.right,
            height: PosTextSize.size2,
          ),
        ),
      ]),
    );
    bytes.addAll(gen.text('Items: ${bill.items.length}'));

    // Payment
    if (bill.isCreditNote) {
      kv(
        bill.paymentMethod == 'credit_note' ? 'Adjusted' : 'Refunded',
        money(bill.paidAmount),
      );
    } else if (settings.showPaymentDetails) {
      kv('Paid', money(bill.paidAmount));
      if (bill.balanceDue > 0.005) {
        kv('Balance due', money(bill.balanceDue), bold: true);
      }
    }
    final upiId = settings.upiId.trim();
    if (!bill.isCreditNote &&
        settings.showUpiQr &&
        bill.balanceDue > 0.005 &&
        Upi.isValidId(upiId)) {
      bytes.addAll(gen.feed(1));
      bytes.addAll(
        gen.qrcode(
          Upi.paymentLink(
            upiId: upiId,
            payeeName: shop?.name ?? '',
            amount: bill.balanceDue,
            note: 'Bill ${bill.billNumber}',
            reference: bill.billNumber,
          ),
          size: paper == ReceiptPaper.mm58 ? QRSize.size5 : QRSize.size6,
        ),
      );
      bytes.addAll(
        gen.text(
          'Scan to pay ${money(bill.balanceDue)}',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
      bytes.addAll(
        gen.text(upiId, styles: const PosStyles(align: PosAlign.center)),
      );
    }

    // Footer
    final footer = [
      if (settings.showFooterText) settings.footerText.trim(),
      settings.termsText.trim(),
    ].where((t) => t.isNotEmpty);
    if (footer.isNotEmpty) bytes.addAll(gen.hr());
    for (final line in footer) {
      bytes.addAll(
        gen.text(_latin(line), styles: const PosStyles(align: PosAlign.center)),
      );
    }
    bytes.addAll(gen.feed(3));
    bytes.addAll(gen.cut());
    return bytes;
  }

  /// Text mode prints Latin only; anything else (e.g. ₹, Hindi) becomes a
  /// close ASCII stand-in or '?', which [needsImageMode] avoids for names.
  static String _latin(String text) => String.fromCharCodes(
    text.replaceAll('₹', 'Rs.').runes.map((r) => r > 0xFF ? 0x3F : r),
  );
}
