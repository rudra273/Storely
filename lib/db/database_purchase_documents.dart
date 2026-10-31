part of 'database_helper.dart';

mixin DatabasePurchaseDocuments {
  Future<Database> get database;

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
