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
];

mixin DatabaseSync {
  Future<Database> get database;
  Future<void> rebuildAllProductQuantityCaches(DatabaseExecutor executor);

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

  Future<void> cloudImportRows(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final activeShopId = await _activeShopId(txn);
      for (final row in rows) {
        final localMap = await _fromCloudMap(txn, table, row);
        if (localMap == null) continue;
        // Defense-in-depth tenant isolation: never write a row that belongs to
        // a different shop into the local database. The pull query already
        // filters by shop_id, but a server-side RLS gap or a shared cloud
        // project must not be able to leak another shop's data onto this
        // device (and from there back up on the next push).
        if (!_belongsToActiveShop(table, localMap, activeShopId)) continue;
        if (table == 'app_settings') {
          await _upsertAppSetting(txn, localMap);
          continue;
        }
        final uuid = localMap['uuid']?.toString();
        if (uuid == null || uuid.isEmpty) continue;
        await _upsertUuidRow(txn, table, uuid, localMap);
      }
      if (table == 'stock_movements') {
        await rebuildAllProductQuantityCaches(txn);
      }
    });
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
    final map = Map<String, dynamic>.from(row)..remove('id');
    switch (table) {
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
        map.remove('customer_id');
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
    final map = Map<String, dynamic>.from(row)..remove('id');
    switch (table) {
      case 'products':
        map
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
          ..remove('source_document_id');
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
      columns: ['id', 'updated_at'],
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
    final localUpdatedAt = existing.single['updated_at']?.toString();
    final cloudUpdatedAt = map['updated_at']?.toString();
    if (!_cloudIsNewer(localUpdatedAt, cloudUpdatedAt)) return;
    await executor.update(
      table,
      map..remove('id'),
      where: 'id = ?',
      whereArgs: [existing.single['id']],
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

    // bills have a live-row unique index on (shop_id, bill_number)
    // (idx_bills_shop_bill_number) — a collision means the same invoice number
    // exists locally under a different uuid (e.g. the bill was created before
    // cloud sync, then pulled back with the cloud's uuid). Merge onto that
    // single local bill and re-point its children's bill_uuid.
    if (table == 'bills') {
      final billNumber = map['bill_number']?.toString();
      if (billNumber == null || billNumber.isEmpty) {
        throw StateError(
          'Unresolvable unique conflict importing bills without bill_number '
          '(uuid=${map['uuid']})',
        );
      }
      await _mergeBillRow(
        executor,
        map,
        shopId: shopId,
        billNumber: billNumber,
      );
      return;
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
  /// cloud copy is newer than the local one.
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
    if (!_cloudIsNewer(localUpdatedAt, cloudUpdatedAt)) return;
    await executor.update(
      table,
      map..remove('id'),
      where: 'id = ?',
      whereArgs: [matches.single['id']],
    );
  }

  /// Merge a pulled cloud bill onto the single live local bill that shares its
  /// (shop_id, bill_number). Like [_mergeMatchingRow] this only proceeds when
  /// there is exactly one live match and the cloud copy is newer, but it must
  /// also re-point the local bill's children: bill_items and bill_payments
  /// reference the bill by bill_uuid, so adopting the cloud uuid would orphan
  /// them otherwise. bill_id links are preserved because the local row keeps
  /// its id.
  Future<void> _mergeBillRow(
    DatabaseExecutor executor,
    Map<String, dynamic> map, {
    required String shopId,
    required String billNumber,
  }) async {
    final matches = await executor.query(
      'bills',
      columns: ['id', 'uuid', 'updated_at'],
      where: 'shop_id = ? AND bill_number = ? AND deleted_at IS NULL',
      whereArgs: [shopId, billNumber],
      limit: 2,
    );
    // Ambiguous (more than one candidate) or none: do not guess.
    if (matches.length != 1) return;
    final localUpdatedAt = matches.single['updated_at']?.toString();
    final cloudUpdatedAt = map['updated_at']?.toString();
    if (!_cloudIsNewer(localUpdatedAt, cloudUpdatedAt)) return;

    final localId = matches.single['id'];
    final oldUuid = matches.single['uuid']?.toString();
    final newUuid = map['uuid']?.toString();

    await executor.update(
      'bills',
      map..remove('id'),
      where: 'id = ?',
      whereArgs: [localId],
    );

    // Re-point children from the old local uuid to the adopted cloud uuid so
    // bill_uuid joins (payment refs, the bills↔payments JOIN) keep resolving.
    if (oldUuid != null &&
        newUuid != null &&
        oldUuid.isNotEmpty &&
        oldUuid != newUuid) {
      for (final childTable in const ['bill_items', 'bill_payments']) {
        await executor.update(
          childTable,
          {'bill_uuid': newUuid},
          where: 'bill_uuid = ?',
          whereArgs: [oldUuid],
        );
      }
    }
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
