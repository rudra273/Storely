import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/product.dart';

class PdfGenerator {
  /// Generates a PDF with QR code labels in a fixed-size grid on A4 pages.
  /// Labels are always the same size regardless of product count.
  static Future<Uint8List> generate(
    List<Product> products, {
    int columns = 3,
    int rows = 8,
  }) async {
    final pdf = pw.Document(title: 'Storely QR Codes', author: 'Storely');

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
                (product) => _buildLabel(product, cellWidth, cellHeight),
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
    double cellHeight,
  ) {
    // QR code takes most of the cell, with space for the name above
    final qrSize = cellHeight * 0.7;

    return pw.SizedBox(
      width: cellWidth,
      height: cellHeight,
      child: pw.Container(
        padding: const pw.EdgeInsets.all(4),
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            // Product name above QR
            pw.Text(
              product.name,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
            ),
            pw.SizedBox(height: 3),
            // QR Code (contains name + mrp + qty encoded inside)
            pw.SizedBox(
              width: qrSize,
              height: qrSize,
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: product.toQrData(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns the number of A4 pages needed
  static int pageCount(int productCount, {int columns = 3, int rows = 8}) {
    if (productCount == 0) return 0;
    return (productCount / (columns * rows)).ceil();
  }
}
