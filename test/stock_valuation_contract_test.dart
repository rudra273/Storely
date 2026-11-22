import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';

void main() {
  final contract =
      jsonDecode(
            File(
              'test/fixtures/stock_valuation_contract_v1.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final db = DatabaseHelper.instance;
  final stamp = DateTime.utc(2026, 11, 22).toIso8601String();
  double number(Object input) => double.parse(input as String);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final valuationCase in contract['cases'] as List) {
    test('independent stock valuation for ${valuationCase['id']}', () async {
      await db.close();
      final original = DatabaseHelper.databaseFileName;
      DatabaseHelper.databaseFileName = 'stock-valuation-contract.db';
      final path = await DatabaseHelper.databasePath();
      await deleteDatabase(path);
      try {
        final sql = await db.database;
        final shop = await db.currentShopId();
        final settings = <String, dynamic>{
          ...contract['shop_defaults'] as Map<String, dynamic>,
          'gst_scheme': valuationCase['gst_scheme'],
          'gst_registered': valuationCase['gst_registered'],
        };
        for (final entry in settings.entries) {
          await sql.insert('app_settings', {
            'shop_id': shop,
            'key': entry.key,
            'value': entry.value,
            'updated_at': stamp,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        final categories = <String, int>{};
        for (final category in contract['categories'] as List) {
          final key = category['id'] as String;
          categories[key] = await sql.insert('categories', {
            'uuid': key,
            'shop_id': shop,
            'name': key,
            'gst_percent': number(category['gst_percent']),
            'overhead_cost': number(category['overhead_cost']),
            'created_at': stamp,
            'updated_at': stamp,
          });
        }
        final names = <String, String>{};
        for (final product in contract['products'] as List) {
          final key = product['id'] as String;
          names[key] = product['name'] as String;
          await sql.insert('products', {
            'uuid': key,
            'shop_id': shop,
            'name': names[key],
            'category_id': categories[product['category']],
            'quantity_cache': number(product['quantity']),
            'purchase_price': number(product['purchase_price']),
            'selling_price': number(product['selling_price']),
            'gst_percent': product['gst_percent'] == null
                ? null
                : number(product['gst_percent']),
            'overhead_cost': product['overhead_cost'] == null
                ? null
                : number(product['overhead_cost']),
            'track_stock': product['track_stock'] == false ? 0 : 1,
            'created_at': stamp,
            'updated_at': stamp,
            if (product['deleted'] == true) 'deleted_at': stamp,
          });
        }

        final rows = await db.stockValuation();
        final expected = valuationCase['expected'];
        expect(
          rows.map((row) => row.name),
          (contract['expected_order'] as List).map((key) => names[key]),
        );
        for (final entry in (expected['items'] as Map).entries) {
          final row = rows.singleWhere((row) => row.name == names[entry.key]);
          expect(
            row.costValue.toStringAsFixed(2),
            entry.value['cost_value'],
            reason: row.name,
          );
          expect(
            row.saleValue.toStringAsFixed(2),
            entry.value['sale_value'],
            reason: row.name,
          );
        }
        expect(
          rows
              .fold<double>(0, (sum, row) => sum + row.costValue)
              .toStringAsFixed(2),
          expected['total_cost'],
        );
        expect(
          rows
              .fold<double>(0, (sum, row) => sum + row.saleValue)
              .toStringAsFixed(2),
          expected['total_sale'],
        );
      } finally {
        await db.close();
        await deleteDatabase(path);
        DatabaseHelper.databaseFileName = original;
      }
    });
  }
}
