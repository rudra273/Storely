part of 'database_helper.dart';

const storelyCloudTables = [
  'app_settings',
  'bill_settings',
  'categories',
  'units',
  'suppliers',
  'customers',
  'products',
  'invoice_series',
  'bills',
  'bill_items',
  'bill_payments',
  'stock_movements',
  'expenses',
  'audit_log',
  'held_bills',
  'user_preferences',
];

/// Billing records whose deletion (cancellation) is final: a stale copy from
/// another device can never bring them back. Mirrors the server rule in
/// the API database sticky-cancellation migration.
const _stickyDeleteTables = {
  'bills',
  'bill_items',
  'bill_payments',
  'stock_movements',
  'held_bills',
};

/// A row that could not be applied locally or uploaded. It is skipped (and
/// kept queued if it was an upload) instead of blocking the whole sync.
class SyncConflict {
  final String table;
  final String key;
  final String message;

  const SyncConflict({
    required this.table,
    required this.key,
    required this.message,
  });

  Map<String, String> toJson() => {
    'table': table,
    'key': key,
    'message': message,
  };

  factory SyncConflict.fromJson(Map<String, dynamic> json) => SyncConflict(
    table: json['table']?.toString() ?? '',
    key: json['key']?.toString() ?? '',
    message: json['message']?.toString() ?? '',
  );

  @override
  String toString() => '$table/$key: $message';
}

mixin DatabaseSync {
  Future<Database> get database;
  Future<void> rebuildAllProductQuantityCaches(DatabaseExecutor executor);
  Future<void> _updateBillPaymentSummary(
    DatabaseExecutor executor,
    int billId,
    String billUuid,
  );

  static const _conflictsKey = 'sync_conflicts';
  static const _deviceIdKey = 'device_id';

  Future<void> bindCloudUserData(
    String userId, {
    bool bindPreferences = true,
  }) async {
    final db = await database;
    final shop = await _activeShopId(db);
    final device = await localDeviceId();
    await setCloudSyncState('preference_owner', userId);
    await db.update(
      'held_bills',
      {'owner_user_id': userId, 'updated_at': _nowIso()},
      where: 'shop_id = ? AND origin_device_id = ? AND owner_user_id IS NULL',
      whereArgs: [shop, device],
    );
    if (!bindPreferences) return;
    final pending = await db.query(
      'user_preferences',
      where: "shop_id = ? AND owner_user_id = 'local'",
      whereArgs: [shop],
    );
    for (final row in pending) {
      final key = row['key'] as String;
      await db.insert('user_preferences', {
        ...row,
        'id': null,
        'uuid': '$shop:$userId:$key',
        'owner_user_id': userId,
        'sync_dirty': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.delete(
        'user_preferences',
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  Future<void> savePortablePreference(
    String key,
    String value, {
    bool onlyIfMissing = false,
  }) async {
    final db = await database;
    final shop = await _activeShopId(db);
    final user = await getCloudSyncState('preference_owner') ?? 'local';
    final rows = await db.query(
      'user_preferences',
      where: 'shop_id = ? AND owner_user_id = ? AND key = ?',
      whereArgs: [shop, user, key],
    );
    if (rows.isNotEmpty && (onlyIfMissing || rows.single['value'] == value)) {
      return;
    }
    final now = _nowIso();
    if (rows.isEmpty) {
      await db.insert('user_preferences', {
        'uuid': '$shop:$user:$key',
        'shop_id': shop,
        'owner_user_id': user,
        'key': key,
        'value': value,
        'created_at': now,
        'updated_at': now,
      });
    } else {
      await db.update(
        'user_preferences',
        {'value': value, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [rows.single['id']],
      );
    }
    notifyDatabaseChanged();
  }

  /// Permanent id of this install, used to register its bill-number letter.
  Future<String> localDeviceId() async {
    final existing = await getCloudSyncState(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _newUuid();
    await setCloudSyncState(_deviceIdKey, id);
    return id;
  }

  Future<bool> hasDeviceCode(String shopId) async =>
      await getCloudSyncState(_deviceCodeKey(shopId)) != null;

  Future<void> setDeviceCode(String shopId, String code) =>
      setCloudSyncState(_deviceCodeKey(shopId), code);

  /// Rows changed on this device and not yet uploaded, in cloud shape.
  Future<List<Map<String, dynamic>>> cloudDirtyRows(String table) async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final rows = await db.query(
      table,
      where: table == 'shops'
          ? 'sync_dirty = 1 AND uuid = ?'
          : 'sync_dirty = 1 AND shop_id = ?',
      whereArgs: [shopId],
      orderBy: 'updated_at ASC',
    );
    final owner = await getCloudSyncState('preference_owner');
    return [
      for (final row in rows)
        if ((table != 'held_bills' && table != 'user_preferences') ||
            (row['owner_user_id'] != null &&
                (owner == null || row['owner_user_id'] == owner)))
          await _toCloudMap(db, table, row),
    ];
  }

  /// Marks uploaded rows as in sync — unless they were edited again while
  /// the upload was in flight (updated_at moved on), which keeps them queued.
  Future<void> markCloudRowsClean(
    String table,
    List<Map<String, dynamic>> uploaded,
  ) async {
    if (uploaded.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final row in uploaded) {
        if (table == 'app_settings') {
          await txn.update(
            table,
            {'sync_dirty': 0},
            where: 'shop_id = ? AND key = ? AND updated_at = ?',
            whereArgs: [row['shop_id'], row['key'], row['updated_at']],
          );
        } else {
          await txn.update(
            table,
            {'sync_dirty': 0},
            where: 'uuid = ? AND updated_at = ?',
            whereArgs: [row['uuid'], row['updated_at']],
          );
        }
      }
    });
  }

  /// Stops uploading one row (see `CloudSyncEngine.useCloudCopy`).
  Future<void> markRowSynced(String table, String key) async {
    if (!['shops', ...storelyCloudTables].contains(table)) return;
    final db = await database;
    await db.update(
      table,
      // Older than any real edit, so the cloud's copy wins when pulled.
      {'sync_dirty': 0, 'updated_at': DatabaseHelper._placeholderTimestamp},
      where: table == 'app_settings' ? 'key = ?' : 'uuid = ?',
      whereArgs: [key],
    );
  }

  /// "Start fresh" first sync: existing local rows are not uploaded.
  Future<void> markAllCloudRowsClean() async {
    final db = await database;
    final owner = await getCloudSyncState('preference_owner') ?? 'local';
    await db.transaction((txn) async {
      for (final table in ['shops', ...storelyCloudTables]) {
        final private = table == 'held_bills' || table == 'user_preferences';
        await txn.update(
          table,
          {'sync_dirty': 0},
          where: private
              ? 'owner_user_id IS NULL OR owner_user_id = ? OR owner_user_id = ?'
              : null,
          whereArgs: private ? [owner, 'local'] : null,
        );
      }
    });
  }

  /// Rows changed on this device and not uploaded yet, per table.
  Future<Map<String, int>> pendingSyncCounts() async {
    final db = await database;
    final counts = <String, int>{};
    final owner = await getCloudSyncState('preference_owner') ?? 'local';
    for (final table in ['shops', ...storelyCloudTables]) {
      final private = table == 'held_bills' || table == 'user_preferences';
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM $table WHERE sync_dirty = 1'
        '${private ? " AND (owner_user_id IS NULL OR owner_user_id = ? OR owner_user_id = ?)" : ""}',
        private ? [owner, 'local'] : null,
      );
      final n = (rows.first['n'] as num).toInt();
      if (n > 0) counts[table] = n;
    }
    return counts;
  }

  /// Bills (and credit notes) not uploaded yet.
  Future<Set<String>> unsyncedBillUuids() async {
    final db = await database;
    final rows = await db.query(
      'bills',
      columns: ['uuid'],
      where: 'sync_dirty = 1',
    );
    return {for (final r in rows) r['uuid'] as String};
  }

  Future<void> saveSyncConflicts(List<SyncConflict> conflicts) async {
    await setCloudSyncState(
      _conflictsKey,
      conflicts.isEmpty
          ? null
          : jsonEncode([for (final c in conflicts) c.toJson()]),
    );
  }

  Future<List<SyncConflict>> getSyncConflicts() async {
    final raw = await getCloudSyncState(_conflictsKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw) as List;
    return [
      for (final item in decoded)
        SyncConflict.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<String?> getCloudSyncState(String key) async {
    final db = await database;
    final rows = await db.query(
      'cloud_sync_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String?;
  }

  Future<void> setCloudSyncState(String key, String? value) async {
    final db = await database;
    await db.insert('cloud_sync_state', {
      'key': key,
      'value': value,
      'updated_at': _nowIso(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Removes a single cloud-sync-state key (e.g. the last-sync watermark). Only
  /// touches the one key — migration markers in this table are left intact.
  Future<void> clearCloudSyncState(String key) async {
    final db = await database;
    await db.delete('cloud_sync_state', where: 'key = ?', whereArgs: [key]);
  }

  Future<List<Map<String, dynamic>>> cloudExportRows(
    String table, {
    String? updatedAfter,
  }) async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (table == 'shops') {
      whereParts.add('uuid = ?');
      whereArgs.add(shopId);
    } else if (table != 'profiles' && table != 'cloud_sync_state') {
      whereParts.add('shop_id = ?');
      whereArgs.add(shopId);
    }
    if (updatedAfter != null) {
      whereParts.add('updated_at > ?');
      whereArgs.add(updatedAfter);
    }
    final rows = await db.query(
      table,
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'updated_at ASC',
    );
    final mapped = <Map<String, dynamic>>[];
    for (final row in rows) {
      mapped.add(await _toCloudMap(db, table, row));
    }
    return mapped;
  }

  Future<bool> hasLocalBusinessDataForCloud() async {
    final db = await database;
    final shopId = await _activeShopId(db);
    for (final table in [
      'categories',
      'suppliers',
      'customers',
      'products',
      'bills',
      'bill_items',
      'bill_payments',
      'stock_movements',
      'expenses',
      'held_bills',
    ]) {
      final rows = await db.query(
        table,
        columns: ['rowid'],
        where: 'shop_id = ? AND deleted_at IS NULL',
        whereArgs: [shopId],
        limit: 1,
      );
      if (rows.isNotEmpty) return true;
    }
    return false;
  }

  /// Applies pulled cloud rows. A row that cannot be applied (e.g. a unique
  /// clash with a different local record) is reported as a conflict and
  /// skipped; it never aborts the rest of the page.
  Future<List<SyncConflict>> cloudImportRows(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final conflicts = <SyncConflict>[];
    final privateOwner = (table == 'held_bills' || table == 'user_preferences')
        ? await getCloudSyncState('preference_owner')
        : null;
    final db = await database;
    await db.transaction((txn) async {
      final activeShopId = await _activeShopId(txn);
      final touchedBillUuids = <String>{};
      for (final row in rows) {
        final key = table == 'app_settings'
            ? row['key']?.toString() ?? ''
            : row['uuid']?.toString() ?? '';
        try {
          final localMap = await _fromCloudMap(txn, table, row);
          if (localMap == null) continue;
          // Defense-in-depth tenant isolation: never write a row that belongs
          // to a different shop into the local database. The pull query
          // already filters by shop_id, but a server-side RLS gap or a shared
          // cloud project must not be able to leak another shop's data onto
          // this device (and from there back up on the next push).
          if (!_belongsToActiveShop(table, localMap, activeShopId)) continue;
          if ((table == 'held_bills' || table == 'user_preferences') &&
              (privateOwner == null ||
                  localMap['owner_user_id'] != privateOwner)) {
            continue;
          }
          if (table == 'app_settings') {
            await _upsertAppSetting(txn, localMap);
            continue;
          }
          if (key.isEmpty) continue;
          await _upsertUuidRow(txn, table, key, localMap);
          if (table == 'bills') touchedBillUuids.add(key);
          if (table == 'bill_payments') {
            final billUuid = row['bill_uuid']?.toString();
            if (billUuid != null) touchedBillUuids.add(billUuid);
          }
        } on DatabaseException catch (error) {
          conflicts.add(
            SyncConflict(table: table, key: key, message: '$error'),
          );
        } on FormatException catch (error) {
          conflicts.add(
            SyncConflict(table: table, key: key, message: error.message),
          );
        } on StateError catch (error) {
          conflicts.add(
            SyncConflict(table: table, key: key, message: error.message),
          );
        }
      }
      // Derived data is recomputed locally, never taken from another device.
      if (table == 'stock_movements' || table == 'products') {
        await rebuildAllProductQuantityCaches(txn);
      }
      for (final billUuid in touchedBillUuids) {
        final bill = await txn.query(
          'bills',
          columns: ['id'],
          where: 'uuid = ?',
          whereArgs: [billUuid],
          limit: 1,
        );
        if (bill.isNotEmpty) {
          await _updateBillPaymentSummary(
            txn,
            bill.single['id'] as int,
            billUuid,
          );
        }
      }
    });
    return conflicts;
  }

  /// True when [map] either has no tenant column or its `shop_id` matches the
  /// active shop. Rows for any other shop are rejected outright.
  bool _belongsToActiveShop(
    String table,
    Map<String, dynamic> map,
    String activeShopId,
  ) {
    if (!map.containsKey('shop_id')) return true;
    final rowShopId = map['shop_id']?.toString();
    if (rowShopId == null || rowShopId.isEmpty) return false;
    return rowShopId == activeShopId;
  }

  Future<Map<String, dynamic>> _toCloudMap(
    DatabaseExecutor executor,
    String table,
    Map<String, dynamic> row,
  ) async {
    final map = Map<String, dynamic>.from(row)
      ..remove('id')
      ..remove('sync_dirty');
    switch (table) {
      case 'held_bills':
        final items = <Map<String, dynamic>>[];
        for (final value in jsonDecode(row['items_json'] as String) as List) {
          final item = Map<String, dynamic>.from(value as Map);
          item['product_uuid'] ??= await _uuidForId(
            executor,
            'products',
            item['product_id'] as int?,
          );
          item.remove('id');
          item.remove('product_id');
          item.remove('bill_id');
          items.add(item);
        }
        map['items_json'] = jsonEncode(items);
        break;
      case 'products':
        map
          ..remove('category_id')
          ..remove('supplier_id')
          ..remove('unit_id')
          ..['category_uuid'] = await _uuidForId(
            executor,
            'categories',
            row['category_id'] as int?,
          )
          ..['supplier_uuid'] = await _uuidForId(
            executor,
            'suppliers',
            row['supplier_id'] as int?,
          )
          ..['unit_uuid'] = await _uuidForId(
            executor,
            'units',
            row['unit_id'] as int?,
          );
        break;
      case 'bills':
        map
          ..remove('customer_id')
          ..['customer_uuid'] =
              await _uuidForId(
                executor,
                'customers',
                row['customer_id'] as int?,
              ) ??
              row['customer_uuid'];
        break;
      case 'bill_items':
        map
          ..remove('bill_id')
          ..remove('product_id');
        break;
      case 'stock_movements':
        map
          ..remove('product_id')
          ..remove('supplier_id')
          ..remove('source_document_id')
          ..['supplier_uuid'] =
              map['supplier_uuid'] ??
              await _uuidForId(
                executor,
                'suppliers',
                row['supplier_id'] as int?,
              );
        break;
    }
    return map;
  }

  Future<Map<String, dynamic>?> _fromCloudMap(
    DatabaseExecutor executor,
    String table,
    Map<String, dynamic> row,
  ) async {
    final map = Map<String, dynamic>.from(row)
      ..remove('id')
      ..remove('server_updated_at')
      ..['sync_dirty'] = DatabaseSchema.syncDirtyFromCloud;
    switch (table) {
      case 'held_bills':
        final items = <Map<String, dynamic>>[];
        for (final value in jsonDecode(row['items_json'] as String) as List) {
          final item = Map<String, dynamic>.from(value as Map);
          item['product_id'] = await _idForUuid(
            executor,
            'products',
            item['product_uuid']?.toString(),
          );
          items.add(item);
        }
        map['items_json'] = jsonEncode(items);
        break;
      case 'products':
        map
          // Stock is rebuilt from the synced ledger, never copied.
          ..remove('quantity_cache')
          ..remove('category_uuid')
          ..remove('supplier_uuid')
          ..remove('unit_uuid')
          ..['category_id'] = await _idForUuid(
            executor,
            'categories',
            row['category_uuid']?.toString(),
          )
          ..['supplier_id'] = await _idForUuid(
            executor,
            'suppliers',
            row['supplier_uuid']?.toString(),
          )
          ..['unit_id'] = await _idForUuid(
            executor,
            'units',
            row['unit_uuid']?.toString(),
          );
        break;
      case 'invoice_series':
        // Sequence counters are per device (numbers carry a device letter).
        map
          ..remove('next_sequence')
          ..remove('last_sequence_key');
        break;
      case 'bills':
        map['customer_id'] = await _idForUuid(
          executor,
          'customers',
          row['customer_uuid']?.toString(),
        );
        break;
      case 'bill_items':
        final billId = await _idForUuid(
          executor,
          'bills',
          row['bill_uuid']?.toString(),
        );
        if (billId == null) return null;
        map
          ..['bill_id'] = billId
          ..['product_id'] = await _idForUuid(
            executor,
            'products',
            row['product_uuid']?.toString(),
          );
        break;
      case 'stock_movements':
        final productId = await _idForUuid(
          executor,
          'products',
          row['product_uuid']?.toString(),
        );
        if (productId == null) return null;
        map
          ..['product_id'] = productId
          ..['supplier_id'] = await _idForUuid(
            executor,
            'suppliers',
            row['supplier_uuid']?.toString(),
          )
          ..['source_document_id'] = row['source_document_type'] == 'bill'
              ? await _idForUuid(
                  executor,
                  'bills',
                  row['source_document_uuid']?.toString(),
                )
              : null;
        break;
    }
    return map;
  }

  Future<void> _upsertUuidRow(
    DatabaseExecutor executor,
    String table,
    String uuid,
    Map<String, dynamic> map,
  ) async {
    final existing = await executor.query(
      table,
      columns: ['id', 'updated_at', 'deleted_at'],
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (existing.isEmpty) {
      // No row with this UUID locally. Try inserting.
      try {
        await executor.insert(table, map..remove('id'));
      } on DatabaseException catch (e) {
        if (e.isUniqueConstraintError()) {
          await _mergeOnUniqueConflict(executor, table, map);
        } else {
          rethrow;
        }
      }
      return;
    }
    final local = existing.single;
    final localDeleted = local['deleted_at'] != null;
    final cloudDeleted = map['deleted_at'] != null;
    // Cancelled billing records stay cancelled.
    if (_stickyDeleteTables.contains(table) && localDeleted && !cloudDeleted) {
      return;
    }
    final localUpdatedAt = local['updated_at']?.toString();
    final cloudUpdatedAt = map['updated_at']?.toString();
    if (!_cloudIsNewer(localUpdatedAt, cloudUpdatedAt)) {
      // An older copy still carries a deletion: apply just that.
      if (cloudDeleted && !localDeleted) {
        await executor.update(
          table,
          {
            'deleted_at': map['deleted_at'],
            if (table == 'bills') ...{
              'lifecycle_status': map['lifecycle_status'],
              'cancelled_at': map['cancelled_at'],
              'cancel_reason': map['cancel_reason'],
            },
          },
          where: 'id = ?',
          whereArgs: [local['id']],
        );
      }
      return;
    }
    await executor.update(
      table,
      map..remove('id'),
      where: 'id = ?',
      whereArgs: [local['id']],
    );
  }

  /// Insert failed because a cloud row's UUID is new locally but collides with
  /// an existing local row on some other unique constraint. We merge ONLY when
  /// we can unambiguously identify the single live local row that represents the
  /// same entity, and only when the cloud copy is newer. Otherwise we rethrow
  /// rather than risk overwriting an unrelated record.
  Future<void> _mergeOnUniqueConflict(
    DatabaseExecutor executor,
    String table,
    Map<String, dynamic> map,
  ) async {
    final shopId = map['shop_id']?.toString();
    if (shopId == null || shopId.isEmpty) return;

    // bill_settings is unique per shop (partial index on shop_id where not
    // deleted), so the colliding row is the shop's single live settings row.
    if (table == 'bill_settings') {
      await _mergeMatchingRow(
        executor,
        table,
        map,
        where: 'shop_id = ? AND deleted_at IS NULL',
        whereArgs: [shopId],
      );
      return;
    }

    // categories and units have a live-row unique index on (shop_id, name)
    // (idx_categories_shop_name / idx_units_shop_name), so a name collision
    // identifies the same entity. suppliers/products are deliberately excluded:
    // suppliers have no business unique key (name index is non-unique) and
    // products collide on product_code/barcode, not name.
    const nameMergeTables = {'categories', 'units'};
    if (nameMergeTables.contains(table)) {
      final name = map['name']?.toString();
      if (name == null) return;
      await _mergeMatchingRow(
        executor,
        table,
        map,
        where: 'shop_id = ? AND name = ? COLLATE NOCASE AND deleted_at IS NULL',
        whereArgs: [shopId, name],
      );
      return;
    }

    // A different bill with the same number already exists here. Two bills
    // are never merged by number (that mixed up two real sales); with a
    // device letter in every number this only happens for bills made before
    // the device joined the shop. Report it instead.
    if (table == 'bills') {
      throw StateError(
        'Bill number ${map['bill_number']} already used by another bill on '
        'this device',
      );
    }

    // customers have a live-row unique index on (shop_id, phone)
    // (idx_customers_shop_phone) — that, not name, is what an insert collides on.
    if (table == 'customers') {
      final phone = map['phone']?.toString();
      if (phone == null || phone.trim().isEmpty) {
        throw StateError(
          'Unresolvable unique conflict importing customers without phone '
          '(uuid=${map['uuid']})',
        );
      }
      await _mergeMatchingRow(
        executor,
        table,
        map,
        where: 'shop_id = ? AND phone = ? AND deleted_at IS NULL',
        whereArgs: [shopId, phone],
      );
      return;
    }

    // Unknown unique conflict (e.g. product barcode/code, supplier with no
    // business key): no safe merge key, so surface it instead of silently
    // clobbering the wrong row.
    throw StateError(
      'Unresolvable unique conflict importing $table (uuid=${map['uuid']})',
    );
  }

  /// Update the single live local row identified by [where]/[whereArgs] to adopt
  /// the cloud row's UUID and data — but only if it is the only match and the
  /// cloud copy is newer than the local one. Customers always adopt the cloud
  /// identity for the same phone, retaining newer local fields for upload.
  Future<void> _mergeMatchingRow(
    DatabaseExecutor executor,
    String table,
    Map<String, dynamic> map, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final matches = await executor.query(
      table,
      columns: ['id', 'updated_at'],
      where: where,
      whereArgs: whereArgs,
      limit: 2,
    );
    // Ambiguous (more than one candidate) or none: do not guess.
    if (matches.length != 1) return;
    final localUpdatedAt = matches.single['updated_at']?.toString();
    final cloudUpdatedAt = map['updated_at']?.toString();
    if (!_cloudIsNewer(localUpdatedAt, cloudUpdatedAt)) {
      if (table == 'customers') {
        // The cloud owns the UUID for an existing phone number. Keep newer
        // local details dirty, but upload them against that canonical identity.
        await executor.update(
          table,
          {'uuid': map['uuid']},
          where: 'id = ?',
          whereArgs: [matches.single['id']],
        );
      }
      return;
    }
    await executor.update(
      table,
      map..remove('id'),
      where: 'id = ?',
      whereArgs: [matches.single['id']],
    );
  }

  Future<void> _upsertAppSetting(
    DatabaseExecutor executor,
    Map<String, dynamic> map,
  ) async {
    final key = map['key']?.toString();
    final shopId = map['shop_id']?.toString();
    if (key == null || shopId == null) return;
    final existing = await executor.query(
      'app_settings',
      columns: ['updated_at'],
      where: 'shop_id = ? AND key = ?',
      whereArgs: [shopId, key],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final localUpdatedAt = existing.single['updated_at']?.toString();
      final cloudUpdatedAt = map['updated_at']?.toString();
      if (!_cloudIsNewer(localUpdatedAt, cloudUpdatedAt)) return;
    }
    await executor.insert(
      'app_settings',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

bool _cloudIsNewer(String? localUpdatedAt, String? cloudUpdatedAt) {
  if (cloudUpdatedAt == null || cloudUpdatedAt.isEmpty) return false;
  if (localUpdatedAt == null || localUpdatedAt.isEmpty) return true;
  final local = DateTime.tryParse(localUpdatedAt);
  final cloud = DateTime.tryParse(cloudUpdatedAt);
  if (local != null && cloud != null) return cloud.isAfter(local);
  return cloudUpdatedAt.compareTo(localUpdatedAt) > 0;
}

Future<String?> _uuidForId(
  DatabaseExecutor executor,
  String table,
  int? id,
) async {
  if (id == null) return null;
  final rows = await executor.query(
    table,
    columns: ['uuid'],
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single['uuid'] as String?;
}

Future<int?> _idForUuid(
  DatabaseExecutor executor,
  String? table,
  String? uuid,
) async {
  if (table == null || uuid == null || uuid.isEmpty) return null;
  final rows = await executor.query(
    table,
    columns: ['id'],
    where: 'uuid = ?',
    whereArgs: [uuid],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single['id'] as int?;
}

String _deviceCodeKey(String shopId) => 'device_code:$shopId';

/// This device's bill-number letter for [shopId]: '' until the cloud assigns
/// one (and always '' for a shop without cloud sync).
Future<String> _deviceCodeFor(DatabaseExecutor executor, String shopId) async {
  final rows = await executor.query(
    'cloud_sync_state',
    columns: ['value'],
    where: 'key = ?',
    whereArgs: [_deviceCodeKey(shopId)],
    limit: 1,
  );
  return rows.isEmpty ? '' : rows.single['value']?.toString() ?? '';
}
