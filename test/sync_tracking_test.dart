import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
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

  Future<int> dirty(String table, {String where = '1 = 1'}) async {
    final raw = await db.database;
    final rows = await raw.rawQuery(
      'SELECT COUNT(*) AS n FROM $table WHERE sync_dirty = 1 AND $where',
    );
    return rows.single['n'] as int;
  }

  Future<void> markAllClean() async {
    final raw = await db.database;
    for (final table in [
      'products',
      'customers',
      'bills',
      'bill_items',
      'bill_payments',
      'stock_movements',
    ]) {
      await raw.update(table, {'sync_dirty': 0});
    }
  }

  Future<int> sell(int productId, {String? phone, bool paid = true}) async {
    final product = await db.getProductById(productId);
    final item = await db.buildBillItemForProduct(product!);
    return db.insertBill(
      Bill(
        customerName: 'Asha',
        customerPhone: phone,
        subtotalAmount: item.subtotal,
        totalAmount: item.subtotal,
        itemCount: 1,
        isPaid: paid,
      ),
      [item],
    );
  }

  test('local inserts and real edits are queued for upload', () async {
    final id = await db.insertProduct(
      Product(name: 'Soap', mrp: 0, purchasePrice: 20, quantity: 5),
    );
    expect(await dirty('products'), 1);

    await markAllClean();
    final product = await db.getProductById(id);
    await db.updateProduct(product!.copyWith(name: 'Bath Soap'));
    expect(await dirty('products'), 1);
  });

  test('a sale does not re-queue the product (stock cache only)', () async {
    final id = await db.insertProduct(
      Product(name: 'Soap', mrp: 0, purchasePrice: 20, quantity: 5),
    );
    await markAllClean();

    await sell(id);

    expect(await dirty('products'), 0);
    expect(await dirty('bills'), 1);
    expect(await dirty('stock_movements'), 1);
    expect((await db.getProductById(id))!.quantity, 4);
  });

  test('recording a payment queues the payment, not the bill', () async {
    final id = await db.insertProduct(
      Product(name: 'Soap', mrp: 0, purchasePrice: 20, quantity: 5),
    );
    final billId = await sell(id, paid: false);
    await markAllClean();

    await db.recordBillPayment(billId, amount: 1);

    expect(await dirty('bill_payments'), 1);
    expect(await dirty('bills'), 0);
  });

  test('loading customers does not re-stamp customers or bills', () async {
    final id = await db.insertProduct(
      Product(name: 'Soap', mrp: 0, purchasePrice: 20, quantity: 5),
    );
    await sell(id, phone: '9876543210');
    await db.getAllCustomers();
    await markAllClean();
    final raw = await db.database;
    final before = await raw.query('customers', columns: ['updated_at']);

    await db.getAllCustomers();
    await db.getAllCustomers();

    expect(await dirty('customers'), 0);
    expect(await dirty('bills'), 0);
    final after = await raw.query('customers', columns: ['updated_at']);
    expect(after, before);
  });

  test('rows imported from the cloud arrive clean', () async {
    final shopId = await db.currentShopId();
    await db.cloudImportRows('categories', [
      {
        'uuid': 'cat-1',
        'shop_id': shopId,
        'name': 'Snacks',
        'created_at': '2026-10-01T00:00:00.000Z',
        'updated_at': '2026-10-01T00:00:00.000Z',
      },
    ]);
    expect(await dirty('categories', where: "uuid = 'cat-1'"), 0);

    // Updating it from the cloud again also stays clean.
    await db.cloudImportRows('categories', [
      {
        'uuid': 'cat-1',
        'shop_id': shopId,
        'name': 'Snacks & Namkeen',
        'created_at': '2026-10-01T00:00:00.000Z',
        'updated_at': '2026-10-02T00:00:00.000Z',
      },
    ]);
    expect(await dirty('categories', where: "uuid = 'cat-1'"), 0);
    final exported = await db.cloudExportRows('categories');
    expect(exported.any((row) => row.containsKey('sync_dirty')), isFalse);
  });
}

Future<void> _deleteStorelyDb() async {
  final dbPath = await getDatabasesPath();
  await deleteDatabase(p.join(dbPath, 'storely.db'));
}
