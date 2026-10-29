import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/product_purchase.dart';
import 'package:storely/models/purchase_document.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';
import 'package:storely/services/sync/purchase_sync_backend.dart';
import 'package:storely/services/sync/sync_backend.dart';

import 'support/fake_sync_backend.dart';

class ReceiptServer extends FakeSyncBackend implements PurchaseSyncBackend {
  final Map<String, Map<String, dynamic>> documents = {};
  final Map<String, String> originalRequests = {};
  final List<String> publishes = [];
  bool dropAck = false;
  bool deny = false;

  @override
  Future<Map<String, dynamic>> publishNativePurchase(
    String shopId,
    Map<String, dynamic> receipt,
  ) async {
    if (deny) throw const SyncRowRejected('Purchase access changed.');
    for (final item in receipt['items'] as List) {
      if (row('stock_movements', item['movement_uuid'] as String) == null) {
        throw StateError('Document published before its stock');
      }
    }
    final id = receipt['uuid'] as String;
    final encoded = jsonEncode(receipt);
    publishes.add(encoded);
    if (originalRequests.containsKey(id)) {
      expect(encoded, originalRequests[id]);
    } else {
      originalRequests[id] = encoded;
      documents[id] = {
        ...receipt,
        'created_at': '2026-10-29T10:00:00Z',
        'device_created_at': receipt['created_at'],
        'change_sequence': documents.length + 1,
      };
    }
    if (dropAck) {
      dropAck = false;
      throw StateError('Lost acknowledgement');
    }
    return Map<String, dynamic>.from(documents[id]!);
  }

  @override
  Future<List<Map<String, dynamic>>> pullPurchaseDocuments(
    String shopId, {
    required int afterSequence,
    required int limit,
  }) async {
    final rows =
        documents.values
            .where((r) => (r['change_sequence'] as int) > afterSequence)
            .toList()
          ..sort(
            (a, b) => (a['change_sequence'] as int).compareTo(
              b['change_sequence'] as int,
            ),
          );
    return rows.take(limit).map(Map<String, dynamic>.from).toList();
  }
}

void main() {
  final db = DatabaseHelper.instance;
  const files = ['purchase-a.db', 'purchase-b.db'];
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  Future<void> cleanup() async {
    await db.close();
    for (final file in files) {
      await deleteDatabase(p.join(await getDatabasesPath(), file));
    }
  }

  setUp(() async {
    await cleanup();
    DatabaseHelper.databaseFileName = files.first;
  });
  tearDown(() async {
    db.isAdminMutationAllowed = null;
    db.assertAdminMutation = null;
    await cleanup();
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  Future<void> purchase({
    String name = 'Tea',
    double quantity = 2,
    double cost = 0.005,
  }) => db
      .commitProductPurchaseBatch([
        ProductPurchaseCommit(
          product: Product(
            name: name,
            purchasePrice: cost,
            quantity: quantity,
            unit: 'pcs',
          ),
          quantityAdded: quantity,
        ),
      ], purchaseDate: DateTime(2026, 10, 1))
      .then((_) {});

  test('exact line amounts and currency do not use binary money math', () {
    expect(purchaseCentsText(purchaseLineCents('1', '0.005')), '0.01');
    expect(
      purchaseMoney('99999999999998000000.01'),
      '₹9,99,99,99,99,99,99,80,00,000.01',
    );
    expect(() => purchaseDecimal(1.12345), throwsArgumentError);
    expect(purchaseDecimal(0.1 + 0.2), '0.3');
  });

  test(
    'offline receipt captures stock once and restores after reopening',
    () async {
      await purchase();
      final receipts = await db.getPurchaseDocuments();
      expect(receipts.single.syncState, 'pending');
      expect(receipts.single.subtotal, '0.01');
      expect(receipts.single.items.single['quantity'], '2');
      expect((await db.pendingSyncCounts())['purchase_documents'], 1);
      await db.close();
      expect(
        (await db.getPurchaseDocuments()).single.uuid,
        receipts.single.uuid,
      );
      expect((await db.getAllProducts()).single.quantity, 2);
    },
  );

  test('failed batch leaves no products, stock or document behind', () async {
    await expectLater(
      db.commitProductPurchaseBatch([
        ProductPurchaseCommit(
          product: Product(
            uuid: 'same',
            name: 'A',
            purchasePrice: 1,
            quantity: 1,
          ),
          quantityAdded: 1,
        ),
        ProductPurchaseCommit(
          product: Product(
            uuid: 'same',
            name: 'B',
            purchasePrice: 1,
            quantity: 1,
          ),
          quantityAdded: 1,
        ),
      ], purchaseDate: DateTime(2026, 10, 1)),
      throwsA(anything),
    );
    await Future<void>.delayed(Duration.zero);
    expect(await db.getPurchaseDocuments(), isEmpty);
    expect(await db.getAllProducts(), isEmpty);
  });

  test(
    'lost document acknowledgement replays identical content without receiving again',
    () async {
      await purchase();
      final server = ReceiptServer()
        ..memberShopId = await db.currentShopId()
        ..dropAck = true;
      final engine = CloudSyncEngine(
        backend: server,
        database: db,
        knownIsAdmin: true,
        pageSize: 1,
      );
      await expectLater(
        engine.sync(firstSyncMode: FirstSyncMode.uploadExisting),
        throwsStateError,
      );
      expect((await db.pendingPurchaseDocuments()).length, 1);
      await engine.sync(firstSyncMode: FirstSyncMode.uploadExisting);
      expect(server.publishes.length, 2);
      expect(server.rows('stock_movements').length, 1);
      expect((await db.getAllProducts()).single.quantity, 2);
      expect((await db.getPurchaseDocuments()).single.syncState, 'synced');
      expect((await db.pendingSyncCounts())['purchase_documents'], isNull);
    },
  );

  test(
    'another phone downloads documents without adding duplicate stock',
    () async {
      await purchase();
      final server = ReceiptServer()..memberShopId = await db.currentShopId();
      await CloudSyncEngine(
        backend: server,
        database: db,
        knownIsAdmin: true,
        pageSize: 1,
      ).sync(firstSyncMode: FirstSyncMode.uploadExisting);
      final id = (await db.getPurchaseDocuments()).single.uuid;
      await db.close();
      DatabaseHelper.databaseFileName = files[1];
      final engine = CloudSyncEngine(
        backend: server,
        database: db,
        knownIsAdmin: true,
        pageSize: 1,
      );
      await engine.sync(firstSyncMode: FirstSyncMode.startFresh);
      expect((await db.getPurchaseDocuments()).single.uuid, id);
      expect((await db.getAllProducts()).single.quantity, 2);
      await engine.sync();
      expect((await db.getAllProducts()).single.quantity, 2);
      expect((await db.getPurchaseDocuments()).length, 1);
    },
  );

  test(
    'conflicting cloud snapshot preserves the pending local document',
    () async {
      await purchase();
      final receipt = (await db.getPurchaseDocuments()).single;
      final cloud = receipt.toJson()..['supplier_name'] = 'Different supplier';
      final conflict = await db.importPurchaseDocument(
        cloud,
        shopId: await db.currentShopId(),
      );
      expect(conflict, isNotNull);
      expect((await db.getPurchaseDocuments()).single.supplier, isNull);
      expect((await db.pendingPurchaseDocuments()).single.syncState, 'error');
      await expectLater(
        CloudSyncEngine.useCloudCopy(db, conflict!),
        throwsStateError,
      );
    },
  );

  test(
    'start fresh keeps existing native receipts local instead of adopting absent stock',
    () async {
      await purchase();
      final server = ReceiptServer()..memberShopId = await db.currentShopId();
      await CloudSyncEngine(
        backend: server,
        database: db,
        knownIsAdmin: true,
      ).sync(firstSyncMode: FirstSyncMode.startFresh);
      expect(server.publishes, isEmpty);
      expect((await db.getPurchaseDocuments()).single.syncState, 'local');
    },
  );

  test('permission changes preserve queued documents and hide costs', () async {
    await purchase();
    final server = ReceiptServer()
      ..memberShopId = await db.currentShopId()
      ..deny = true;
    final result = await CloudSyncEngine(
      backend: server,
      database: db,
      knownIsAdmin: true,
    ).sync(firstSyncMode: FirstSyncMode.uploadExisting);
    expect(result.conflicts.any((c) => c.table == 'purchase_documents'), true);
    expect((await db.pendingPurchaseDocuments()).length, 1);
    db.isAdminMutationAllowed = () => false;
    await expectLater(db.getPurchaseDocuments(), throwsStateError);
  });

  test(
    'v22 upgrade creates no guessed receipts and preserves old stock',
    () async {
      await db.insertProduct(
        Product(name: 'Legacy', purchasePrice: 10, quantity: 3),
      );
      final path = await DatabaseHelper.databasePath();
      await db.close();
      final raw = await databaseFactory.openDatabase(path);
      await raw.execute('DROP TABLE purchase_documents');
      await raw.execute('PRAGMA user_version = 22');
      await raw.close();
      expect(await db.getPurchaseDocuments(), isEmpty);
      expect((await db.getAllProducts()).single.quantity, 3);
      await db.close();
      expect(await db.getPurchaseDocuments(), isEmpty);
      expect((await db.getAllProducts()).single.quantity, 3);
    },
  );

  test(
    'purchase supplier overrides product preference, including anonymous receipts',
    () async {
      final id = await db.insertProduct(
        Product(
          name: 'Rice',
          purchasePrice: 10,
          quantity: 1,
          supplier: 'Preferred supplier',
        ),
      );
      final product = (await db.getProductById(id))!;
      await db.commitProductPurchaseBatch(
        [
          ProductPurchaseCommit(
            product: product,
            quantityAdded: 2,
            restockTarget: product,
          ),
        ],
        purchaseDate: DateTime(2026, 10, 1),
        usePurchaseSupplier: true,
        purchaseSupplier: null,
      );
      expect((await db.getPurchaseDocuments()).single.supplier, isNull);
      expect((await db.getProductById(id))!.supplier, 'Preferred supplier');
    },
  );
  test('zero-stock catalog setup does not invent a receipt', () async {
    await db.commitProductPurchaseBatch([
      ProductPurchaseCommit(
        product: Product(name: 'Catalog only', purchasePrice: 10, quantity: 0),
        quantityAdded: 0,
      ),
    ], purchaseDate: DateTime(2026, 10, 1));
    expect((await db.getAllProducts()).single.quantity, 0);
    expect(await db.getPurchaseDocuments(), isEmpty);
  });
}
