import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product.dart';

enum ExportFormat { csv, xlsx }

/// Product list export. Columns match the importer's standard headers, so
/// an exported file can be edited and imported back.
class ProductExport {
  static const headers = [
    'product_name',
    'product_code',
    'barcode',
    'category',
    'unit',
    'hsn_code',
    'gst_percent',
    'purchase_price',
    'selling_price',
    'quantity',
    'reorder_level',
  ];

  static List<List<Object?>> rows(List<Product> products) => [
    headers,
    for (final p in products)
      [
        p.name,
        p.productCode ?? '',
        p.barcode ?? '',
        p.category ?? '',
        p.unit ?? '',
        p.hsnCode ?? '',
        p.gstPercent ?? '',
        _num(p.purchasePrice),
        _num(p.sellingPrice),
        p.trackStock ? _num(p.quantity) : '',
        p.reorderLevel == null ? '' : _num(p.reorderLevel!),
      ],
  ];

  static String toCsv(List<Product> products) =>
      const ListToCsvConverter().convert(rows(products));

  static Uint8List toXlsx(List<Product> products) {
    final book = xl.Excel.createExcel();
    final sheetName = book.getDefaultSheet() ?? 'Sheet1';
    book.rename(sheetName, 'Products');
    final sheet = book['Products'];
    for (final row in rows(products)) {
      sheet.appendRow([
        for (final cell in row)
          cell is num
              ? xl.DoubleCellValue(cell.toDouble())
              : xl.TextCellValue('${cell ?? ''}'),
      ]);
    }
    return Uint8List.fromList(book.encode()!);
  }

  /// Writes the export to a temp file and opens the share sheet.
  static Future<void> share(
    List<Product> products, {
    required ExportFormat format,
    String shopName = 'Storely',
  }) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final ext = format == ExportFormat.csv ? 'csv' : 'xlsx';
    final file = File('${dir.path}/products_$stamp.$ext');
    if (format == ExportFormat.csv) {
      await file.writeAsString(toCsv(products));
    } else {
      await file.writeAsBytes(toXlsx(products));
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: '$shopName products ($stamp)',
      ),
    );
  }

  static num _num(double v) =>
      v == v.roundToDouble() ? v.toInt() : double.parse(v.toStringAsFixed(4));
}
