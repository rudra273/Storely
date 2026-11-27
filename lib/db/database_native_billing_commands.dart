part of 'database_helper.dart';

const _nativeBillingCommandsScopeKey = 'native_billing_commands_scope';

const _nativeBillingCommandReservedTables = {
  'bills',
  'bill_items',
  'bill_payments',
  'stock_movements',
  'audit_log',
};

/// A durable upload reservation for an offline billing follow-up command
/// (invoice payment, bill/credit-note cancellation, or credit note).
class PendingNativeBillingCommand {
  final String commandId;
  final String shopId;
  final String owner;
  final String deviceId;
  final String commandType;
  final String billUuid;
  final String targetUuid;
  final String requestJson;
  final String reservedUuidsJson;
  final String state;
  final String? lastError;
  final String createdAt;

  PendingNativeBillingCommand(Map<String, Object?> row)
    : commandId = row['command_id'] as String,
      shopId = row['shop_id'] as String,
      owner = row['owner'] as String,
      deviceId = row['device_id'] as String,
      commandType = row['command_type'] as String,
      billUuid = row['bill_uuid'] as String,
      targetUuid = row['target_uuid'] as String,
      requestJson = row['request_json'] as String,
      reservedUuidsJson = row['reserved_uuids_json'] as String,
      state = row['state'] as String,
      lastError = row['last_error'] as String?,
      createdAt = row['created_at'] as String;

  Map<String, dynamic> get decodedRequest =>
      Map<String, dynamic>.from(jsonDecode(requestJson) as Map);

  Map<String, List<String>> get decodedReservedUuids {
    final decoded = jsonDecode(reservedUuidsJson) as Map;
    return {
      for (final entry in decoded.entries)
        entry.key.toString(): [
          for (final item in (entry.value as List)) item.toString(),
        ],
    };
  }
}

Future<bool> _isNativeBillingCommandsEnabled(
  DatabaseExecutor txn,
  String shopId,
  String? owner,
  String deviceId,
) async {
  if (!nativeSalePostingEnabled || owner == null) return false;
  final scope = await txn.query(
    'cloud_sync_state',
    columns: ['value'],
    where: 'key = ? AND value = ?',
    whereArgs: [
      _nativeBillingCommandsScopeKey,
      jsonEncode([shopId, owner, deviceId, 1]),
    ],
  );
  return scope.isNotEmpty;
}

Future<({String owner, String deviceId})?> _currentNativeBillingCommandScope(
  DatabaseExecutor txn,
  String shopId,
) async {
  if (!nativeSalePostingEnabled) return null;
  final owner = await _checkoutOwner(txn);
  if (owner == null) return null;
  final deviceRows = await txn.query(
    'cloud_sync_state',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: ['device_id'],
    limit: 1,
  );
  final deviceId = deviceRows.isEmpty
      ? null
      : deviceRows.single['value']?.toString();
  if (deviceId == null || deviceId.isEmpty) return null;
  if (!await _isNativeBillingCommandsEnabled(txn, shopId, owner, deviceId)) {
    return null;
  }
  return (owner: owner, deviceId: deviceId);
}

Future<void> _enqueueNativeBillingCommand(
  DatabaseExecutor txn, {
  required String commandId,
  required String shopId,
  required String owner,
  required String deviceId,
  required String commandType,
  required String billUuid,
  required String targetUuid,
  required Map<String, dynamic> request,
  required Map<String, List<String>> reservedUuids,
}) async {
  await txn.insert('native_billing_commands', {
    'command_id': commandId,
    'shop_id': shopId,
    'owner': owner,
    'device_id': deviceId,
    'command_type': commandType,
    'bill_uuid': billUuid,
    'target_uuid': targetUuid,
    'request_json': jsonEncode(request),
    'reserved_uuids_json': jsonEncode(reservedUuids),
    'state': 'pending',
    'last_error': null,
    'created_at': _nowIso(),
  });
}

String _formatNativeMoney(double amount) => decimalTextFromScaled(
  decimalScaledInteger(amount.toString(), scale: 2),
  scale: 2,
  fixed: true,
);

String _formatNativeQuantity(double quantity) => decimalTextFromScaled(
  decimalScaledInteger(quantity.toString(), scale: 3),
  scale: 3,
);

extension DatabaseNativeBillingCommands on DatabaseHelper {
  Future<void> clearNativeBillingCommandsScope() =>
      clearCloudSyncState(_nativeBillingCommandsScopeKey);

  Future<void> updateNativeBillingCommandsScope(
    CheckoutScope scope, {
    required bool supported,
    required bool Function() isCurrent,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      if (!isCurrent()) {
        throw StateError('Account changed during billing command sync.');
      }
      final identity = [scope.shopId, scope.owner, scope.deviceId];
      final value = jsonEncode([...identity, 1]);
      if (!supported) {
        await txn.delete(
          'cloud_sync_state',
          where: 'key = ? AND value IN (?, ?)',
          whereArgs: [
            _nativeBillingCommandsScopeKey,
            jsonEncode(identity),
            value,
          ],
        );
        return;
      }
      await txn.insert('cloud_sync_state', {
        'key': _nativeBillingCommandsScopeKey,
        'value': value,
        'updated_at': _nowIso(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<PendingNativeBillingCommand>> pendingNativeBillingCommands(
    CheckoutScope scope,
  ) async {
    final db = await database;
    return db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      return (await txn.query(
        'native_billing_commands',
        where: "shop_id = ? AND owner = ? AND state = 'pending'",
        whereArgs: [scope.shopId, scope.owner],
        orderBy: 'rowid ASC',
      )).map(PendingNativeBillingCommand.new).toList();
    });
  }

  Future<bool> hasReservedNativeBillingCommands(String shopId) async {
    final db = await database;
    return (await db.query(
      'native_billing_commands',
      columns: ['command_id'],
      where: "shop_id = ? AND state = 'pending'",
      whereArgs: [shopId],
      limit: 1,
    )).isNotEmpty;
  }

  Future<void> acknowledgeNativeBillingCommand(
    CheckoutScope scope,
    PendingNativeBillingCommand cmd, {
    required bool Function() isCurrent,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      if (!isCurrent()) {
        throw StateError('Account changed during billing command sync.');
      }
      final rows = await txn.query(
        'native_billing_commands',
        where:
            "command_id = ? AND shop_id = ? AND owner = ? AND state = 'pending'",
        whereArgs: [cmd.commandId, scope.shopId, scope.owner],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('The reserved billing command could not be found.');
      }
      for (final entry in cmd.decodedReservedUuids.entries) {
        if (!_nativeBillingCommandReservedTables.contains(entry.key)) continue;
        for (final uuid in entry.value) {
          await txn.update(
            entry.key,
            {'sync_dirty': 0},
            where: 'shop_id = ? AND uuid = ?',
            whereArgs: [scope.shopId, uuid],
          );
        }
      }
      if (!isCurrent()) {
        throw StateError('Account changed during billing command sync.');
      }
      await txn.update(
        'native_billing_commands',
        {'state': 'posted', 'last_error': null},
        where: 'command_id = ?',
        whereArgs: [cmd.commandId],
      );
    });
  }

  Future<void> recordNativeBillingCommandError(
    String commandId,
    String error,
  ) async {
    final db = await database;
    await db.update(
      'native_billing_commands',
      {'last_error': error},
      where: "command_id = ? AND state = 'pending'",
      whereArgs: [commandId],
    );
  }
}
