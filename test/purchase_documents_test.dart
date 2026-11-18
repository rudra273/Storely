import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/supplier.dart';
import 'package:storely/models/product_purchase.dart';
import 'package:storely/models/purchase_document.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';
import 'package:storely/services/sync/purchase_sync_backend.dart';
import 'package:storely/services/sync/sync_backend.dart';

import 'support/fake_sync_backend.dart';

class ReceiptServer extends FakeSyncBackend
    implements PurchaseSyncBackend, SupplierPaymentSyncBackend {
  final Map<String, Map<String, dynamic>> documents = {};
  final Map<String, String> originalRequests = {};
  final List<String> publishes = [];
  bool dropAck = false;
  bool deny = false;

  bool dropPaymentAck = false;
  bool rejectPayment = false;
  final Map<String, Map<String, dynamic>> paymentRequests = {};
  @override
  Future<Map<String, dynamic>> publishSupplierPayment(
    String shopId,
    String supplierId,
    Map<String, dynamic> payment,
  ) async {
    if (rejectPayment) {
      throw const SyncRowRejected('Balance changed on another device.');
    }
    final key = payment['request_key'] as String;
    if (paymentRequests.containsKey(key)) {
      expect(jsonEncode(payment), jsonEncode(paymentRequests[key]));
    } else {
      paymentRequests[key] = payment;
      final id = documents.keys.single;
      documents[id] = {
        ...documents[id]!,
        'change_sequence': 3,
        'payment_status': 'partial',
        'paid_amount': '4.00',
        'balance_due': '6.00',
        'payments': [
          {
            'uuid': key,
            'payment_date': payment['payment_date'],
            'amount': '4.00',
            'payment_method': 'cash',
          },
        ],
      };
    }
    if (dropPaymentAck) {
      dropPaymentAck = false;
      throw StateError('Lost payment acknowledgement');
    }
    return {'uuid': key};
  }

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

  test(
    'offline supplier payment survives reopen and lost acknowledgement without duplicate balance or stock',
    () async {
      await purchase();
      await db.saveSupplierProfile(SupplierProfile(name: 'Payments vendor'));
      final profiles = await db.getSupplierProfiles();
      final supplierId = profiles.single.uuid;
      final server = ReceiptServer()..memberShopId = await db.currentShopId();
      final engine = CloudSyncEngine(
        backend: server,
        database: db,
        knownIsAdmin: true,
        pageSize: 1,
      );
      await engine.sync(firstSyncMode: FirstSyncMode.uploadExisting);
      final id = server.documents.keys.single;
      server.documents[id] = {
        ...server.documents[id]!,
        'supplier_uuid': supplierId,
        'total': '10.00',
        'balance_due': '10.00',
        'payment_status': 'unpaid',
        'change_sequence': 2,
      };
      await engine.sync();
      await db.queueSupplierPayment(supplierId, '4', 'cash', '2026-10-01');
      expect((await db.supplierAccounting(supplierId))['balance'], '6.00');
      expect((await db.pendingSyncCounts())['supplier_payment_queue'], 1);
      await db.close();
      expect((await db.pendingSupplierPayments()).length, 1);
      server.dropPaymentAck = true;
      await expectLater(engine.sync(), throwsStateError);
      final uncertain = (await db.pendingSupplierPayments()).single;
      expect(uncertain['command_state'], 'unknown');
      expect(uncertain['attempt_count'], 1);
      expect(uncertain['last_attempt_at'], isNotNull);
      await db.close();
      expect(
        (await db.pendingSupplierPayments()).single['payload'],
        uncertain['payload'],
      );
      server.rejectPayment =
          true; // e.g. access revoked after the first commit.
      final deniedReplay = await engine.sync();
      expect(
        deniedReplay.conflicts.any((c) => c.table == 'supplier_payment_queue'),
        isTrue,
      );
      final stillUnknown = (await db.pendingSupplierPayments()).single;
      expect(stillUnknown['command_state'], 'unknown');
      expect(stillUnknown['payload'], uncertain['payload']);
      // The receipt feed already includes the remote payment, but no matching
      // result UUID was acknowledged. Keep a conservative reservation until
      // replay resolves identity rather than allowing another unsafe payment.
      expect((await db.supplierAccounting(supplierId))['balance'], '2.00');
      await expectLater(
        db.queueSupplierPayment(supplierId, '3', 'cash', '2026-10-01'),
        throwsStateError,
      );
      server.rejectPayment = false;
      await engine.sync();
      final accepted = (await (await db.database).query(
        'supplier_payment_queue',
      )).single;
      expect(accepted['command_state'], 'accepted');
      expect(accepted['attempt_count'], 3);
      expect(server.paymentRequests.length, 1);
      expect((await db.pendingSupplierPayments()), isEmpty);
      expect((await db.supplierAccounting(supplierId))['balance'], '6.00');
      expect((await db.getAllProducts()).single.quantity, 2);
      await expectLater(
        db.queueSupplierPayment(supplierId, '7', 'cash', '2026-10-01'),
        throwsStateError,
      );
      await db.queueSupplierPayment(supplierId, '1', 'cash', '2026-10-01');
      server.rejectPayment = true;
      final rejected = await engine.sync();
      expect(
        rejected.conflicts.any((c) => c.table == 'supplier_payment_queue'),
        isTrue,
      );
      expect(await db.pendingSupplierPayments(), isEmpty);
      expect((await db.supplierAccounting(supplierId))['balance'], '6.00');
      server.rejectPayment = false;
      await engine.sync();
      expect(server.paymentRequests.length, 1);
      db.isAdminMutationAllowed = () => false;
      await expectLater(
        db.queueSupplierPayment(supplierId, '1', 'cash', '2026-10-01'),
        throwsStateError,
      );
    },
  );

  test(
    'large supplier payment stays exact across queue persistence and rejection',
    () async {
      await purchase();
      await db.saveSupplierProfile(SupplierProfile(name: 'Exact vendor'));
      final supplierId = (await db.getSupplierProfiles()).single.uuid;
      final server = ReceiptServer()..memberShopId = await db.currentShopId();
      final engine = CloudSyncEngine(
        backend: server,
        database: db,
        knownIsAdmin: true,
      );
      await engine.sync(firstSyncMode: FirstSyncMode.uploadExisting);
      final id = server.documents.keys.single;
      server.documents[id] = {
        ...server.documents[id]!,
        'supplier_uuid': supplierId,
        'total': '900719925474.02',
        'balance_due': '900719925474.02',
        'payment_status': 'unpaid',
        'change_sequence': 2,
      };
      await engine.sync();
      for (final invalid in ['1.005', '1.2300', '-1', ' 1 ', '1e2', '0']) {
        await expectLater(
          db.queueSupplierPayment(supplierId, invalid, 'cash', '2026-10-01'),
          throwsArgumentError,
          reason: invalid,
        );
      }
      expect(await db.pendingSupplierPayments(), isEmpty);
      await db.queueSupplierPayment(
        supplierId,
        '900719925474.01',
        'cash',
        '2026-10-01',
      );
      final original = (await db.pendingSupplierPayments()).single;
      expect(
        (jsonDecode(original['payload'] as String) as Map)['amount'],
        '900719925474.01',
      );
      expect((await db.supplierAccounting(supplierId))['balance'], '0.01');
      await db.close();
      expect(
        (await db.pendingSupplierPayments()).single['payload'],
        original['payload'],
      );
      expect((await db.supplierAccounting(supplierId))['balance'], '0.01');
      server.rejectPayment = true;
      final result = await engine.sync();
      expect(
        result.conflicts.any((c) => c.table == 'supplier_payment_queue'),
        isTrue,
      );
      expect(
        (await db.supplierAccounting(supplierId))['balance'],
        '900719925474.02',
      );
    },
  );

  test(
    'interrupted send reopens as unknown and duplicate claim cannot send twice',
    () async {
      final sql = await db.database;
      final shop = await db.currentShopId();
      const payload = '{"request_key":"durable-key","amount":"0.01"}';
      await sql.insert('supplier_payment_queue', {
        'request_key': 'durable-key',
        'shop_id': shop,
        'supplier_uuid': 'supplier',
        'payload': payload,
        'sync_state': 'pending',
        'created_at': '2026-10-01',
      });
      expect(
        await db.beginSupplierPaymentAttempt('durable-key', shopId: shop),
        isTrue,
      );
      expect(
        await db.beginSupplierPaymentAttempt('durable-key', shopId: shop),
        isFalse,
      );
      expect(await db.pendingSupplierPayments(), isEmpty);
      // A callback constrained to a different shop cannot accept this request.
      await db.setSupplierPaymentSync(
        'durable-key',
        shopId: 'other-shop',
        cloudUuid: 'wrong',
      );
      expect(
        (await sql.query('supplier_payment_queue')).single['command_state'],
        'sending',
      );
      await db.close();
      final recovered = (await db.pendingSupplierPayments()).single;
      expect(recovered['command_state'], 'unknown');
      expect(recovered['payload'], payload);
      expect(recovered['attempt_count'], 1);
      expect(
        await db.beginSupplierPaymentAttempt('durable-key', shopId: shop),
        isTrue,
      );
      await db.setSupplierPaymentSync(
        'durable-key',
        shopId: shop,
        error: 'Identity conflict',
        isConflict: true,
      );
      final conflict = (await (await db.database).query(
        'supplier_payment_queue',
      )).single;
      expect(conflict['command_state'], 'conflict');
      expect(conflict['sync_state'], 'pending');
      expect(conflict['attempt_count'], 2);
      expect(conflict['payload'], payload);
      expect(await db.pendingSupplierPayments(), isEmpty);
      expect(
        await db.beginSupplierPaymentAttempt('durable-key', shopId: shop),
        isFalse,
      );
    },
  );

  test(
    'v25 queue from an older backup gains local state without changing saved requests',
    () async {
      final sql = await db.database;
      final shop = await db.currentShopId();
      for (final state in ['pending', 'synced', 'error', 'local']) {
        await sql.insert('supplier_payment_queue', {
          'request_key': state,
          'shop_id': shop,
          'supplier_uuid': 'supplier',
          'payload': '{"request_key":"$state","amount":"0.01"}',
          'sync_state': state,
          'created_at': '2026-10-01',
        });
      }
      await db.close();
      final raw = await openDatabase(
        p.join(await getDatabasesPath(), files.first),
      );
      for (final column in [
        'command_state',
        'attempt_count',
        'last_attempt_at',
      ]) {
        await raw.execute(
          'ALTER TABLE supplier_payment_queue DROP COLUMN $column',
        );
      }
      await raw.delete(
        'cloud_sync_state',
        where: 'key = ?',
        whereArgs: ['migration_done:v26_supplier_payment_state'],
      );
      await raw.execute('PRAGMA user_version = 25');
      await raw.close();
      final migrated = await db.database;
      final rows = await migrated.query(
        'supplier_payment_queue',
        orderBy: 'request_key',
      );
      expect(
        {for (final row in rows) row['request_key']: row['command_state']},
        {
          'pending': 'unknown',
          'synced': 'accepted',
          'error': 'rejected',
          'local': 'local',
        },
      );
      for (final row in rows) {
        expect(row['attempt_count'], 0);
        expect(
          (jsonDecode(row['payload'] as String) as Map)['request_key'],
          row['request_key'],
        );
      }
      await db.beginSupplierPaymentAttempt('pending', shopId: shop);
      await db.markSupplierPaymentUncertain('pending', shopId: shop);
      await db.close();
      expect(
        (await db.pendingSupplierPayments()).single['command_state'],
        'unknown',
      );
    },
  );

  test('exact line amounts and currency do not use binary money math', () {
    expect(purchaseCentsText(purchaseLineCents('1', '0.005')), '0.01');
    expect(
      purchaseMoney('99999999999998000000.01'),
      '₹9,99,99,99,99,99,99,80,00,000.01',
    );
    expect(() => purchaseDecimal(1.12345), throwsArgumentError);
    expect(purchaseDecimal(0.1 + 0.2), '0.3');
    expect(normalizePurchaseDecimal('0001.2300'), '1.23');
    for (final legacyInvalid in ['-0', ' 1 ', '+1', '1.23000']) {
      expect(
        () => normalizePurchaseDecimal(legacyInvalid),
        throwsFormatException,
      );
    }
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
      server.documents[id] = {
        ...server.documents[id]!,
        'change_sequence': 2,
        'payment_status': 'partial',
        'total': '10.00',
        'paid_amount': '4.00',
        'balance_due': '6.00',
        'payments': [
          {
            'uuid': 'payment-1',
            'payment_date': '2026-10-01',
            'amount': '4.00',
            'payment_method': 'cash',
          },
        ],
      };
      await engine.sync();
      final updated = (await db.getPurchaseDocuments()).single;
      expect(updated.paymentStatus, 'partial');
      expect(updated.balanceDue, '6.00');
      expect(updated.payments.single['amount'], '4.00');
      expect((await db.getAllProducts()).single.quantity, 2);
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
