import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';

void main() {
  late DatabaseHelper db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = DatabaseHelper.instance;
    await db.close();
    await _deleteStorelyDb();
  });

  tearDown(() async {
    await db.close();
    await _deleteStorelyDb();
  });

  group('Product inventory purchases', () {
    test(
      'merge import appends quantity for existing product identity',
      () async {
        final firstDate = DateTime(2026, 4, 20);
        final secondDate = DateTime(2026, 4, 25);

        final first = await db.mergeProducts([
          Product(
            itemCode: 'SKU-1',
            name: 'Cement Bag',
            mrp: 350,
            purchasePrice: 300,
            quantity: 10,
            supplier: 'Acme',
            source: ProductSource.imported,
          ),
        ], purchaseDate: firstDate);
        final second = await db.mergeProducts([
          Product(
            itemCode: 'SKU-1',
            name: 'Cement Bag',
            mrp: 360,
            purchasePrice: 310,
            quantity: 5,
            supplier: 'Acme',
            source: ProductSource.imported,
          ),
        ], purchaseDate: secondDate);

        final products = await db.getAllProducts();
        final summaries = await db.getProductPurchaseSummaries();
        final rows = await _purchaseRows();

        expect(first.added, 1);
        expect(first.updated, 0);
        expect(second.added, 0);
        expect(second.updated, 1);
        expect(products, hasLength(1));
        expect(products.single.quantity, 15);
        expect(products.single.purchasePrice, 310);
        expect(rows, hasLength(2));
        expect(summaries[products.single.id]!.lastPurchaseDate, secondDate);
        expect(summaries[products.single.id]!.lastPurchasePrice, 310);
      },
    );

    test('same purchase batch is flagged as possible duplicate', () async {
      final purchaseDate = DateTime(2026, 4, 25);
      final otherDate = DateTime(2026, 4, 26);
      final products = [
        Product(
          name: 'Notebook',
          mrp: 50,
          purchasePrice: 40,
          quantity: 12,
          supplier: 'Paper Co',
          source: ProductSource.imported,
        ),
      ];

      final first = await db.mergeProducts(
        products,
        purchaseDate: purchaseDate,
      );
      final duplicate = await db.wouldImportDuplicate(
        products,
        purchaseDate: purchaseDate,
      );
      final duplicateDifferentDate = await db.previewImportDuplicate(
        products,
        purchaseDate: otherDate,
      );
      final second = await db.mergeProducts(
        products,
        purchaseDate: purchaseDate,
      );

      expect(first.possibleDuplicate, isFalse);
      expect(duplicate, isTrue);
      expect(duplicateDifferentDate.possibleDuplicate, isFalse);
      expect(duplicateDifferentDate.duplicateOnDifferentDate, isTrue);
      expect(second.possibleDuplicate, isTrue);
    });

    test('purchase date filter returns products bought on that date', () async {
      final firstDate = DateTime(2026, 4, 20);
      final secondDate = DateTime(2026, 4, 25);
      await db.mergeProducts([
        Product(name: 'Item A', mrp: 10, purchasePrice: 8, quantity: 2),
        Product(name: 'Item B', mrp: 20, purchasePrice: 15, quantity: 3),
      ], purchaseDate: firstDate);
      await db.mergeProducts([
        Product(name: 'Item B', mrp: 21, purchasePrice: 16, quantity: 4),
      ], purchaseDate: secondDate);

      final products = await db.getAllProducts();
      final byName = {
        for (final product in products) product.name: product.id!,
      };
      final firstDateIds = await db.getProductIdsPurchasedOn(firstDate);
      final secondDateIds = await db.getProductIdsPurchasedOn(secondDate);

      expect(firstDateIds, {byName['Item A'], byName['Item B']});
      expect(secondDateIds, {byName['Item B']});
    });

    test('replace import only replaces imported identities', () async {
      await db.insertProduct(
        Product(name: 'Keep Me', mrp: 100, purchasePrice: 80, quantity: 7),
      );
      await db.insertProduct(
        Product(name: 'Replace Me', mrp: 50, purchasePrice: 40, quantity: 10),
      );

      final count = await db.replaceAllProducts([
        Product(name: 'Replace Me', mrp: 60, purchasePrice: 45, quantity: 3),
        Product(name: 'New Item', mrp: 20, purchasePrice: 15, quantity: 2),
      ], purchaseDate: DateTime(2026, 4, 25));

      final products = await db.getAllProducts();
      final byName = {for (final product in products) product.name: product};

      expect(count, 2);
      expect(products, hasLength(3));
      expect(byName['Keep Me']!.quantity, 7);
      expect(byName['Replace Me']!.quantity, 3);
      expect(byName['Replace Me']!.purchasePrice, 45);
      expect(byName['New Item']!.quantity, 2);
    });

    test('cloud import compares parsed timestamps instead of text', () async {
      final productId = await db.insertProduct(
        Product(name: 'Synced Item', mrp: 100, purchasePrice: 80, quantity: 5),
      );
      final database = await db.database;
      await database.update(
        'products',
        {'updated_at': '2026-04-30T11:30:00.000'},
        where: 'id = ?',
        whereArgs: [productId],
      );
      final rows = await db.cloudExportRows('products');
      final cloudRow = Map<String, dynamic>.from(rows.single)
        ..['quantity_cache'] = 7.0
        ..['updated_at'] = '2026-04-30T06:01:00.000Z';

      await db.cloudImportRows('products', [cloudRow]);

      final product = await db.getProductById(productId);
      expect(product!.quantity, 7);
    });
  });
}

Future<void> _deleteStorelyDb() async {
  final dbPath = await getDatabasesPath();
  await deleteDatabase(p.join(dbPath, 'storely.db'));
}

Future<List<Map<String, Object?>>> _purchaseRows() async {
  final database = await DatabaseHelper.instance.database;
  return database.query(
    'stock_movements',
    where: 'movement_type = ? AND deleted_at IS NULL',
    whereArgs: ['purchase'],
    orderBy: 'id ASC',
  );
}
