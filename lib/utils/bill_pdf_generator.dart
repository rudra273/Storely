import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/bill.dart';
import '../models/shop_profile.dart';

class BillPdfGenerator {
  static Future<Uint8List> generate({
    required Bill bill,
    required ShopProfile? shop,
  }) {
    final pdf = pw.Document(
      title: _billTitle(bill),
      author: shop?.name ?? 'Storely',
    );
    final gstRegistered = shop?.gstRegistered ?? false;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _header(bill, shop),
          pw.SizedBox(height: 14),
          _partyBlock(bill, shop),
          pw.SizedBox(height: 18),
          _itemsTable(bill, gstRegistered: gstRegistered),
          pw.SizedBox(height: 14),
          _totals(bill, gstRegistered: gstRegistered),
          pw.SizedBox(height: 20),
          _footer(gstRegistered),
        ],
      ),
    );

    return pdf.save();
  }

  static String filename(Bill bill) {
    final id = bill.billNumber.isNotEmpty ? bill.billNumber : 'bill-${bill.id}';
    final safe = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-');
    return '$safe.pdf';
  }

  static pw.Widget _header(Bill bill, ShopProfile? shop) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                shop?.name ?? 'Storely',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (shop?.address != null) _muted(shop!.address!),
              if (shop?.phone != null) _muted('Phone: ${shop!.phone}'),
              if (shop?.email != null) _muted('Email: ${shop!.email}'),
              if (shop?.gstin != null) _muted('GSTIN: ${shop!.gstin}'),
            ],
          ),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'TAX INVOICE',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(_billTitle(bill)),
              pw.Text(
                DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _partyBlock(Bill bill, ShopProfile? shop) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _infoBox(
            title: 'Bill To',
            lines: [
              bill.customerName,
              if (bill.customerPhone != null) 'Phone: ${bill.customerPhone}',
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: _infoBox(
            title: 'Payment',
            lines: [
              bill.isPaid ? 'Status: Paid' : 'Status: Unpaid',
              'Method: ${bill.paymentMethod == 'online' ? 'Online' : 'Cash'}',
              if (shop?.gstRegistered == true) 'GST: Registered',
              if (shop?.gstRegistered != true) 'GST: Not registered',
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _itemsTable(Bill bill, {required bool gstRegistered}) {
    final headers = [
      '#',
      'Item',
      'Qty',
      'Rate',
      if (gstRegistered) 'Taxable',
      if (gstRegistered) 'GST',
      'Amount',
    ];

    final data = bill.items.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final item = entry.value;
      final gst = gstRegistered ? item.totalGst : 0.0;
      final taxable = (item.subtotal - gst)
          .clamp(0, double.infinity)
          .toDouble();
      return [
        '$index',
        item.productName,
        item.quantityLabel,
        _money(item.sellingPriceSnapshot),
        if (gstRegistered) _money(taxable),
        if (gstRegistered) _money(gst),
        _money(item.subtotal),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellAlignment: pw.Alignment.centerLeft,
      headerAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        0: pw.Alignment.center,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        if (gstRegistered) 4: pw.Alignment.centerRight,
        if (gstRegistered) 5: pw.Alignment.centerRight,
        if (gstRegistered) 6: pw.Alignment.centerRight,
        if (!gstRegistered) 4: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FlexColumnWidth(2.4),
        2: const pw.FlexColumnWidth(0.9),
        3: const pw.FlexColumnWidth(0.9),
        if (gstRegistered) 4: const pw.FlexColumnWidth(1),
        if (gstRegistered) 5: const pw.FlexColumnWidth(0.9),
        if (gstRegistered) 6: const pw.FlexColumnWidth(1),
        if (!gstRegistered) 4: const pw.FlexColumnWidth(1),
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
    );
  }

  static pw.Widget _totals(Bill bill, {required bool gstRegistered}) {
    final gstTotal = gstRegistered
        ? bill.items.fold(0.0, (sum, item) => sum + item.totalGst)
        : 0.0;
    final taxableTotal = (bill.subtotalAmount - gstTotal)
        .clamp(0, double.infinity)
        .toDouble();

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 240,
        child: pw.Column(
          children: [
            if (gstRegistered) _totalRow('Taxable value', taxableTotal),
            if (gstRegistered) _totalRow('GST total', gstTotal),
            _totalRow('Subtotal', bill.subtotalAmount),
            if (bill.discountAmount > 0)
              _totalRow(
                'Discount (${bill.discountPercent.toStringAsFixed(2)}%)',
                -bill.discountAmount,
              ),
            pw.Divider(),
            _totalRow('Grand total', bill.totalAmount, bold: true),
          ],
        ),
      ),
    );
  }

  static pw.Widget _footer(bool gstRegistered) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.Text(
          gstRegistered
              ? 'GST shown above is calculated from item price snapshots at billing time.'
              : 'This shop is not marked GST registered; GST is not shown as collected on this invoice.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Thank you for your business.',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        ),
      ],
    );
  }

  static pw.Widget _infoBox({
    required String title,
    required List<String> lines,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
          pw.SizedBox(height: 5),
          ...lines.map(
            (line) => pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _totalRow(String label, double value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: bold ? 12 : 9,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.Text(_money(value), style: style),
        ],
      ),
    );
  }

  static pw.Widget _muted(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 2),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    );
  }

  static String _billTitle(Bill bill) {
    return bill.billNumber.isNotEmpty ? bill.billNumber : 'Bill #${bill.id}';
  }

  static String _money(double value) {
    final sign = value < 0 ? '-' : '';
    return '${sign}Rs. ${value.abs().toStringAsFixed(2)}';
  }
}
