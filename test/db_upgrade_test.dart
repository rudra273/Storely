import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/product.dart';

/// Regression coverage for installs whose database was created on DB v16
/// (app 1.0.0/1.0.1). Those devices keep the old `stock_movements` shape and
/// the old non-unique product indexes, because `CREATE ... IF NOT EXISTS`
/// never touches an existing table/index.
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

  test('v16 database upgrades and can save a bill', () async {
    await db.saveGlobalPricingSettings(
      const GlobalPricingSettings(
        defaultGstPercent: 0,
        defaultOverheadCost: 0,
        defaultProfitMarginPercent: 0,
        gstRegistered: false,
      ),
    );
    await _downgradeToV16Shape(db);

    final columns = await _columnNames('stock_movements');
    expect(columns, containsAll(_v20StockMovementColumns));

    final productId = await db.insertProduct(
      Product(
        name: 'Rice',
        mrp: 0,
        purchasePrice: 50,
        quantity: 10,
        unit: 'kg',
      ),
    );
    final product = await db.getProductById(productId);
    final item = await db.buildBillItemForProduct(product!);
    item.quantity = 2;

    await db.insertBill(
      Bill(
        customerName: 'Walk-in',
        subtotalAmount: item.subtotal,
        totalAmount: item.subtotal,
        itemCount: 2,
        isPaid: true,
        paymentMethod: 'cash',
      ),
      [item],
    );

    final updated = await db.getProductById(productId);
    expect(updated!.quantity, 8);
  });

  test('v16 duplicate barcodes are cleared and uniqueness enforced', () async {
    await db.insertProduct(
      Product(name: 'Soap A', mrp: 0, purchasePrice: 10, quantity: 1),
    );
    await db.insertProduct(
      Product(name: 'Soap B', mrp: 0, purchasePrice: 10, quantity: 1),
    );
    await _downgradeToV16Shape(
      db,
      beforeClose: (raw) async {
        // The old non-unique index allowed the same barcode twice.
        await raw.rawUpdate("UPDATE products SET barcode = '8901234567890'");
      },
    );

    final database = await db.database;
    final withBarcode = await database.query(
      'products',
      where: 'barcode = ?',
      whereArgs: ['8901234567890'],
    );
    expect(withBarcode, hasLength(1));
    expect(withBarcode.single['name'], 'Soap B');

    final indexSql = await database.rawQuery(
      "SELECT sql FROM sqlite_master WHERE name = 'idx_products_shop_barcode'",
    );
    expect(indexSql.single['sql'].toString(), contains('UNIQUE'));
  });
}

const _v20StockMovementColumns = [
  'supplier_id',
  'supplier_uuid',
  'source_document_type',
  'source_document_id',
  'source_document_uuid',
  'import_row_number',
];

/// Rewrites the freshly created database into the v16 on-disk shape, then
/// reopens it through [DatabaseHelper] so the real upgrade path runs.
Future<void> _downgradeToV16Shape(
  DatabaseHelper db, {
  Future<void> Function(Database raw)? beforeClose,
}) async {
  final raw = await db.database;
  await raw.execute('PRAGMA foreign_keys = OFF');
  await raw.execute('DROP TABLE stock_movements');
  await raw.execute('''
    CREATE TABLE stock_movements(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      shop_id TEXT NOT NULL,
      product_id INTEGER NOT NULL,
      product_uuid TEXT NOT NULL,
      movement_type TEXT NOT NULL,
      quantity_delta REAL NOT NULL,
      unit_cost REAL,
      source_type TEXT,
      source_id INTEGER,
      source_uuid TEXT,
      import_batch_key TEXT,
      notes TEXT,
      device_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      FOREIGN KEY (product_id) REFERENCES products(id)
    )
  ''');
  await raw.execute(
    'CREATE INDEX idx_stock_movements_source '
    'ON stock_movements(source_type, source_id)',
  );
  await raw.execute('DROP INDEX IF EXISTS idx_products_shop_barcode');
  await raw.execute(
    'CREATE INDEX idx_products_shop_barcode ON products(shop_id, barcode)',
  );
  await raw.execute('DROP INDEX IF EXISTS idx_products_shop_product_code');
  await raw.execute(
    'CREATE INDEX idx_products_shop_product_code '
    'ON products(shop_id, product_code)',
  );
  await raw.delete(
    'cloud_sync_state',
    where: 'key = ?',
    whereArgs: ['migration_done:v21_index_rebuild'],
  );
  if (beforeClose != null) await beforeClose(raw);
  await raw.execute('PRAGMA user_version = 16');
  await db.close();
}

Future<Set<String>> _columnNames(String table) async {
  final database = await DatabaseHelper.instance.database;
  final rows = await database.rawQuery('PRAGMA table_info($table)');
  return rows.map((row) => row['name'].toString()).toSet();
}

Future<void> _deleteStorelyDb() async {
  final dbPath = await getDatabasesPath();
  await deleteDatabase(p.join(dbPath, 'storely.db'));
}
