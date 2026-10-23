import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/services/sample_data.dart';

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
  });

  test('sample products are ready to bill at their own prices', () async {
    await SampleData.addProducts();
    final products = await db.getAllProducts();
    expect(products, hasLength(SampleData.products.length));
    final rice = products.firstWhere((p) => p.name == 'Rice (1 kg)');
    expect(rice.sellingPrice, 60);
    expect(rice.quantity, 25);
    expect(rice.hsnCode, '1006');
  });
}
