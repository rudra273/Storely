part of 'database_helper.dart';

mixin DatabasePurchaseDocuments {
  Future<Database> get database;

  Future<Map<String, dynamic>> supplierAccounting(String supplier) async {
    if (!_canMutateAsAdmin()) {
      throw StateError('Supplier payments require admin access.');
    }
    final db = await database;
    return _supplierAccounting(db, await _activeShopId(db), supplier);
  }

  Future<Map<String, dynamic>> _supplierAccounting(
    DatabaseExecutor db,
    String shop,
    String supplier,
  ) async {
    final rows = await db.query(
      'purchase_documents',
      where: 'shop_id = ? AND deleted_at IS NULL',
      whereArgs: [shop],
    );
    final receipts = [
      for (final row in rows) _purchaseFromRow(row),
    ].where((r) => r.toJson()['supplier_uuid'] == supplier).toList();
    final queue = await db.query(
      'supplier_payment_queue',
      where: 'shop_id = ? AND supplier_uuid = ?',
      whereArgs: [shop, supplier],
      orderBy: 'created_at, request_key',
    );
    BigInt cents(String amount) {
      if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(amount)) {
        throw const FormatException('Invalid currency amount');
      }
      final parts = amount.split('.');
      return BigInt.parse(parts[0]) * BigInt.from(100) +
          BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(2, '0'));
    }

    var balance = BigInt.zero;
    final known = <String>{};
    for (final receipt in receipts) {
      if (receipt.balanceDue != null) balance += cents(receipt.balanceDue!);
      for (final payment in receipt.payments) {
        known.add(payment['uuid'] as String);
      }
    }
    for (final row in queue) {
      if ((row['sync_state'] == 'pending' || row['sync_state'] == 'synced') &&
          !known.contains(row['cloud_uuid'])) {
        balance -= cents(
          (jsonDecode(row['payload'] as String) as Map)['amount'] as String,
        );
      }
    }
    return {
      'balance': purchaseCentsText(
        balance < BigInt.zero ? BigInt.zero : balance,
      ),
      'receipts': receipts,
      'queue': queue,
    };
  }

  Future<void> queueSupplierPayment(
    String supplier,
    String amount,
    String method,
    String date,
  ) async {
    if (!_canMutateAsAdmin()) {
      throw StateError('Supplier payments require admin access.');
    }
    if (!RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(amount)) {
      throw ArgumentError('Enter an amount with up to two decimal places.');
    }
    final parsed = DateTime.tryParse(date);
    if (parsed == null ||
        _dateOnly(parsed) != date ||
        date.compareTo(_dateOnly(DateTime.now())) > 0) {
      throw ArgumentError('Choose a valid payment date up to today.');
    }
    if (!['cash', 'upi', 'card', 'bank_transfer', 'online'].contains(method)) {
      throw ArgumentError('Choose a payment method.');
    }
    BigInt cents(String value) {
      final parts = value.split('.');
      return BigInt.parse(parts[0]) * BigInt.from(100) +
          BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(2, '0'));
    }

    final paid = cents(amount);
    if (paid <= BigInt.zero) {
      throw ArgumentError('Payment must be greater than zero.');
    }
    final db = await database;
    final shop = await _activeShopId(db);
    await db.transaction((txn) async {
      final suppliers = await txn.query(
        'suppliers',
        where: 'shop_id = ? AND uuid = ? AND deleted_at IS NULL',
        whereArgs: [shop, supplier],
      );
      if (suppliers.isEmpty) {
        throw StateError('Supplier is no longer available.');
      }
      final statement = await _supplierAccounting(txn, shop, supplier);
      if (paid > cents(statement['balance'] as String)) {
        throw StateError(
          'Payment cannot exceed the recorded supplier balance.',
        );
      }
      final key = _newUuid();
      await txn.insert('supplier_payment_queue', {
        'request_key': key,
        'shop_id': shop,
        'supplier_uuid': supplier,
        'payload': jsonEncode({
          'request_key': key,
          'amount': purchaseCentsText(paid),
          'payment_date': date,
          'payment_method': method,
          'reference': null,
          'notes': null,
        }),
        'sync_state': 'pending',
        'created_at': _nowIso(),
      });
    });
  }

  Future<List<Map<String, Object?>>> pendingSupplierPayments() async {
    final db = await database;
    return db.query(
      'supplier_payment_queue',
      where: "shop_id = ? AND sync_state = 'pending'",
      whereArgs: [await _activeShopId(db)],
      orderBy: 'created_at, request_key',
    );
  }

  Future<void> setSupplierPaymentSync(
    String key, {
    String? cloudUuid,
    String? error,
  }) async {
    final db = await database;
    await db.update(
      'supplier_payment_queue',
      {
        'sync_state': error == null ? 'synced' : 'error',
        'cloud_uuid': cloudUuid,
        'last_error': error,
      },
      where: 'shop_id = ? AND request_key = ?',
      whereArgs: [await _activeShopId(db), key],
    );
  }

  Future<List<PurchaseDocument>> getPurchaseDocuments({
    int limit = 50,
    int offset = 0,
  }) async {
    if (!_canMutateAsAdmin()) {
      throw StateError(
        'Purchase costs are available to owners and admins only.',
      );
    }
    final db = await database;
    final shop = await _activeShopId(db);
    final rows = await db.query(
      'purchase_documents',
      where: 'shop_id = ? AND deleted_at IS NULL',
      whereArgs: [shop],
      orderBy: 'purchase_date DESC, uuid DESC',
      limit: limit,
      offset: offset,
    );
    return [for (final row in rows) _purchaseFromRow(row)];
  }

  PurchaseDocument _purchaseFromRow(Map<String, Object?> row) =>
      PurchaseDocument.fromJson(
        Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
        syncState: row['sync_state'] as String,
        syncError: row['last_error'] as String?,
      );

  Future<List<PurchaseDocument>> pendingPurchaseDocuments() async {
    final db = await database;
    final shop = await _activeShopId(db);
    final rows = await db.query(
      'purchase_documents',
      where: "shop_id = ? AND sync_state IN ('pending','error')",
      whereArgs: [shop],
      orderBy: 'created_at, uuid',
    );
    return [for (final row in rows) _purchaseFromRow(row)];
  }

  Future<bool> purchaseStockUploaded(PurchaseDocument receipt) async {
    final db = await database;
    final shop = await _activeShopId(db);
    for (final item in receipt.items) {
      final rows = await db.query(
        'stock_movements',
        columns: ['sync_dirty'],
        where: 'shop_id = ? AND uuid = ? AND deleted_at IS NULL',
        whereArgs: [shop, item['movement_uuid']],
      );
      if (rows.length != 1 || rows.single['sync_dirty'] != 0) return false;
    }
    return true;
  }

  Future<void> setPurchaseSyncError(String uuid, String error) async {
    final db = await database;
    await db.update(
      'purchase_documents',
      {'sync_state': 'error', 'last_error': error},
      where: 'uuid = ? AND shop_id = ?',
      whereArgs: [uuid, await _activeShopId(db)],
    );
  }

  Future<void> keepPendingPurchasesLocal() async {
    final db = await database;
    await db.update(
      'supplier_payment_queue',
      {'sync_state': 'local'},
      where: "shop_id = ? AND sync_state IN ('pending','error')",
      whereArgs: [await _activeShopId(db)],
    );
    await db.update(
      'purchase_documents',
      {'sync_state': 'local', 'last_error': null},
      where: "shop_id = ? AND sync_state IN ('pending','error')",
      whereArgs: [await _activeShopId(db)],
    );
  }

  Future<SyncConflict?> importPurchaseDocument(
    Map<String, dynamic> json, {
    required String shopId,
  }) async {
    final receipt = PurchaseDocument.fromJson(json);
    final db = await database;
    final shop = await _activeShopId(db);
    if (shop != shopId) {
      throw StateError('The active shop changed during purchase sync.');
    }
    return db.transaction((txn) async {
      final rows = await txn.query(
        'purchase_documents',
        where: 'uuid = ?',
        whereArgs: [receipt.uuid],
      );
      if (rows.isNotEmpty) {
        if (rows.single['shop_id'] != shop ||
            (rows.single['sync_state'] != 'synced' &&
                !_purchaseFromRow(rows.single).sameBusinessContent(receipt))) {
          const message =
              'Cloud purchase differs from the local receipt. Stock is preserved; review purchase history.';
          await txn.update(
            'purchase_documents',
            {'sync_state': 'error', 'last_error': message},
            where: 'uuid = ? AND shop_id = ?',
            whereArgs: [receipt.uuid, shop],
          );
          return SyncConflict(
            table: 'purchase_documents',
            key: receipt.uuid,
            message: message,
          );
        }
      }
      await txn.insert('purchase_documents', {
        'uuid': receipt.uuid,
        'shop_id': shop,
        'payload': jsonEncode(receipt.toJson()),
        'origin': receipt.origin,
        'sync_state': 'synced',
        'last_error': null,
        'created_at': receipt.createdAt,
        'purchase_date': receipt.date,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return null;
    });
  }
}

Future<void> _captureNativePurchase(
  DatabaseExecutor txn,
  String receiptUuid,
  DateTime date,
) async {
  final shop = await _activeShopId(txn);
  final rows = await txn.rawQuery(
    '''
    SELECT m.*, p.name AS product_name, u.name AS unit_name, s.name AS supplier_name
    FROM stock_movements m JOIN products p ON p.uuid = m.product_uuid
    LEFT JOIN units u ON u.id = p.unit_id LEFT JOIN suppliers s ON s.uuid = m.supplier_uuid
    WHERE m.shop_id = ? AND m.source_document_type = 'native_purchase'
      AND m.source_document_uuid = ? ORDER BY m.id
  ''',
    [shop, receiptUuid],
  );
  if (rows.isEmpty) throw StateError('A purchase must receive stock.');
  final suppliers = rows.map((row) => row['supplier_uuid']).toSet();
  if (suppliers.length != 1) throw StateError('Use one supplier per purchase.');
  var subtotal = BigInt.zero;
  final items = <Map<String, dynamic>>[];
  for (final row in rows) {
    final quantity = purchaseDecimal(row['quantity_delta'] as num);
    final cost = purchaseDecimal(row['unit_cost'] as num);
    final amount = purchaseLineCents(quantity, cost);
    subtotal += amount;
    items.add({
      'uuid': _newUuid(),
      'movement_uuid': row['uuid'],
      'product_uuid': row['product_uuid'],
      'product_name': row['product_name'],
      'unit_name': row['unit_name'],
      'quantity': quantity,
      'unit_cost': cost,
      'amount': purchaseCentsText(amount),
      'batch_no': row['batch_no'],
      'expiry_date': row['expiry_date'],
      'line_number': items.length + 1,
    });
  }
  final now = _nowIso();
  final payload = {
    'uuid': receiptUuid,
    'purchase_date': _dateOnly(date),
    'created_at': now,
    'origin': 'android',
    'subtotal': purchaseCentsText(subtotal),
    'payment_status': 'not_recorded',
    'supplier_uuid': rows.first['supplier_uuid'],
    'supplier_name': rows.first['supplier_name'],
    'invoice_number': null,
    'notes': null,
    'items': items,
  };
  await txn.insert('purchase_documents', {
    'uuid': receiptUuid,
    'shop_id': shop,
    'payload': jsonEncode(payload),
    'origin': 'android',
    'sync_state': 'pending',
    'created_at': now,
    'purchase_date': _dateOnly(date),
  });
}
