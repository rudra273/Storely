part of 'database_helper.dart';

const _nativeSaleScopeKey = 'native_sale_scope';
const nativeSalePostingEnabled = bool.fromEnvironment(
  'STORELY_NATIVE_SALE_POSTING',
);

const _nativeSaleTables = {
  'bills',
  'bill_items',
  'bill_payments',
  'stock_movements',
  'audit_log',
  'held_bills',
};

Future<Map<String, dynamic>?> _selectNativeSale(
  DatabaseExecutor txn,
  String shopId,
  String? owner,
  String deviceId,
  String snapshot,
) async {
  if (!nativeSalePostingEnabled || owner == null) return null;
  final scope = await txn.query(
    'cloud_sync_state',
    columns: ['value'],
    where: 'key = ? AND value = ?',
    whereArgs: [
      _nativeSaleScopeKey,
      jsonEncode([shopId, owner, deviceId]),
    ],
  );
  return scope.isEmpty ? null : nativeSaleRequest(snapshot);
}

/// A durable upload reservation for an accepted checkout.
class PendingNativeSale {
  final String attemptId;
  final String billUuid;
  final String request;

  PendingNativeSale(Map<String, Object?> row)
    : attemptId = row['attempt_id'] as String,
      billUuid = row['bill_uuid'] as String,
      request = row['native_sale_request'] as String;
}

extension DatabaseNativeSales on DatabaseHelper {
  Future<void> clearNativeSaleScope() =>
      clearCloudSyncState(_nativeSaleScopeKey);

  Future<void> updateNativeSaleScope(
    CheckoutScope scope, {
    required bool supported,
    required bool Function() isCurrent,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      if (!isCurrent()) throw StateError('Account changed during sale sync.');
      final value = jsonEncode([scope.shopId, scope.owner, scope.deviceId]);
      if (!supported) {
        await txn.delete(
          'cloud_sync_state',
          where: 'key = ? AND value = ?',
          whereArgs: [_nativeSaleScopeKey, value],
        );
        return;
      }
      await txn.insert('cloud_sync_state', {
        'key': _nativeSaleScopeKey,
        'value': value,
        'updated_at': _nowIso(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<PendingNativeSale>> pendingNativeSales(
    CheckoutScope scope,
  ) async {
    final db = await database;
    return db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      return (await txn.query(
        'checkout_acceptances',
        where:
            "shop_id = ? AND owner = ? AND native_sale_state IN ('pending', 'reconcile')",
        whereArgs: [scope.shopId, scope.owner],
        orderBy: 'bill_id ASC',
      )).map(PendingNativeSale.new).toList();
    });
  }

  Future<bool> hasReservedNativeSales(String shopId) async {
    final db = await database;
    return (await db.query(
      'checkout_acceptances',
      columns: ['attempt_id'],
      where: "shop_id = ? AND native_sale_state IN ('pending', 'reconcile')",
      whereArgs: [shopId],
      limit: 1,
    )).isNotEmpty;
  }

  /// Check the local invoice before sending and again before releasing the
  /// reservation. A local edit keeps the entire group out of row sync.
  Future<bool> checkNativeSale(
    CheckoutScope scope,
    PendingNativeSale sale, {
    required bool Function() isCurrent,
    bool acknowledged = false,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      if (!isCurrent()) throw StateError('Account changed during sale sync.');
      final accepted = (await txn.query(
        'checkout_acceptances',
        where: 'attempt_id = ? AND shop_id = ? AND owner = ? AND bill_uuid = ?',
        whereArgs: [sale.attemptId, scope.shopId, scope.owner, sale.billUuid],
      )).single;
      if (accepted['native_sale_request'] != sale.request) {
        throw StateError('The reserved sale request changed.');
      }
      if (accepted['native_sale_state'] != 'pending') return false;

      final snapshot =
          jsonDecode(accepted['posting_snapshot'] as String) as Map;
      final effects = <String, List>{
        'bills': [snapshot['invoice']],
        'bill_items': snapshot['items'] as List,
        'bill_payments': snapshot['payments'] as List,
        'stock_movements': snapshot['movements'] as List,
      };
      final matches = await _matchesNativeSale(txn, scope.shopId, effects);
      if (!isCurrent()) throw StateError('Account changed during sale sync.');
      if (matches && !acknowledged) return true;

      if (matches) {
        for (final entry in effects.entries) {
          for (final effect in entry.value.cast<Map>()) {
            await txn.update(
              entry.key,
              {'sync_dirty': 0},
              where: 'shop_id = ? AND uuid = ?',
              whereArgs: [scope.shopId, effect['uuid']],
            );
          }
        }
      }
      await txn.update(
        'checkout_acceptances',
        {'native_sale_state': matches ? 'posted' : 'reconcile'},
        where: 'attempt_id = ?',
        whereArgs: [sale.attemptId],
      );
      return matches;
    });
  }
}

Future<bool> _matchesNativeSale(
  Transaction txn,
  String shopId,
  Map<String, List> effects,
) async {
  for (final entry in effects.entries) {
    for (final effect in entry.value.cast<Map>()) {
      final rows = await txn.query(
        entry.key,
        where: 'shop_id = ? AND uuid = ?',
        whereArgs: [shopId, effect['uuid']],
      );
      if (rows.isEmpty ||
          effect.entries.any(
            (field) => rows.single[field.key] != field.value,
          )) {
        return false;
      }
    }
  }
  return true;
}

class _ReservedSaleRows {
  final bills = <Object?>{};
  final carts = <Object?>{};

  bool contains(String table, Map<String, Object?> row) => switch (table) {
    'bills' =>
      bills.contains(row['uuid']) || bills.contains(row['original_bill_uuid']),
    'bill_items' || 'bill_payments' => bills.contains(row['bill_uuid']),
    'stock_movements' =>
      row['source_document_type'] == 'bill' &&
          bills.contains(row['source_document_uuid']),
    'audit_log' =>
      row['entity_type'] == 'bill' && bills.contains(row['entity_uuid']),
    'held_bills' => carts.contains(row['uuid']),
    _ => false,
  };
}

Future<_ReservedSaleRows> _reservedSaleRows(
  DatabaseExecutor txn,
  String table,
  String shopId,
) async {
  final reserved = _ReservedSaleRows();
  if (!_nativeSaleTables.contains(table)) return reserved;
  final rows = await txn.query(
    'checkout_acceptances',
    columns: ['bill_uuid', 'posting_snapshot'],
    where: "shop_id = ? AND native_sale_state IN ('pending', 'reconcile')",
    whereArgs: [shopId],
  );
  if (rows.isEmpty) return reserved;
  if (table == 'held_bills') {
    for (final row in rows) {
      final snapshot = jsonDecode(row['posting_snapshot'] as String) as Map;
      reserved.carts.addAll(
        snapshot['consumed_cart_uuids'] as List? ?? const [],
      );
    }
  } else {
    reserved.bills.addAll(rows.map((row) => row['bill_uuid']));
    final notes = await txn.rawQuery(
      """
      SELECT b.uuid FROM bills b
      JOIN checkout_acceptances a
        ON a.shop_id = b.shop_id AND a.bill_uuid = b.original_bill_uuid
      WHERE b.shop_id = ? AND a.native_sale_state IN ('pending', 'reconcile')
    """,
      [shopId],
    );
    reserved.bills.addAll(notes.map((row) => row['uuid']));
  }
  return reserved;
}
