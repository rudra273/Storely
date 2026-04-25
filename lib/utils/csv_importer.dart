import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import '../models/product.dart';

class CsvImporter {
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
  static Future<List<Product>> parseBytes(
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

    return _productsFromRows(rows);
  }

  static List<Product> _productsFromRows(List<List<dynamic>> rows) {
    if (rows.isEmpty) throw Exception('File is empty');
    if (rows.length < 2) {
      throw Exception('File must have a header row and at least one data row');
    }

    final header = _findHeader(rows);
    final mapping = header.mapping;

    if (mapping['name'] == null) {
      throw Exception(
        'Could not find a "Name" column. Found headers: ${header.row.join(", ")}',
      );
    }

    final products = <Product>[];
    for (int i = header.index + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      try {
        final name = _getString(row, mapping['name']);
        if (name == null || name.isEmpty) continue;

        products.add(
          Product(
            itemCode: _getString(row, mapping['item_code']),
            name: name,
            category: _getString(row, mapping['category']),
            mrp: _getDouble(row, mapping['mrp']) ?? 0,
            purchasePrice: _getDouble(row, mapping['purchase_price']),
            directPriceToggle: mapping['purchase_price'] == null,
            manualPrice: _getDouble(row, mapping['mrp']) ?? 0,
            quantity: _getInt(row, mapping['quantity']) ?? 0,
            unit: _getString(row, mapping['unit']),
            supplier: _getString(row, mapping['supplier']),
            source: ProductSource.imported,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    return products;
  }

  static _HeaderMatch _findHeader(List<List<dynamic>> rows) {
    final rowsToCheck = rows.length < 10 ? rows.length : 10;
    _HeaderMatch? best;

    for (int i = 0; i < rowsToCheck; i++) {
      final headers = rows[i]
          .map((h) => h.toString().trim().toLowerCase())
          .toList();
      final mapping = _mapColumns(headers);
      final score = mapping.values.whereType<int>().length;

      if (best == null || score > best.score) {
        best = _HeaderMatch(
          index: i,
          row: rows[i],
          mapping: mapping,
          score: score,
        );
      }

      if (mapping['name'] != null && score >= 2) return best;
    }

    return best ??
        _HeaderMatch(
          index: 0,
          row: rows.first,
          mapping: _mapColumns(
            rows.first.map((h) => h.toString().trim().toLowerCase()).toList(),
          ),
          score: 0,
        );
  }

  /// Reads CSV content into rows.
  static List<List<dynamic>> _readCsv(String content) {
    return const CsvToListConverter().convert(content, eol: '\n');
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

  /// Maps header names to our field names using fuzzy matching.
  static Map<String, int?> _mapColumns(List<String> headers) {
    final mapping = <String, int?>{
      'item_code': null,
      'name': null,
      'category': null,
      'mrp': null,
      'purchase_price': null,
      'quantity': null,
      'unit': null,
      'supplier': null,
    };

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (_matches(h, [
        'item id',
        'item_id',
        'itemid',
        'item code',
        'item_code',
        'itemcode',
        'code',
        'sku',
        'product id',
        'product_id',
        'product code',
        'product_code',
      ])) {
        mapping['item_code'] = i;
      } else if (_matches(h, [
        'name',
        'item name',
        'item_name',
        'product',
        'product name',
        'product_name',
        'description',
      ])) {
        mapping['name'] = i;
      } else if (_matches(h, ['category', 'cat', 'group', 'type', 'class'])) {
        mapping['category'] = i;
      } else if (_matches(h, [
        'purchase price',
        'purchase_price',
        'buying price',
        'buying_price',
        'cost price',
        'cost_price',
      ])) {
        mapping['purchase_price'] = i;
      } else if (_matches(h, [
        'price',
        'mrp',
        'rate',
        'unit price',
        'unit_price',
        'cost',
        'selling price',
        'amount',
      ])) {
        mapping['mrp'] = i;
      } else if (_matches(h, [
        'quantity',
        'qty',
        'stock',
        'count',
        'units',
        'available',
      ])) {
        mapping['quantity'] = i;
      } else if (_matches(h, [
        'unit',
        'uom',
        'measure',
        'measurement',
        'unit of measure',
        'unit_of_measure',
      ])) {
        mapping['unit'] = i;
      } else if (_matches(h, [
        'supplier',
        'vendor',
        'manufacturer',
        'brand',
        'source',
      ])) {
        mapping['supplier'] = i;
      }
    }

    return mapping;
  }

  static bool _matches(String header, List<String> keywords) {
    final clean = header.replaceAll(RegExp(r'[^a-z0-9 _]'), '').trim();
    return keywords.any((k) => clean == k || clean.contains(k));
  }

  static String? _getString(List row, int? index) {
    if (index == null || index >= row.length) return null;
    final val = row[index].toString().trim();
    return val.isEmpty ? null : val;
  }

  static double? _getDouble(List row, int? index) {
    if (index == null || index >= row.length) return null;
    final val = row[index].toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(val);
  }

  static int? _getInt(List row, int? index) {
    if (index == null || index >= row.length) return null;
    final val = row[index].toString().replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(val);
  }
}

class _HeaderMatch {
  final int index;
  final List<dynamic> row;
  final Map<String, int?> mapping;
  final int score;

  const _HeaderMatch({
    required this.index,
    required this.row,
    required this.mapping,
    required this.score,
  });
}
