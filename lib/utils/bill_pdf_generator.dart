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
    // GST visibility is driven by the bill's own data, not the shop's current
    // GST-registration flag. A bill that actually carries GST amounts should
    // always be able to show them when the template toggles ask for it, so the
    // shared PDF matches the live preview in Bill Settings.
    final billHasGst = _billHasGst(bill);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          _header(bill, shop, billSettings),
          if (_showHeader(billSettings)) pw.SizedBox(height: 10),
          _partyBlock(bill, shop, billSettings),
          pw.SizedBox(height: 10),
          _invoiceMeta(bill, shop, billSettings),
          pw.SizedBox(height: 16),
          _itemsTable(
            bill,
            gstRegistered: billHasGst,
            settings: billSettings,
          ),
          pw.SizedBox(height: 14),
          _totals(bill, gstRegistered: billHasGst, settings: billSettings),
          pw.SizedBox(height: 20),
          _footer(billSettings),
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
    if (!_showHeader(settings)) return pw.SizedBox();
    final title = settings.invoiceTitle.trim().isEmpty
        ? BillSettings.defaultInvoiceTitle
        : settings.invoiceTitle.trim().toUpperCase();
    final logo = settings.showShopLogo
        ? _imageProvider(settings.shopLogoBase64)
        : null;
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey500)),
      ),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 64,
            child: logo == null
                ? pw.SizedBox()
                : pw.SizedBox(
                    width: 48,
                    height: 48,
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
          ),
          pw.Expanded(
            child: settings.showInvoiceTitle
                ? pw.Text(
                    title,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  )
                : pw.SizedBox(),
          ),
          pw.SizedBox(width: 64),
        ],
      ),
    );
  }

  /// True when the bill carries any GST amounts. Used to decide whether GST
  /// columns/rows can appear, independent of the shop's current registration
  /// flag — so historical GST bills always render their tax breakdown.
  static bool _billHasGst(Bill bill) {
    if (bill.cgstAmount > 0 || bill.sgstAmount > 0 || bill.igstAmount > 0) {
      return true;
    }
    return bill.items.any((item) => item.totalGst > 0);
  }

  static bool _showHeader(BillSettings settings) {
    return settings.showInvoiceTitle ||
        (settings.showShopLogo &&
            _imageProvider(settings.shopLogoBase64) != null);
  }

  static pw.Widget _partyBlock(
    Bill bill,
    ShopProfile? shop,
    BillSettings settings,
  ) {
    final sellerLines = _sellerLines(shop, settings);
    final buyerLines = _buyerLines(bill, settings);
    final showSeller = sellerLines.any((line) => line.trim().isNotEmpty);
    final showBuyer = buyerLines.any((line) => line.trim().isNotEmpty);
    if (!showSeller && !showBuyer) return pw.SizedBox();

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (showSeller)
          pw.Expanded(
            child: _infoBox(title: 'Seller / From', lines: sellerLines),
          ),
        if (showSeller && showBuyer) pw.SizedBox(width: 10),
        if (showBuyer)
          pw.Expanded(
            child: _infoBox(title: 'Buyer / Bill To', lines: buyerLines),
          ),
      ],
    );
  }

  static pw.Widget _invoiceMeta(
    Bill bill,
    ShopProfile? shop,
    BillSettings settings,
  ) {
    final supplyState = _cleanStateCode(
      bill.placeOfSupplyStateCode ?? bill.customerGstin,
    );
    final shopState = _cleanStateCode(shop?.gstin);
    final supplyType = shopState == null || supplyState == null
        ? null
        : shopState == supplyState
        ? 'Intrastate'
        : 'Interstate';

    final cells = [
      if (settings.showInvoiceNumber) _metaCell('Invoice No', _billTitle(bill)),
      if (settings.showInvoiceDate)
        _metaCell(
          'Date',
          DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt),
        ),
      if (settings.showInvoicePlaceOfSupply)
        _metaCell('Place of Supply', supplyState ?? '-'),
      if (settings.showInvoiceSupplyType)
        _metaCell('Supply Type', supplyType ?? '-'),
    ];
    if (cells.isEmpty) return pw.SizedBox();

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(children: cells),
    );
  }

  static pw.Widget _metaCell(String label, String value) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
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
    final columns = [
      if (settings.showItemSerialColumn)
        _BillTableColumn(
          label: '#',
          width: const pw.FixedColumnWidth(24),
          alignment: pw.Alignment.center,
          value: (index, _) => '$index',
        ),
      if (settings.showItemNameColumn)
        _BillTableColumn(
          label: 'Item',
          width: const pw.FlexColumnWidth(2.6),
          alignment: pw.Alignment.centerLeft,
          value: (_, item) => item.productName,
        ),
      if (showHsn)
        _BillTableColumn(
          label: 'HSN',
          width: const pw.FlexColumnWidth(0.8),
          alignment: pw.Alignment.centerRight,
          value: (_, item) => item.hsnCodeSnapshot ?? '-',
        ),
      if (settings.showQuantityColumn)
        _BillTableColumn(
          label: 'Qty',
          width: const pw.FlexColumnWidth(0.75),
          alignment: pw.Alignment.centerRight,
          value: (_, item) => item.quantityLabel,
        ),
      if (settings.showRateColumn)
        _BillTableColumn(
          label: 'Rate',
          width: const pw.FlexColumnWidth(0.9),
          alignment: pw.Alignment.centerRight,
          value: (_, item) => _money(_lineRate(item, showGst: showGst)),
        ),
      if (showGst && settings.showGstPercentColumn)
        _BillTableColumn(
          label: 'GST %',
          width: const pw.FlexColumnWidth(0.65),
          alignment: pw.Alignment.centerRight,
          value: (_, item) => _taxLabel(item.gstPercentSnapshot),
        ),
      if (showGst && settings.showGstAmountColumn)
        _BillTableColumn(
          label: 'GST',
          width: const pw.FlexColumnWidth(0.85),
          alignment: pw.Alignment.centerRight,
          value: (_, item) => _money(item.totalGst),
        ),
      if (settings.showAmountColumn)
        _BillTableColumn(
          label: 'Amount',
          width: const pw.FlexColumnWidth(0.95),
          alignment: pw.Alignment.centerRight,
          value: (_, item) => _money(_lineAmount(item, showGst: showGst)),
        ),
    ];
    if (columns.isEmpty) return pw.SizedBox();

    final headers = columns.map((column) => column.label).toList();
    final data = bill.items.asMap().entries.map((entry) {
      final index = entry.key + 1;
      return columns.map((column) => column.value(index, entry.value)).toList();
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
        for (final entry in columns.asMap().entries)
          entry.key: entry.value.alignment,
      },
      columnWidths: {
        for (final entry in columns.asMap().entries)
          entry.key: entry.value.width,
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
    final rows = [
      if (settings.showSubtotal) _totalRow('Subtotal', bill.subtotalAmount),
      if (settings.showDiscount && bill.discountAmount > 0)
        _totalRow(
          'Discount (${bill.discountPercent.toStringAsFixed(2)}%)',
          -bill.discountAmount,
        ),
      if (showGst && settings.showTaxableAmount)
        _totalRow('Taxable Amount', bill.taxableAmount),
      if (showGst && settings.showCgstSgstIgst && bill.cgstAmount > 0)
        _totalRow('CGST', bill.cgstAmount),
      if (showGst && settings.showCgstSgstIgst && bill.sgstAmount > 0)
        _totalRow('SGST', bill.sgstAmount),
      if (showGst && settings.showCgstSgstIgst && bill.igstAmount > 0)
        _totalRow('IGST', bill.igstAmount),
      if (showGst && settings.showGstTotal && gstTotal > 0)
        _totalRow('GST Total', gstTotal),
      if (settings.showGrandTotal) ...[
        pw.Divider(),
        _totalRow('Grand total', bill.totalAmount, bold: true),
      ],
    ];
    if (rows.isEmpty) return pw.SizedBox();

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(width: 260, child: pw.Column(children: rows)),
    );
  }

  static pw.Widget _footer(BillSettings settings) {
    final signature = settings.showDigitalSignature
        ? _imageProvider(settings.digitalSignatureBase64)
        : null;
    final footerText = settings.showFooterText
        ? settings.footerText.trim()
        : '';
    if (footerText.isEmpty && signature == null) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(color: PdfColors.grey400),
        if (footerText.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            footerText,
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
    final visibleLines = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
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
          ...visibleLines.map(
            (line) => pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      ),
    );
  }

  static List<String> _sellerLines(ShopProfile? shop, BillSettings settings) {
    final name = _cleanText(shop?.name) ?? 'Storely';
    final address = _cleanText(shop?.address);
    final phone = _cleanText(shop?.phone);
    final email = _cleanText(shop?.email);
    final gstin = _cleanGstin(shop?.gstin);

    return [
      if (settings.showShopName) name,
      if (address != null && settings.showShopAddress) address,
      if (phone != null && settings.showShopPhone) 'Phone: $phone',
      if (email != null && settings.showShopEmail) 'Email: $email',
      if (gstin != null && settings.showShopGstin) 'GSTIN: $gstin',
    ];
  }

  static double _lineRate(BillItem item, {required bool showGst}) {
    if (!showGst) return item.sellingPriceSnapshot;
    return item.taxableValueSnapshot;
  }

  static double _lineAmount(BillItem item, {required bool showGst}) {
    if (!showGst) return item.subtotal;
    return item.totalTaxableValue + item.totalGst;
  }

  static String _taxLabel(double? percent) {
    if (percent == null || percent <= 0) return '-';
    final isWhole = percent == percent.roundToDouble();
    return '${percent.toStringAsFixed(isWhole ? 0 : 2)}%';
  }

  static List<String> _buyerLines(Bill bill, BillSettings settings) {
    final customerName = _cleanText(bill.customerName) ?? 'Walk-in Customer';
    final legalName = _cleanText(bill.customerGstLegalName);
    final tradeName = _cleanText(bill.customerGstTradeName);
    final gstin = _cleanGstin(bill.customerGstin);
    final address = _cleanText(bill.customerAddressSnapshot);
    final phone = _cleanText(bill.customerPhone);
    final supplyState = _cleanStateCode(bill.placeOfSupplyStateCode ?? gstin);
    final isB2b = bill.billType == Bill.typeB2b || gstin != null;
    final displayName = isB2b
        ? legalName ?? tradeName ?? customerName
        : customerName;

    return [
      if (settings.showCustomerName) displayName,
      if (settings.showCustomerTradeName &&
          isB2b &&
          tradeName != null &&
          tradeName != displayName)
        'Trade Name: $tradeName',
      if (settings.showCustomerLegalName &&
          isB2b &&
          legalName != null &&
          legalName != displayName)
        'Legal Name: $legalName',
      if (settings.showCustomerName && isB2b && customerName != displayName)
        'Contact: $customerName',
      if (settings.showCustomerGstin && isB2b && gstin != null) 'GSTIN: $gstin',
      if (phone != null && settings.showCustomerPhone) 'Phone: $phone',
      if (address != null && settings.showCustomerAddress) 'Address: $address',
      if (settings.showCustomerPlaceOfSupply && isB2b && supplyState != null)
        'Place of Supply: $supplyState',
    ];
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

  static String? _cleanText(String? value) {
    final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _cleanGstin(String? value) {
    final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _cleanStateCode(String? value) {
    final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits == null || digits.isEmpty) return null;
    return digits.padLeft(2, '0').substring(0, 2);
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

class _BillTableColumn {
  final String label;
  final pw.TableColumnWidth width;
  final pw.Alignment alignment;
  final String Function(int index, BillItem item) value;

  const _BillTableColumn({
    required this.label,
    required this.width,
    required this.alignment,
    required this.value,
  });
}
