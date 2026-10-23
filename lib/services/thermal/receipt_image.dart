import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/bill.dart';
import '../../models/bill_settings.dart';
import '../../models/shop_profile.dart';
import '../../utils/money.dart';
import '../../utils/pdf_theme.dart';
import '../../utils/upi.dart';
import 'receipt_builder.dart';

/// Image-mode receipt for text a printer's Latin code page can't print
/// (Hindi, ₹): laid out as a receipt-width PDF with the bundled fonts,
/// rasterised at the printer's 203 dpi and sent as an ESC/POS image.
class ReceiptImage {
  /// Printable dots per line at 203 dpi.
  static int dots(ReceiptPaper paper) => paper == ReceiptPaper.mm58 ? 384 : 576;

  static Future<List<int>> build({
    required Bill bill,
    required ShopProfile? shop,
    required BillSettings settings,
    required ReceiptPaper paper,
    required CapabilityProfile profile,
  }) async {
    final pdfBytes = await receiptPdf(
      bill: bill,
      shop: shop,
      settings: settings,
      paper: paper,
    );
    final page = await Printing.raster(pdfBytes, dpi: 203).first;
    final png = await page.toPng();
    var image = img.decodePng(png)!;
    if (image.width != dots(paper)) {
      image = img.copyResize(image, width: dots(paper));
    }
    final gen = Generator(paper.size, profile);
    return [
      ...gen.reset(),
      ...gen.imageRaster(image),
      ...gen.feed(3),
      ...gen.cut(),
    ];
  }

  /// The receipt as a narrow PDF page (also usable for a preview).
  static Future<Uint8List> receiptPdf({
    required Bill bill,
    required ShopProfile? shop,
    required BillSettings settings,
    required ReceiptPaper paper,
  }) async {
    if (bill.isCreditNote && bill.totalAmount < 0) bill = bill.negated();
    final widthMm = paper == ReceiptPaper.mm58 ? 48.0 : 72.0;
    final format = PdfPageFormat(
      widthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 1.5 * PdfPageFormat.mm,
    );
    final small = paper == ReceiptPaper.mm58 ? 7.5 : 9.0;
    pw.TextStyle style({bool bold = false, double? size}) => pw.TextStyle(
      fontSize: size ?? small,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    pw.Widget row(String l, String r, {bool bold = false}) => pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(l, style: style(bold: bold)),
        ),
        pw.Text(r, style: style(bold: bold)),
      ],
    );
    final hasGst = bill.cgstAmount + bill.sgstAmount + bill.igstAmount > 0.005;
    final title = bill.isCreditNote
        ? 'CREDIT NOTE'
        : settings.documentTitle(
            billHasGst: hasGst,
            gstScheme: shop?.gstScheme ?? GstScheme.unregistered,
          );
    final upiId = settings.upiId.trim();
    final showQr =
        !bill.isCreditNote &&
        settings.showUpiQr &&
        bill.balanceDue > 0.005 &&
        Upi.isValidId(upiId);

    final doc = pw.Document(theme: await storelyPdfTheme());
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              shop?.name ?? 'Storely',
              textAlign: pw.TextAlign.center,
              style: style(bold: true, size: small * 1.5),
            ),
            for (final line in [
              shop?.address,
              if ((shop?.phone ?? '').isNotEmpty) 'Ph: ${shop!.phone}',
              if ((shop?.gstin ?? '').isNotEmpty) 'GSTIN: ${shop!.gstin}',
            ])
              if (line != null && line.trim().isNotEmpty)
                pw.Text(line, textAlign: pw.TextAlign.center, style: style()),
            pw.Divider(height: 6),
            pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: style(bold: true),
            ),
            pw.Text('No: ${bill.billNumber}', style: style()),
            if (bill.isCreditNote && bill.originalBillNumber != null)
              pw.Text('Against: ${bill.originalBillNumber}', style: style()),
            pw.Text(
              DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt),
              style: style(),
            ),
            pw.Text('Customer: ${bill.customerName}', style: style()),
            pw.Divider(height: 6),
            for (final item in bill.items) ...[
              pw.Text(item.productName, style: style(bold: true)),
              row(
                '  ${_qty(item.quantity)} ${item.unitLabel} x '
                '${rupees(item.sellingPriceSnapshot)}',
                rupees(hasGst ? item.lineAmount : item.subtotal),
              ),
            ],
            pw.Divider(height: 6),
            if (hasGst) ...[
              row('Taxable', rupees(bill.taxableAmount)),
              if (bill.cgstAmount > 0) row('CGST', rupees(bill.cgstAmount)),
              if (bill.sgstAmount > 0) row('SGST', rupees(bill.sgstAmount)),
              if (bill.igstAmount > 0) row('IGST', rupees(bill.igstAmount)),
            ] else
              row('Subtotal', rupees(bill.subtotalAmount)),
            if (bill.discountAmount > 0.005)
              row('Discount', '-${rupees(bill.discountAmount)}'),
            if (bill.roundOffAmount.abs() > 0.004)
              row('Round off', signedRupees(bill.roundOffAmount)),
            pw.SizedBox(height: 2),
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'TOTAL',
                    style: style(bold: true, size: small * 1.4),
                  ),
                ),
                pw.Text(
                  rupees(bill.totalAmount),
                  style: style(bold: true, size: small * 1.4),
                ),
              ],
            ),
            if (!bill.isCreditNote &&
                bill.items.any((item) => item.mrpSaving > 0))
              pw.Text(
                'You saved ${rupees(bill.items.fold<double>(0, (s, i) => s + i.mrpSaving))} on MRP',
                textAlign: pw.TextAlign.center,
                style: style(bold: true),
              ),
            if (bill.isCreditNote)
              row(
                bill.paymentMethod == 'credit_note' ? 'Adjusted' : 'Refunded',
                rupees(bill.paidAmount),
              )
            else if (settings.showPaymentDetails) ...[
              row('Paid', rupees(bill.paidAmount)),
              if (bill.balanceDue > 0.005)
                row('Balance due', rupees(bill.balanceDue), bold: true),
            ],
            if (showQr) ...[
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: Upi.paymentLink(
                    upiId: upiId,
                    payeeName: shop?.name ?? '',
                    amount: bill.balanceDue,
                    note: 'Bill ${bill.billNumber}',
                    reference: bill.billNumber,
                  ),
                  width: widthMm * 0.55 * PdfPageFormat.mm,
                  height: widthMm * 0.55 * PdfPageFormat.mm,
                ),
              ),
              pw.Text(
                'Scan to pay ${rupees(bill.balanceDue)}',
                textAlign: pw.TextAlign.center,
                style: style(bold: true),
              ),
            ],
            if (settings.showFooterText &&
                settings.footerText.trim().isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  settings.footerText.trim(),
                  textAlign: pw.TextAlign.center,
                  style: style(),
                ),
              ),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(3);
}
