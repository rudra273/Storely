import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/product.dart';

class PdfGenerator {
  static const codeTypeQr = 'qr';
  static const codeTypeBarcode = 'barcode';

  /// Generates a PDF with product QR/barcode labels in a fixed-size grid on A4 pages.
  /// Labels are always the same size regardless of product count.
  static Future<Uint8List> generate(
    List<Product> products, {
    int columns = 3,
    int rows = 8,
    String codeType = codeTypeQr,
  }) async {
    final pdf = pw.Document(title: 'Storely Product Labels', author: 'Storely');

    final itemsPerPage = columns * rows;
    final totalPages = (products.length / itemsPerPage).ceil();

    // A4 usable area after margins
    const margin = 20.0;
    final usableWidth = PdfPageFormat.a4.width - (margin * 2);
    final usableHeight = PdfPageFormat.a4.height - (margin * 2);
    final cellWidth = usableWidth / columns;
    final cellHeight = usableHeight / rows;

    for (int page = 0; page < totalPages; page++) {
      final startIndex = page * itemsPerPage;
      final endIndex = (startIndex + itemsPerPage).clamp(0, products.length);
      final pageProducts = products.sublist(startIndex, endIndex);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(margin),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: _buildFixedRows(
                pageProducts,
                columns: columns,
                rows: rows,
                cellWidth: cellWidth,
                cellHeight: cellHeight,
                codeType: codeType,
              ),
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  static List<pw.Widget> _buildFixedRows(
    List<Product> products, {
    required int columns,
    required int rows,
    required double cellWidth,
    required double cellHeight,
    required String codeType,
  }) {
    final List<pw.Widget> rowWidgets = [];

    for (int row = 0; row < rows; row++) {
      final startIndex = row * columns;
      if (startIndex >= products.length) break;

      final endIndex = (startIndex + columns).clamp(0, products.length);
      final rowProducts = products.sublist(startIndex, endIndex);

      rowWidgets.add(
        pw.SizedBox(
          height: cellHeight,
          child: pw.Row(
            children: [
              ...rowProducts.map(
                (product) => _buildLabel(
                  product,
                  cellWidth,
                  cellHeight,
                  codeType: codeType,
                ),
              ),
              // Fill remaining cells in this row with empty space
              ...List.generate(
                columns - rowProducts.length,
                (_) => pw.SizedBox(width: cellWidth),
              ),
            ],
          ),
        ),
      );
    }

    return rowWidgets;
  }

  static pw.Widget _buildLabel(
    Product product,
    double cellWidth,
    double cellHeight, {
    required String codeType,
  }) {
    final isBarcode = codeType == codeTypeBarcode;
    final codeWidth = isBarcode ? cellWidth * 0.82 : cellHeight * 0.7;
    final codeHeight = isBarcode ? cellHeight * 0.32 : cellHeight * 0.7;
    final data = isBarcode ? _barcodeData(product) : product.toQrData();

    return pw.SizedBox(
      width: cellWidth,
      height: cellHeight,
      child: pw.Container(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            // Product name above the scannable code.
            pw.Text(
              product.name,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
            ),
            pw.SizedBox(height: 3),
            pw.SizedBox(
              width: codeWidth,
              height: codeHeight,
              child: pw.BarcodeWidget(
                barcode: isBarcode ? pw.Barcode.code128() : pw.Barcode.qrCode(),
                data: data,
              ),
            ),
            if (isBarcode) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                data,
                style: const pw.TextStyle(fontSize: 6),
                maxLines: 1,
                overflow: pw.TextOverflow.clip,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _barcodeData(Product product) {
    final value = product.barcode ?? product.productCode ?? product.uuid;
    return value.trim().isEmpty ? product.name : value.trim();
  }

  /// Returns the number of A4 pages needed
  static int pageCount(int productCount, {int columns = 3, int rows = 8}) {
    if (productCount == 0) return 0;
    return (productCount / (columns * rows)).ceil();
  }
}
