part of 'database_helper.dart';

const storelyCloudTables = [
  'shops',
  'app_settings',
  'categories',
  'units',
  'suppliers',
  'customers',
  'products',
  'bills',
  'bill_items',
  'stock_movements',
];

mixin DatabaseSync {
  Future<Database> get database;

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

  Future<List<Map<String, dynamic>>> cloudExportRows(
    String table, {
    String? updatedAfter,
  }) async {
    final db = await database;
    final rows = await db.query(
      table,
      where: updatedAfter == null ? null : 'updated_at > ?',
      whereArgs: updatedAfter == null ? null : [updatedAfter],
      orderBy: 'updated_at ASC',
    );
    final mapped = <Map<String, dynamic>>[];
    for (final row in rows) {
      mapped.add(await _toCloudMap(db, table, row));
    }
    return mapped;
  }

  Future<void> cloudImportRows(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final row in rows) {
        final localMap = await _fromCloudMap(txn, table, row);
        if (localMap == null) continue;
        if (table == 'app_settings') {
          await _upsertAppSetting(txn, localMap);
          continue;
        }
        final uuid = localMap['uuid']?.toString();
        if (uuid == null || uuid.isEmpty) continue;
        await _upsertUuidRow(txn, table, uuid, localMap);
      }
    });
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
          ..remove('source_id');
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
          ..['source_id'] = await _idForUuid(
            executor,
            _sourceTable(row['source_type']?.toString()),
            row['source_uuid']?.toString(),
          );
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
          // A local row with a different UUID but same (shop_id, name) exists.
          // Merge: update the existing local row to adopt the cloud UUID + data.
          final shopId = map['shop_id']?.toString();
          final name = map['name']?.toString();
          if (shopId != null && name != null) {
            await executor.update(
              table,
              map..remove('id'),
              where: 'shop_id = ? AND name = ? COLLATE NOCASE',
              whereArgs: [shopId, name],
            );
          }
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

String? _sourceTable(String? sourceType) {
  switch (sourceType) {
    case 'bill':
    case 'bill_void':
      return 'bills';
    case 'manual':
    case 'import':
      return null;
    default:
      return null;
  }
}
