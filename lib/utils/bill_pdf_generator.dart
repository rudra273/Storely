import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/bill.dart';
import '../models/bill_settings.dart';
import '../models/shop_profile.dart';

class BillPdfGenerator {
  static Future<Uint8List> generate({
    required Bill bill,
    required ShopProfile? shop,
    BillSettings? settings,
  }) async {
    final billSettings = settings ?? BillSettings();
    WidgetsFlutterBinding.ensureInitialized();
    final fontData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final boldFontData = await rootBundle.load(
      'assets/fonts/NotoSans-Bold.ttf',
    );
    final pdf = pw.Document(
      title: _billTitle(bill),
      author: shop?.name ?? 'Storely',
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(fontData),
        bold: pw.Font.ttf(boldFontData),
      ),
    );
    final gstRegistered = shop?.gstRegistered ?? false;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _header(bill, shop, billSettings),
          pw.SizedBox(height: 14),
          _partyBlock(bill, shop, billSettings),
          pw.SizedBox(height: 18),
          _itemsTable(
            bill,
            gstRegistered: gstRegistered,
            settings: billSettings,
          ),
          pw.SizedBox(height: 14),
          _totals(bill, gstRegistered: gstRegistered, settings: billSettings),
          pw.SizedBox(height: 20),
          _footer(gstRegistered, billSettings),
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

  static pw.Widget _header(
    Bill bill,
    ShopProfile? shop,
    BillSettings settings,
  ) {
    final logo = settings.showShopLogo
        ? _imageProvider(settings.shopLogoBase64)
        : null;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logo != null) ...[
          pw.Container(
            width: 58,
            height: 58,
            margin: const pw.EdgeInsets.only(right: 12),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
        ],
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
              if (settings.showShopAddress && shop?.address != null)
                _muted(shop!.address!),
              if (settings.showShopPhone && shop?.phone != null)
                _muted('Phone: ${shop!.phone}'),
              if (settings.showShopEmail && shop?.email != null)
                _muted('Email: ${shop!.email}'),
              if (settings.showShopGstin && shop?.gstin != null)
                _muted('GSTIN: ${shop!.gstin}'),
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
                settings.invoiceTitle.trim().isEmpty
                    ? BillSettings.defaultInvoiceTitle
                    : settings.invoiceTitle.trim().toUpperCase(),
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

  static pw.Widget _partyBlock(
    Bill bill,
    ShopProfile? shop,
    BillSettings settings,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _infoBox(
            title: 'Bill To',
            lines: [
              bill.customerName,
              if (bill.customerGstin != null) 'GSTIN: ${bill.customerGstin}',
              if (bill.customerGstLegalName != null)
                'Legal Name: ${bill.customerGstLegalName}',
              if (bill.customerGstTradeName != null)
                'Trade Name: ${bill.customerGstTradeName}',
              if (settings.showCustomerPhone && bill.customerPhone != null)
                'Phone: ${bill.customerPhone}',
              if (settings.showCustomerAddress &&
                  bill.customerAddressSnapshot != null)
                bill.customerAddressSnapshot!,
            ],
          ),
        ),
        if (settings.showPaymentDetails) ...[
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: _infoBox(
              title: 'Payment',
              lines: [
                'Status: ${_paymentStatusLabel(bill.paymentStatus)}',
                if (bill.paidAmount > 0)
                  'Method: ${bill.paymentMethod == 'online' ? 'Online' : 'Cash'}',
                if (bill.paidAmount > 0) 'Paid: ${_money(bill.paidAmount)}',
                if (bill.balanceDue > 0) 'Balance: ${_money(bill.balanceDue)}',
                if (shop?.gstRegistered == true) 'GST: Registered',
                if (shop?.gstRegistered != true) 'GST: Not registered',
              ],
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _itemsTable(
    Bill bill, {
    required bool gstRegistered,
    required BillSettings settings,
  }) {
    final showGst = gstRegistered && settings.showGstBreakdown;
    final showHsn =
        settings.showHsnColumn &&
        (gstRegistered ||
            bill.items.any((item) => item.hsnCodeSnapshot != null));
    final headers = [
      '#',
      'Item',
      if (showHsn) 'HSN',
      'Rate',
      'Qty',
      if (showGst) 'Net Amount',
      if (showGst) 'GST',
      'Amount',
    ];

    final data = bill.items.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final item = entry.value;
      final gst = showGst ? item.totalGst : 0.0;
      final taxable = showGst ? item.totalTaxableValue : item.subtotal;
      return [
        '$index',
        item.productName,
        if (showHsn) item.hsnCodeSnapshot ?? '-',
        _money(item.sellingPriceSnapshot),
        item.quantityLabel,
        if (showGst) _money(taxable),
        if (showGst) _money(gst),
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
        for (var i = 2; i < headers.length; i++) i: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FlexColumnWidth(2.4),
        2: const pw.FlexColumnWidth(0.9),
        3: const pw.FlexColumnWidth(0.9),
        if (showGst) 4: const pw.FlexColumnWidth(1),
        if (showGst) 5: const pw.FlexColumnWidth(0.9),
        if (showGst) 6: const pw.FlexColumnWidth(1),
        if (!showGst) 4: const pw.FlexColumnWidth(1),
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
    );
  }

  static pw.Widget _totals(
    Bill bill, {
    required bool gstRegistered,
    required BillSettings settings,
  }) {
    final showGst = gstRegistered && settings.showGstBreakdown;
    final gstTotal = showGst
        ? bill.cgstAmount + bill.sgstAmount + bill.igstAmount
        : 0.0;
    final taxableTotal = showGst ? bill.taxableAmount : bill.subtotalAmount;

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 240,
        child: pw.Column(
          children: [
            if (showGst) _totalRow('Net Amount', taxableTotal),
            if (showGst) _totalRow('GST total', gstTotal),
            _totalRow('Subtotal', bill.subtotalAmount),
            if (bill.discountAmount > 0)
              _totalRow(
                'Discount (${bill.discountPercent.toStringAsFixed(2)}%)',
                -bill.discountAmount,
              ),
            pw.Divider(),
            _totalRow('Grand total', bill.totalAmount, bold: true),
            if (settings.showPaymentDetails) ...[
              if (bill.paidAmount > 0) _totalRow('Paid', bill.paidAmount),
              if (bill.balanceDue > 0)
                _totalRow('Balance due', bill.balanceDue, bold: true),
            ],
          ],
        ),
      ),
    );
  }

  static pw.Widget _footer(bool gstRegistered, BillSettings settings) {
    final signature = settings.showDigitalSignature
        ? _imageProvider(settings.digitalSignatureBase64)
        : null;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey400),
        if (settings.showGstBreakdown)
          pw.Text(
            gstRegistered
                ? 'GST shown above is calculated from item price snapshots at billing time.'
                : 'This shop is not marked GST registered; GST is not shown as collected on this invoice.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        if (settings.footerText.trim().isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            settings.footerText.trim(),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          ),
        ],
        if (signature != null) ...[
          pw.SizedBox(height: 18),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              children: [
                pw.SizedBox(
                  width: 120,
                  height: 48,
                  child: pw.Image(signature, fit: pw.BoxFit.contain),
                ),
                pw.Container(width: 120, height: 0.5, color: PdfColors.grey600),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Authorised signature',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
        ],
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
    if (bill.billNumber.startsWith('SHOP-LOCAL-')) {
      return 'Bill #${bill.id ?? ''}';
    }
    return bill.billNumber.isNotEmpty
        ? bill.billNumber
        : 'Bill #${bill.id ?? ''}';
  }

  static String _money(double value) {
    final sign = value < 0 ? '-' : '';
    return '${sign}Rs. ${value.abs().toStringAsFixed(2)}';
  }

  static String _paymentStatusLabel(String status) {
    return switch (status) {
      Bill.statusPaid => 'Paid',
      Bill.statusPartial => 'Partial',
      _ => 'Unpaid',
    };
  }

  static pw.MemoryImage? _imageProvider(String? base64Value) {
    final value = base64Value?.trim();
    if (value == null || value.isEmpty) return null;
    try {
      return pw.MemoryImage(base64Decode(value));
    } catch (_) {
      return null;
    }
  }
}
