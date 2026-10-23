import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/product.dart';
import 'package:storely/services/product_export.dart';
import 'package:storely/utils/csv_importer.dart';

Uint8List _csv(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  test('common header spellings map to columns', () async {
    final result = await CsvImporter.parseBytesDetailed(
      _csv(
        'Item Name,Qty,Cost Price,MRP,HSN/SAC,GST %,UOM,Min Stock\n'
        'Tea 250g,12,80,110,0902,5,pkt,4\n',
      ),
      fileName: 'stock.csv',
    );
    expect(result.errors, isEmpty);
    final tea = result.products.single;
    expect(tea.name, 'Tea 250g');
    expect(tea.quantity, 12);
    expect(tea.purchasePrice, 80);
    expect(tea.sellingPrice, 110);
    expect(tea.hsnCode, '0902');
    expect(tea.gstPercent, 5);
    expect(tea.unit, 'pkt');
    expect(tea.reorderLevel, 4);
  });

  test('bad rows are listed and good rows still import', () async {
    final result = await CsvImporter.parseBytesDetailed(
      _csv(
        'product_name,quantity,purchase_price,gst_percent,hsn_code\n'
        'Soap,10,20,18,3401\n'
        ',5,10,,\n'
        'Oil,abc,90,,\n'
        'Salt,4,15,7,\n'
        'Rice,3,40,5,12\n',
      ),
      fileName: 'mixed.csv',
    );
    expect(result.products.map((p) => p.name), ['Soap']);
    expect(result.errors.map((e) => e.row), [3, 4, 5, 6]);
    expect(result.errors[2].message, contains('GST %'));
    expect(result.errors[3].message, contains('HSN'));
    // The strict API still refuses a file with errors.
    expect(
      () => CsvImporter.parseBytes(
        _csv('product_name,quantity,purchase_price\nOil,abc,90\n'),
        fileName: 'bad.csv',
      ),
      throwsException,
    );
  });

  test('exported files import back unchanged', () async {
    final products = [
      Product(
        name: 'Tea 250g',
        productCode: 'T1',
        barcode: '0089012345',
        category: 'Beverages',
        unit: 'pkt',
        hsnCode: '0902',
        gstPercent: 5,
        purchasePrice: 80,
        sellingPrice: 110,
        quantity: 12.5,
        reorderLevel: 4,
      ),
    ];
    for (final bytes in [
      _csv(ProductExport.toCsv(products)),
      ProductExport.toXlsx(products),
    ]) {
      final isCsv = bytes.first != 0x50; // xlsx is a zip ("PK")
      final back = await CsvImporter.parseBytesDetailed(
        bytes,
        fileName: isCsv ? 'p.csv' : 'p.xlsx',
      );
      expect(back.errors, isEmpty);
      final p = back.products.single;
      expect(p.name, 'Tea 250g');
      expect(p.productCode, 'T1');
      expect(p.barcode, '0089012345');
      expect(p.hsnCode, '0902');
      expect(p.gstPercent, 5);
      expect(p.purchasePrice, 80);
      expect(p.sellingPrice, 110);
      expect(p.quantity, 12.5);
      expect(p.reorderLevel, 4);
    }
  });
}
