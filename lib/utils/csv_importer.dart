import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import '../models/product.dart';

/// One file row that could not be imported.
class ImportRowError {
  final int row;
  final String message;

  const ImportRowError(this.row, this.message);

  @override
  String toString() => 'Row $row: $message';
}

/// Parsed rows ready to import plus the rows that were skipped.
class ImportParseResult {
  final List<Product> products;
  final List<ImportRowError> errors;

  const ImportParseResult(this.products, this.errors);
}

class CsvImporter {
  static const requiredColumns = ['product_name', 'quantity', 'purchase_price'];
  static const optionalColumns = [
    'product_code',
    'barcode',
    'category',
    'selling_price',
    'unit',
    'hsn_code',
    'gst_percent',
    'reorder_level',
    'mrp_price',
  ];

  /// Other header spellings shop files use for each column (after
  /// normalising: lower case, words joined by "_").
  static const _aliases = <String, List<String>>{
    'product_name': ['name', 'product', 'item', 'item_name', 'description'],
    'quantity': ['qty', 'stock', 'opening_stock', 'quantity_in_stock'],
    'purchase_price': [
      'cost',
      'cost_price',
      'buy_price',
      'buying_price',
      'purchase_rate',
    ],
    'selling_price': [
      'price',
      'sale_price',
      'sales_price',
      'rate',
      'sale_rate',
      'mrp',
    ],
    'product_code': ['code', 'item_code', 'sku'],
    'barcode': ['bar_code', 'ean', 'upc'],
    'category': ['group', 'item_group'],
    'unit': ['uom', 'units'],
    'hsn_code': ['hsn', 'hsn_sac', 'sac', 'hsn_sac_code'],
    'gst_percent': ['gst', 'gst_rate', 'tax', 'tax_rate', 'gst_percentage'],
    'reorder_level': ['reorder', 'min_stock', 'minimum_stock', 'low_stock'],
    // Only when the file also has a selling price column; a lone "MRP"
    // column is taken as the selling price (above).
    'mrp_price': ['mrp', 'printed_mrp', 'max_retail_price'],
  };

  static String get columnGuide =>
      'Required columns: ${requiredColumns.join(', ')}\n'
      'Optional columns: ${optionalColumns.join(', ')}';

  /// Parses a CSV or Excel file and returns a list of Products.
  static Future<List<Product>> parseFile(
    String filePath, {
    String? fileName,
    String? extension,
  }) async {
    final ext = extension ?? (fileName ?? filePath).split('.').last;
    final bytes = await File(filePath).readAsBytes();

    return parseBytes(bytes, fileName: fileName ?? filePath, extension: ext);
  }

  /// Parses CSV or Excel bytes from file pickers that do not expose a path.
  /// Throws if any row has an error; see [parseBytesDetailed] to import the
  /// valid rows and list the rest.
  static Future<List<Product>> parseBytes(
    Uint8List bytes, {
    required String fileName,
    String? extension,
  }) async {
    final result = await parseBytesDetailed(
      bytes,
      fileName: fileName,
      extension: extension,
    );
    if (result.errors.isNotEmpty) {
      final preview = result.errors.take(10).join('\n');
      final suffix = result.errors.length > 10
          ? '\n...and ${result.errors.length - 10} more row errors'
          : '';
      throw Exception('Import failed:\n$preview$suffix');
    }
    return result.products;
  }

  /// Like [parseBytes], but returns the valid rows with per-row errors
  /// instead of failing the whole file. File-level problems still throw.
  static Future<ImportParseResult> parseBytesDetailed(
    Uint8List bytes, {
    required String fileName,
    String? extension,
  }) async {
    final ext = (extension ?? fileName.split('.').last).toLowerCase();

    if (bytes.isEmpty) throw Exception('File is empty or could not be read');

    List<List<dynamic>> rows;

    if (ext == 'xlsx') {
      rows = await _readExcel(bytes);
    } else if (ext == 'xls') {
      throw Exception(
        'Old .xls files are not supported. Save it as .xlsx or CSV and try again.',
      );
    } else {
      final content = utf8.decode(bytes, allowMalformed: true);
      rows = _readCsv(content);
    }

    return _parseRows(rows);
  }

  static ImportParseResult _parseRows(List<List<dynamic>> rows) {
    if (rows.isEmpty) throw Exception('File is empty');
    if (rows.length < 2) {
      throw Exception('File must have a header row and at least one data row');
    }

    final header = _readHeader(rows);
    final mapping = header.mapping;

    final missing = requiredColumns
        .where((column) => mapping[column] == null)
        .toList();
    if (missing.isNotEmpty) {
      throw Exception(
        'Missing required column(s): ${missing.join(', ')}\n'
        '$columnGuide\n'
        'Found headers: ${header.row.join(", ")}',
      );
    }

    final products = <Product>[];
    final errors = <ImportRowError>[];
    for (int i = header.index + 1; i < rows.length; i++) {
      final row = rows[i];
      if (_isBlankRow(row)) continue;

      final rowNumber = i + 1;
      final rowErrors = <String>[];
      final name = _getString(row, mapping['product_name']);
      if (name == null || name.isEmpty) {
        errors.add(ImportRowError(rowNumber, 'Product name is required'));
        continue;
      }

      final sellingPrice = _getMoney(
        row,
        mapping['selling_price'],
        'Selling price',
        rowNumber,
        rowErrors,
      );
      final purchasePrice = _getRequiredMoney(
        row,
        mapping['purchase_price'],
        'Purchase price',
        rowNumber,
        rowErrors,
      );
      final quantity = _getRequiredQuantity(
        row,
        mapping['quantity'],
        rowNumber,
        rowErrors,
      );
      final gstPercent = _getMoney(
        row,
        mapping['gst_percent'],
        'GST %',
        rowNumber,
        rowErrors,
      );
      if (gstPercent != null && !_gstRates.contains(gstPercent)) {
        rowErrors.add(
          'Row $rowNumber: GST % must be one of '
          '${_gstRates.map(_trimNumber).join(', ')}',
        );
      }
      final reorderLevel = _getQuantity(
        row,
        mapping['reorder_level'],
        rowNumber,
        rowErrors,
      );
      final printedMrp = _getMoney(
        row,
        mapping['mrp_price'],
        'MRP',
        rowNumber,
        rowErrors,
      );
      final hsn = _getString(row, mapping['hsn_code']);
      if (hsn != null && !RegExp(r'^\d{4,8}$').hasMatch(hsn)) {
        rowErrors.add('Row $rowNumber: HSN/SAC code must be 4 to 8 digits');
      }

      if (rowErrors.isNotEmpty) {
        errors.add(
          ImportRowError(
            rowNumber,
            rowErrors
                .map((e) => e.replaceFirst('Row $rowNumber: ', ''))
                .join('; '),
          ),
        );
        continue;
      }

      products.add(
        Product(
          productCode: _getString(row, mapping['product_code']),
          barcode: _getString(row, mapping['barcode']),
          name: name,
          category: _getString(row, mapping['category']),
          hsnCode: hsn,
          gstPercent: gstPercent,
          sellingPrice: sellingPrice ?? 0,
          purchasePrice: purchasePrice ?? 0,
          directPriceToggle: sellingPrice != null,
          manualPrice: sellingPrice,
          quantity: quantity ?? 0,
          reorderLevel: reorderLevel,
          printedMrp: printedMrp,
          unit: _getString(row, mapping['unit']),
          source: ProductSource.imported,
        ),
      );
    }

    return ImportParseResult(products, errors);
  }

  static const _gstRates = [0.0, 0.25, 3.0, 5.0, 12.0, 18.0, 28.0, 40.0];

  static String _trimNumber(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static _HeaderMatch _readHeader(List<List<dynamic>> rows) {
    for (var i = 0; i < rows.length; i++) {
      if (_isBlankRow(rows[i])) continue;
      final headers = rows[i].map((value) => _normaliseHeader(value)).toList();
      return _HeaderMatch(
        index: i,
        row: rows[i],
        mapping: _mapColumns(headers),
      );
    }
    throw Exception('File is empty');
  }

  /// Reads CSV content into rows.
  static List<List<dynamic>> _readCsv(String content) {
    // Keep every cell as text: number parsing turned barcodes/codes like
    // "001234" into 1234 and long codes into doubles, so they never matched.
    return const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(content, eol: '\n');
  }

  /// Reads an Excel file on a background isolate to prevent UI jank/crashes.
  static Future<List<List<dynamic>>> _readExcel(Uint8List bytes) async {
    // Run the heavy Excel decoding on a background isolate
    return compute(_decodeExcelBytes, bytes);
  }

  /// Top-level function for compute() — decodes Excel bytes into rows of strings.
  static List<List<dynamic>> _decodeExcelBytes(Uint8List bytes) {
    try {
      return _decodeExcelWithPackage(bytes);
    } catch (packageError) {
      try {
        return _decodeXlsxArchive(bytes);
      } catch (fallbackError) {
        throw Exception(
          'Failed to decode Excel file. Package decoder error: $packageError. Fallback decoder error: $fallbackError',
        );
      }
    }
  }

  static List<List<dynamic>> _decodeExcelWithPackage(Uint8List bytes) {
    xl.Excel excel;
    try {
      excel = xl.Excel.decodeBytes(bytes);
    } catch (e) {
      throw Exception('Failed to decode Excel file: $e');
    }

    if (excel.tables.isEmpty) {
      throw Exception('No sheets found in the Excel file');
    }

    // Try to find the first non-empty sheet
    xl.Sheet? sheet;
    String? foundSheetName;

    for (final name in excel.tables.keys) {
      final s = excel.tables[name];
      if (s != null && s.rows.isNotEmpty) {
        sheet = s;
        foundSheetName = name;
        break;
      }
    }

    if (sheet == null || foundSheetName == null) {
      throw Exception('All sheets in the Excel file are empty');
    }

    final rows = <List<dynamic>>[];
    for (final row in sheet.rows) {
      if (row.isEmpty) continue;

      final values = <String>[];
      for (final cell in row) {
        values.add(_cellToString(cell));
      }
      // Skip completely empty rows
      if (values.every((v) => v.trim().isEmpty)) continue;
      rows.add(values);
    }

    return rows;
  }

  /// Fallback XLSX reader for workbooks that crash package:excel while decoding.
  ///
  /// XLSX files are zip archives containing worksheet XML. This reader extracts
  /// raw cell text from the first non-empty sheet, which is enough for imports.
  static List<List<dynamic>> _decodeXlsxArchive(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStrings = _readSharedStrings(archive);
    final sheetPaths = _readSheetPaths(archive);

    if (sheetPaths.isEmpty) {
      throw Exception('No worksheet XML found in the Excel file');
    }

    for (final path in sheetPaths) {
      final sheetXml = _archiveText(archive, path);
      if (sheetXml == null) continue;

      final rows = _readSheetRows(sheetXml, sharedStrings);
      if (rows.isNotEmpty) return rows;
    }

    throw Exception('All sheets in the Excel file are empty');
  }

  static List<String> _readSharedStrings(Archive archive) {
    final xml = _archiveText(archive, 'xl/sharedStrings.xml');
    if (xml == null) return const [];

    final document = XmlDocument.parse(xml);
    return document.findAllElements('si').map((node) {
      return node
          .findAllElements('t')
          .where((textNode) => textNode.parentElement?.name.local != 'rPh')
          .map((textNode) => textNode.innerText)
          .join();
    }).toList();
  }

  static List<String> _readSheetPaths(Archive archive) {
    final workbookXml = _archiveText(archive, 'xl/workbook.xml');
    if (workbookXml == null) return _fallbackSheetPaths(archive);

    final relationships = _readWorkbookRelationships(archive);
    final document = XmlDocument.parse(workbookXml);
    final paths = <String>[];

    for (final sheet in document.findAllElements('sheet')) {
      final relationshipId = sheet.getAttribute('r:id');
      final target = relationshipId == null
          ? null
          : relationships[relationshipId];
      if (target != null) {
        paths.add(_normaliseXlsxPath(target));
        continue;
      }

      final sheetId = sheet.getAttribute('sheetId');
      if (sheetId != null) paths.add('xl/worksheets/sheet$sheetId.xml');
    }

    return paths.isEmpty ? _fallbackSheetPaths(archive) : paths;
  }

  static Map<String, String> _readWorkbookRelationships(Archive archive) {
    final xml = _archiveText(archive, 'xl/_rels/workbook.xml.rels');
    if (xml == null) return const {};

    final document = XmlDocument.parse(xml);
    final relationships = <String, String>{};

    for (final relationship in document.findAllElements('Relationship')) {
      final id = relationship.getAttribute('Id');
      final target = relationship.getAttribute('Target');
      if (id != null && target != null) relationships[id] = target;
    }

    return relationships;
  }

  static List<String> _fallbackSheetPaths(Archive archive) {
    final paths = archive.files
        .where(
          (file) =>
              file.isFile &&
              file.name.startsWith('xl/worksheets/') &&
              file.name.endsWith('.xml'),
        )
        .map((file) => file.name)
        .toList();

    paths.sort();
    return paths;
  }

  static List<List<dynamic>> _readSheetRows(
    String sheetXml,
    List<String> sharedStrings,
  ) {
    final document = XmlDocument.parse(sheetXml);
    final rows = <List<dynamic>>[];

    for (final row in document.findAllElements('row')) {
      final values = <String>[];

      for (final cell in row.findElements('c')) {
        final columnIndex = _cellColumnIndex(cell.getAttribute('r'));
        final index = columnIndex ?? values.length;
        while (values.length <= index) {
          values.add('');
        }
        values[index] = _readCellValue(cell, sharedStrings);
      }

      if (values.any((value) => value.trim().isNotEmpty)) rows.add(values);
    }

    return rows;
  }

  static String _readCellValue(XmlElement cell, List<String> sharedStrings) {
    final type = cell.getAttribute('t');

    if (type == 'inlineStr') {
      return cell.findAllElements('t').map((node) => node.innerText).join();
    }

    final value = _firstChildText(cell, 'v');
    if (value == null) return '';

    if (type == 's') {
      final index = int.tryParse(value);
      if (index == null || index < 0 || index >= sharedStrings.length) {
        return '';
      }
      return sharedStrings[index];
    }

    if (type == 'b') return value == '1' ? 'true' : 'false';

    return value;
  }

  static String? _firstChildText(XmlElement element, String name) {
    for (final child in element.findElements(name)) {
      return child.innerText;
    }
    return null;
  }

  static int? _cellColumnIndex(String? cellReference) {
    if (cellReference == null || cellReference.isEmpty) return null;

    var index = 0;
    var foundLetter = false;
    for (final unit in cellReference.codeUnits) {
      final upper = unit >= 97 && unit <= 122 ? unit - 32 : unit;
      if (upper < 65 || upper > 90) break;
      foundLetter = true;
      index = index * 26 + (upper - 64);
    }

    return foundLetter ? index - 1 : null;
  }

  static String _normaliseXlsxPath(String target) {
    var path = target.replaceAll('\\', '/');
    if (path.startsWith('/')) path = path.substring(1);
    if (!path.startsWith('xl/')) path = 'xl/$path';

    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }

    return parts.join('/');
  }

  static String? _archiveText(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null || !file.isFile) return null;

    file.decompress();
    return utf8.decode(file.content as List<int>, allowMalformed: true);
  }

  /// Safely extracts a string from an Excel Data cell.
  static String _cellToString(xl.Data? cell) {
    if (cell == null) return '';
    try {
      final v = cell.value;
      if (v == null) return '';

      // Excel v4 uses CellValue sealed class
      // We use .toString() on the inner value to be safe
      if (v is xl.TextCellValue) return v.value.toString();
      if (v is xl.IntCellValue) return v.value.toString();
      if (v is xl.DoubleCellValue) return v.value.toString();
      if (v is xl.BoolCellValue) return v.value.toString();
      if (v is xl.FormulaCellValue) return v.formula;

      // Handle Date/Time types if they exist in this version
      return v.toString();
    } catch (e) {
      return ''; // Silently skip problematic cells
    }
  }

  /// Maps standard header names (and their [_aliases]) to field names.
  /// An exact standard name wins over an alias.
  static Map<String, int?> _mapColumns(List<String> headers) {
    final mapping = <String, int?>{
      for (final column in [...requiredColumns, ...optionalColumns])
        column: null,
    };
    for (int i = 0; i < headers.length; i++) {
      if (mapping.containsKey(headers[i]) && mapping[headers[i]] == null) {
        mapping[headers[i]] = i;
      }
    }
    for (final entry in _aliases.entries) {
      if (mapping[entry.key] != null) continue;
      for (int i = 0; i < headers.length; i++) {
        if (entry.value.contains(headers[i]) && !mapping.values.contains(i)) {
          mapping[entry.key] = i;
          break;
        }
      }
    }
    return mapping;
  }

  /// "Product Name", "product-name" and " PRODUCT_NAME " all become
  /// "product_name"; "GST %" becomes "gst".
  static String _normaliseHeader(Object value) => value
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  static String? _getString(List row, int? index) {
    if (index == null || index >= row.length) return null;
    final val = row[index].toString().trim();
    return val.isEmpty ? null : val;
  }

  static bool _isBlankRow(List row) {
    return row.every((value) => value.toString().trim().isEmpty);
  }

  static double? _getMoney(
    List row,
    int? index,
    String label,
    int rowNumber,
    List<String> errors,
  ) {
    final value = _getDouble(row, index, label, rowNumber, errors);
    if (value != null && value < 0) {
      errors.add('Row $rowNumber: $label cannot be negative');
    }
    return value;
  }

  static double? _getRequiredMoney(
    List row,
    int? index,
    String label,
    int rowNumber,
    List<String> errors,
  ) {
    final value = _getMoney(row, index, label, rowNumber, errors);
    if (value == null && !_hasCellValue(row, index)) {
      errors.add('Row $rowNumber: $label is required');
    }
    return value;
  }

  static double? _getQuantity(
    List row,
    int? index,
    int rowNumber,
    List<String> errors,
  ) {
    final value = _getDouble(row, index, 'Quantity', rowNumber, errors);
    if (value != null && value < 0) {
      errors.add('Row $rowNumber: Quantity cannot be negative');
    }
    return value;
  }

  static double? _getRequiredQuantity(
    List row,
    int? index,
    int rowNumber,
    List<String> errors,
  ) {
    final value = _getQuantity(row, index, rowNumber, errors);
    if (value == null && !_hasCellValue(row, index)) {
      errors.add('Row $rowNumber: Quantity is required');
    }
    return value;
  }

  static double? _getDouble(
    List row,
    int? index,
    String label,
    int rowNumber,
    List<String> errors,
  ) {
    if (index == null || index >= row.length) return null;
    final raw = row[index].toString().trim();
    if (raw.isEmpty) return null;
    final value = parseIndianNumber(raw);
    if (value == null) {
      errors.add('Row $rowNumber: Invalid $label "$raw"');
    }
    return value;
  }

  /// Parses amounts as Indian shops write them: "Rs.250", "₹ 1,25,000.50",
  /// "INR 99", "250/-", and quantities with a unit ("2.5 kg"). Returns null for anything else instead of guessing
  /// (the old digit-stripping read "Rs.250" as 0.25).
  @visibleForTesting
  static double? parseIndianNumber(String raw) {
    var text = raw.trim().toLowerCase();
    text = text.replaceFirst(RegExp(r'^(rs\.?|inr|₹)\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*/-$'), '');
    text = text.replaceAll(',', '');
    // Optional trailing unit word, e.g. "2.5 kg", "10 pcs", "250 rs".
    final match = RegExp(r'^(-?\d+(\.\d+)?)\s*[a-z]*\.?$').firstMatch(text);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  static bool _hasCellValue(List row, int? index) {
    if (index == null || index >= row.length) return false;
    return row[index].toString().trim().isNotEmpty;
  }
}

class _HeaderMatch {
  final int index;
  final List<dynamic> row;
  final Map<String, int?> mapping;

  const _HeaderMatch({
    required this.index,
    required this.row,
    required this.mapping,
  });
}
