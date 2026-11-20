part of 'database_helper.dart';

/// Captured screen ownership; every delayed write rechecks it in its transaction.
class CheckoutScope {
  final String shopId;
  final String? owner;
  final String deviceId;
  const CheckoutScope(this.shopId, this.owner, this.deviceId);
}

class CheckoutCart {
  final HeldBill cart;
  final CheckoutScope scope;
  final int revision;
  final Map<String, dynamic> state;
  const CheckoutCart(this.cart, this.scope, this.revision, this.state);
}

mixin DatabaseCheckoutDrafts {
  Future<Database> get database;

  Future<CheckoutScope> captureCheckoutScope() async {
    final device = await DatabaseHelper.instance.localDeviceId();
    final db = await database;
    return db.transaction((txn) async {
      final owner = await _checkoutOwner(txn);
      return CheckoutScope(await _activeShopId(txn), owner, device);
    });
  }

  Future<CheckoutCart?> loadCheckoutCart(CheckoutScope scope) async {
    final db = await database;
    return db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      final rows = await txn.query(
        'held_bills',
        where:
            "kind = 'draft' AND shop_id = ? AND origin_device_id = ? AND deleted_at IS NULL AND (owner_user_id IS NULL OR owner_user_id = ?)",
        whereArgs: [scope.shopId, scope.deviceId, scope.owner ?? 'local'],
        limit: 1,
      );
      return rows.isEmpty ? null : _checkoutCart(txn, rows.single, scope);
    });
  }

  /// Updates an existing identity only. A consumed/tombstoned cart never revives.
  Future<CheckoutCart> writeCheckoutState(
    CheckoutCart expected,
    Map<String, dynamic> state,
  ) async {
    final db = await database;
    return db.transaction((txn) async {
      await _assertCheckoutScope(txn, expected.scope);
      final rows = await txn.query(
        'held_bills',
        where:
            "uuid = ? AND shop_id = ? AND origin_device_id = ? AND kind = 'draft' AND deleted_at IS NULL",
        whereArgs: [
          expected.cart.uuid,
          expected.scope.shopId,
          expected.scope.deviceId,
        ],
      );
      if (rows.isEmpty) {
        throw StateError(
          'This checkout was consumed or moved. Reopen the current cart.',
        );
      }
      final current = await _checkoutCart(txn, rows.single, expected.scope);
      if (current.revision != expected.revision ||
          HeldBill.encodeItems(current.cart.items) !=
              HeldBill.encodeItems(expected.cart.items)) {
        throw StateError(
          'This checkout changed elsewhere. Your entries have not overwritten it.',
        );
      }
      final payload = jsonEncode(state);
      final next = expected.revision + 1;
      await txn.insert('checkout_draft_state', {
        'cart_uuid': expected.cart.uuid,
        'shop_id': expected.scope.shopId,
        'owner': expected.scope.owner,
        'device_id': expected.scope.deviceId,
        'revision': next,
        'payload': payload,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return CheckoutCart(
        current.cart,
        current.scope,
        next,
        jsonDecode(payload) as Map<String, dynamic>,
      );
    });
  }

  /// New rows keep the cloud's immutable kind/origin columns unchanged.
  Future<CheckoutCart> parkCheckoutCart(CheckoutCart expected, String label) =>
      _moveCheckoutCart(
        expected.scope,
        expected.cart.id,
        'draft',
        'held',
        label,
        expected: expected,
      );

  Future<CheckoutCart> resumeCheckoutCart(
    CheckoutScope scope,
    int heldId, {
    CheckoutCart? active,
  }) => _moveCheckoutCart(
    scope,
    heldId,
    'held',
    'draft',
    'Unsaved bill',
    active: active,
  );

  Future<CheckoutCart> _moveCheckoutCart(
    CheckoutScope scope,
    int id,
    String from,
    String to,
    String label, {
    CheckoutCart? expected,
    CheckoutCart? active,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      final rows = await txn.query(
        'held_bills',
        where: 'id = ? AND shop_id = ? AND kind = ? AND deleted_at IS NULL',
        whereArgs: [id, scope.shopId, from],
      );
      if (rows.isEmpty) {
        throw StateError('This cart was already moved or deleted.');
      }
      final row = rows.single;
      if (row['origin_device_id'] != scope.deviceId ||
          (row['owner_user_id'] != null &&
              row['owner_user_id'] != scope.owner)) {
        throw StateError(
          'This is a read-only backup from another device or account.',
        );
      }
      final current = await _checkoutCart(txn, row, scope);
      if (expected != null &&
          (current.cart.uuid != expected.cart.uuid ||
              current.revision != expected.revision ||
              HeldBill.encodeItems(current.cart.items) !=
                  HeldBill.encodeItems(expected.cart.items))) {
        throw StateError('This cart changed before it could be held.');
      }
      if (current.state['pending'] != null) {
        throw StateError(
          'Recover the pending checkout before holding or moving it.',
        );
      }
      if (to == 'draft') {
        final activeRows = await txn.query(
          'held_bills',
          where:
              "kind = 'draft' AND shop_id = ? AND origin_device_id = ? AND deleted_at IS NULL AND (owner_user_id IS NULL OR owner_user_id = ?)",
          whereArgs: [scope.shopId, scope.deviceId, scope.owner ?? 'local'],
        );
        if (activeRows.isNotEmpty) {
          final row = activeRows.single;
          final old = await _checkoutCart(txn, row, scope);
          if (active == null ||
              old.cart.uuid != active.cart.uuid ||
              old.revision != active.revision ||
              HeldBill.encodeItems(old.cart.items) !=
                  HeldBill.encodeItems(active.cart.items) ||
              old.state['pending'] != null) {
            throw StateError(
              'The current cart changed or needs checkout recovery before swapping.',
            );
          }
          final parkedUuid = _newUuid();
          final now = _nowIso();
          await txn.insert(
            'held_bills',
            {
              ...row,
              'uuid': parkedUuid,
              'kind': 'held',
              'label': old.cart.label,
              'created_at': now,
              'updated_at': now,
              'sync_dirty': 1,
            }..remove('id'),
          );
          if (old.state.isNotEmpty) {
            await txn.insert('checkout_draft_state', {
              'cart_uuid': parkedUuid,
              'shop_id': scope.shopId,
              'owner': scope.owner,
              'device_id': scope.deviceId,
              'revision': 1,
              'payload': jsonEncode(old.state),
            });
          }
          await txn.update(
            'held_bills',
            {'deleted_at': now, 'updated_at': now},
            where: 'id = ?',
            whereArgs: [old.cart.id],
          );
          await txn.delete(
            'checkout_draft_state',
            where: 'cart_uuid = ?',
            whereArgs: [old.cart.uuid],
          );
        } else if (active != null) {
          throw StateError(
            'The current cart was already consumed before swapping.',
          );
        }
      }
      final now = _nowIso();
      final uuid = _newUuid();
      final newRow = {
        ...row,
        'uuid': uuid,
        'owner_user_id': scope.owner,
        'kind': to,
        'label': label,
        'created_at': now,
        'updated_at': now,
        'sync_dirty': 1,
        'deleted_at': null,
      }..remove('id');
      final newId = await txn.insert('held_bills', newRow);
      if (current.state.isNotEmpty) {
        await txn.insert('checkout_draft_state', {
          'cart_uuid': uuid,
          'shop_id': scope.shopId,
          'owner': scope.owner,
          'device_id': scope.deviceId,
          'revision': 1,
          'payload': jsonEncode(current.state),
        });
      }
      await txn.update(
        'held_bills',
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'checkout_draft_state',
        where: 'cart_uuid = ?',
        whereArgs: [row['uuid']],
      );
      notifyDatabaseChanged();
      return CheckoutCart(
        HeldBill.fromMap({...newRow, 'id': newId}),
        scope,
        current.state.isEmpty ? 0 : 1,
        current.state,
      );
    });
  }
}

Future<String?> _checkoutOwner(DatabaseExecutor txn) async {
  final rows = await txn.query(
    'cloud_sync_state',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: ['preference_owner'],
  );
  return rows.isEmpty ? null : rows.single['value'] as String?;
}

Future<void> _assertCheckoutScope(
  DatabaseExecutor txn,
  CheckoutScope scope,
) async {
  final devices = await txn.query(
    'cloud_sync_state',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: ['device_id'],
  );
  if (await _activeShopId(txn) != scope.shopId ||
      await _checkoutOwner(txn) != scope.owner ||
      devices.isEmpty ||
      devices.single['value'] != scope.deviceId) {
    throw StateError(
      'Checkout shop, account or device changed. Return to the original session.',
    );
  }
}

Future<CheckoutCart> _checkoutCart(
  DatabaseExecutor txn,
  Map<String, Object?> row,
  CheckoutScope scope,
) async {
  if (row['shop_id'] != scope.shopId ||
      row['origin_device_id'] != scope.deviceId ||
      (row['owner_user_id'] != null && row['owner_user_id'] != scope.owner)) {
    throw StateError(
      'Checkout cart belongs to another shop, account or device.',
    );
  }
  final metadata = await txn.query(
    'checkout_draft_state',
    where: 'cart_uuid = ?',
    whereArgs: [row['uuid']],
  );
  if (metadata.isEmpty) {
    return CheckoutCart(HeldBill.fromMap(row), scope, 0, const {});
  }
  final saved = metadata.single;
  if (saved['shop_id'] != scope.shopId ||
      saved['owner'] != scope.owner ||
      saved['device_id'] != scope.deviceId) {
    throw StateError('Checkout details belong to another account or device.');
  }
  final state = jsonDecode(saved['payload'] as String);
  if (state is! Map<String, dynamic> || state['version'] != 1) {
    throw const FormatException(
      'Unreadable saved checkout. Keep a backup before repairing it.',
    );
  }
  return CheckoutCart(
    HeldBill.fromMap(row),
    scope,
    saved['revision'] as int,
    state,
  );
}
