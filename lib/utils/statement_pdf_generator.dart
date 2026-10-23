import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/bill.dart';
import '../models/bill_settings.dart';
import '../models/shop_profile.dart';
import 'money.dart';
import 'pdf_theme.dart';
import 'upi.dart';

/// A customer's account statement: every bill with amount, paid and
/// balance, the total due, and a UPI QR to pay it.
class StatementPdfGenerator {
  static Future<Uint8List> generate({
    required String customerName,
    required String? customerPhone,
    required List<Bill> bills,
    required ShopProfile? shop,
    required BillSettings settings,
    DateTime? now,
  }) async {
    final sorted = [...bills]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final billed = sorted.fold<double>(0, (sum, b) => sum + b.totalAmount);
    final paid = sorted.fold<double>(0, (sum, b) => sum + b.paidAmount);
    final due = sorted.fold<double>(0, (sum, b) => sum + b.balanceDue);
    final date = DateFormat('dd MMM yyyy');
    final upiId = settings.upiId.trim();
    final showQr = settings.showUpiQr && due > 0.005 && Upi.isValidId(upiId);

    final pdf = pw.Document(
      title: 'Statement - $customerName',
      author: shop?.name ?? 'Storely',
      theme: await storelyPdfTheme(),
    );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            shop?.name ?? 'Storely',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          if ((shop?.address ?? '').isNotEmpty)
            pw.Text(shop!.address!, style: const pw.TextStyle(fontSize: 9)),
          if ((shop?.phone ?? '').isNotEmpty)
            pw.Text(
              'Phone: ${shop!.phone}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          if ((shop?.gstin ?? '').isNotEmpty)
            pw.Text(
              'GSTIN: ${shop!.gstin}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          pw.Divider(color: PdfColors.grey500),
          pw.Text(
            'ACCOUNT STATEMENT',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            customerName,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          if ((customerPhone ?? '').isNotEmpty)
            pw.Text(
              'Phone: $customerPhone',
              style: const pw.TextStyle(fontSize: 9),
            ),
          pw.Text(
            sorted.isEmpty
                ? 'As of ${date.format(now ?? DateTime.now())}'
                : '${date.format(sorted.first.createdAt)} to '
                      '${date.format(now ?? DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Bill No', 'Amount', 'Paid', 'Balance'],
            data: [
              for (final bill in sorted)
                [
                  date.format(bill.createdAt),
                  bill.billNumber,
                  rupees(bill.totalAmount),
                  rupees(bill.paidAmount),
                  rupees(bill.balanceDue),
                ],
            ],
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignment: pw.Alignment.centerRight,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
            },
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5,
              vertical: 5,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: showQr
                    ? pw.Row(
                        children: [
                          pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: Upi.paymentLink(
                              upiId: upiId,
                              payeeName: shop?.name ?? '',
                              amount: due,
                              note: 'Dues - $customerName',
                            ),
                            width: 80,
                            height: 80,
                          ),
                          pw.SizedBox(width: 8),
                          pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'Scan to pay ${rupees(due)}',
                                style: pw.TextStyle(
                                  fontSize: 9,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                              pw.Text(
                                upiId,
                                style: const pw.TextStyle(fontSize: 8),
                              ),
                            ],
                          ),
                        ],
                      )
                    : pw.SizedBox(),
              ),
              pw.SizedBox(
                width: 220,
                child: pw.Column(
                  children: [
                    _row('Total billed', billed),
                    _row('Total paid', paid),
                    pw.Divider(),
                    _row('Amount due', due, bold: true),
                  ],
                ),
              ),
            ],
          ),
          if (due > 0.005) ...[
            pw.SizedBox(height: 6),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                amountInWords(due),
                style: const pw.TextStyle(
                  fontSize: 8.5,
                  color: PdfColors.grey800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _row(String label, double value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: bold ? 12 : 9.5,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.Text(rupees(value), style: style),
        ],
      ),
    );
  }
}
