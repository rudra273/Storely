import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/product.dart';
import 'money.dart';
import 'pdf_theme.dart';

/// Where labels are printed.
enum LabelLayout {
  a4Sheet('A4 sheet', null, null),
  roll50x25('Label roll 50×25 mm', 50, 25),
  roll38x25('Label roll 38×25 mm', 38, 25);

  final String label;

  /// Label size in mm for rolls (one label per page); null for A4.
  final double? widthMm;
  final double? heightMm;

  const LabelLayout(this.label, this.widthMm, this.heightMm);

  bool get isRoll => widthMm != null;
}

/// One product and how many labels of it to print.
class LabelRequest {
  final Product product;
  final int copies;

  const LabelRequest(this.product, this.copies);
}

class PdfGenerator {
  static const codeTypeQr = 'qr';
  static const codeTypeBarcode = 'barcode';

  /// Product labels: each product repeated [LabelRequest.copies] times,
  /// either in a [columns] x [rows] grid on A4 or one per page on a label
  /// roll. Labels show the name, price (and MRP) and a QR code or barcode.
  static Future<Uint8List> generate(
    List<LabelRequest> requests, {
    LabelLayout layout = LabelLayout.a4Sheet,
    int columns = 3,
    int rows = 8,
    String codeType = codeTypeQr,
  }) async {
    final pdf = pw.Document(
      title: 'Storely Product Labels',
      author: 'Storely',
      theme: await storelyPdfTheme(),
    );
    final labels = [
      for (final r in requests)
        for (var i = 0; i < r.copies; i++) r.product,
    ];
    if (labels.isEmpty) {
      pdf.addPage(pw.Page(build: (_) => pw.SizedBox()));
      return pdf.save();
    }

    if (layout.isRoll) {
      final format = PdfPageFormat(
        layout.widthMm! * PdfPageFormat.mm,
        layout.heightMm! * PdfPageFormat.mm,
        marginAll: 1.5 * PdfPageFormat.mm,
      );
      for (final product in labels) {
        pdf.addPage(
          pw.Page(
            pageFormat: format,
            build: (_) => _buildLabel(
              product,
              format.availableWidth,
              format.availableHeight,
              codeType: codeType,
              compact: true,
            ),
          ),
        );
      }
      return pdf.save();
    }

    final itemsPerPage = columns * rows;
    const margin = 20.0;
    final cellWidth = (PdfPageFormat.a4.width - margin * 2) / columns;
    final cellHeight = (PdfPageFormat.a4.height - margin * 2) / rows;
    for (var start = 0; start < labels.length; start += itemsPerPage) {
      final page = labels.sublist(
        start,
        (start + itemsPerPage).clamp(0, labels.length),
      );
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(margin),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (var r = 0; r * columns < page.length; r++)
                pw.Row(
                  children: [
                    for (var c = 0; c < columns; c++)
                      r * columns + c < page.length
                          ? _buildLabel(
                              page[r * columns + c],
                              cellWidth,
                              cellHeight,
                              codeType: codeType,
                            )
                          : pw.SizedBox(width: cellWidth, height: cellHeight),
                  ],
                ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }

  static pw.Widget _buildLabel(
    Product product,
    double width,
    double height, {
    required String codeType,
    bool compact = false,
  }) {
    final isBarcode = codeType == codeTypeBarcode;
    final data = isBarcode ? barcodeData(product) : product.toQrData();
    final nameSize = compact ? 6.5 : 8.0;
    final priceText = [
      rupees(product.sellingPrice),
      if (product.printedMrp != null &&
          product.printedMrp! > product.sellingPrice + 0.004)
        'MRP ${rupees(product.printedMrp!)}',
    ].join('  ');

    final code = pw.BarcodeWidget(
      barcode: isBarcode ? pw.Barcode.code128() : pw.Barcode.qrCode(),
      data: data,
      drawText: false,
    );

    return pw.SizedBox(
      width: width,
      height: height,
      child: pw.Padding(
        padding: pw.EdgeInsets.all(compact ? 1 : 4),
        child: isBarcode
            ? pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  _name(product, nameSize),
                  pw.Text(
                    priceText,
                    style: pw.TextStyle(fontSize: nameSize - 0.5),
                  ),
                  pw.SizedBox(height: 1),
                  pw.SizedBox(
                    width: width * 0.9,
                    height: height * (compact ? 0.38 : 0.32),
                    child: code,
                  ),
                  pw.Text(data, style: const pw.TextStyle(fontSize: 6)),
                ],
              )
            : pw.Row(
                children: [
                  pw.SizedBox(
                    width: height * (compact ? 0.92 : 0.7),
                    height: height * (compact ? 0.92 : 0.7),
                    child: code,
                  ),
                  pw.SizedBox(width: 3),
                  pw.Expanded(
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _name(product, nameSize, align: pw.TextAlign.left),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          priceText,
                          style: pw.TextStyle(
                            fontSize: nameSize,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  static pw.Widget _name(
    Product product,
    double size, {
    pw.TextAlign align = pw.TextAlign.center,
  }) => pw.Text(
    product.name,
    style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
    textAlign: align,
    maxLines: 2,
    overflow: pw.TextOverflow.clip,
  );

  /// What a barcode label encodes: the product's barcode or code. Products
  /// with neither should get a short code first (see
  /// `DatabaseHelper.assignShortCodes`); the long id is the last resort.
  static String barcodeData(Product product) {
    for (final value in [product.barcode, product.productCode, product.uuid]) {
      final v = value?.trim() ?? '';
      // CODE 128 holds ASCII only (a Hindi name or code can't be encoded).
      if (v.isNotEmpty && v.runes.every((r) => r < 128)) return v;
    }
    return 'NO-CODE';
  }

  /// Pages needed for [labelCount] labels.
  static int pageCount(
    int labelCount, {
    LabelLayout layout = LabelLayout.a4Sheet,
    int columns = 3,
    int rows = 8,
  }) {
    if (labelCount == 0) return 0;
    if (layout.isRoll) return labelCount;
    return (labelCount / (columns * rows)).ceil();
  }
}
