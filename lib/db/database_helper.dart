import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/bill.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/product_purchase.dart';
import '../models/pricing.dart';
import '../models/shop_profile.dart';
import '../models/supplier.dart';

part 'database_schema.dart';
part 'database_settings.dart';
part 'database_products.dart';
part 'database_bills.dart';
part 'database_sync.dart';
part 'database_kpi.dart';

const _uuid = Uuid();
const _legacyShopId = 'local-shop';

class DatabaseHelper
    with
        DatabaseSchema,
        DatabaseSettings,
        DatabaseProducts,
        DatabaseBills,
        DatabaseSync,
        DatabaseKpi {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  @override
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('storely.db');
    return _database!;
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) return;
    await db.close();
    _database = null;
  }

  VoidCallback? onDatabaseChanged;
  Future<void> Function()? assertAdminMutation;

  Future<String> currentShopId() async {
    final db = await database;
    return _activeShopId(db);
  }

  Future<void> adoptCloudShopId(String shopId) async {
    final db = await database;
    await db.transaction((txn) async {
      final current = await _activeShopId(txn);
      if (current == shopId) return;
      await _replaceShopId(txn, current, shopId);
    });
  }
}

void notifyDatabaseChanged() {
  DatabaseHelper.instance.onDatabaseChanged?.call();
}

Future<void> _requireAdminMutation() async {
  final guard = DatabaseHelper.instance.assertAdminMutation;
  if (guard != null) await guard();
}

String? _normaliseName(String? value) {
  final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _newUuid() => _uuid.v4();

String _nowIso() => DateTime.now().toUtc().toIso8601String();

bool _isPresetUnit(String value) {
  return Product.presetUnits.any(
    (unit) => unit.toLowerCase() == value.trim().toLowerCase(),
  );
}

String _dateOnly(DateTime value) {
  final local = DateTime(value.year, value.month, value.day);
  return local.toIso8601String().substring(0, 10);
}

Future<String> _activeShopId(DatabaseExecutor executor) async {
  final rows = await executor.query(
    'shops',
    columns: ['id', 'uuid'],
    where: 'deleted_at IS NULL',
    orderBy: 'id ASC',
    limit: 1,
  );
  if (rows.isNotEmpty) {
    final uuid = rows.first['uuid']?.toString();
    if (uuid != null && uuid.isNotEmpty && uuid != _legacyShopId) return uuid;
    if (rows.first['id'] != null) {
      return _migrateLegacyShopId(executor, rows.first['id'] as int);
    }
  }
  return _createLocalShop(executor);
}

Future<String> _createLocalShop(DatabaseExecutor executor) async {
  final now = _nowIso();
  final uuid = _newUuid();
  await executor.insert('shops', {
    'uuid': uuid,
    'name': 'My Shop',
    'created_at': now,
    'updated_at': now,
  });
  return uuid;
}

Future<String> _migrateLegacyShopId(
  DatabaseExecutor executor,
  int shopRowId,
) async {
  final uuid = _newUuid();
  await _replaceShopId(executor, _legacyShopId, uuid, shopRowId: shopRowId);
  return uuid;
}

Future<void> _replaceShopId(
  DatabaseExecutor executor,
  String fromShopId,
  String toShopId, {
  int? shopRowId,
}) async {
  final now = _nowIso();
  for (final table in [
    'app_settings',
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
  ]) {
    await executor.update(
      table,
      {'shop_id': toShopId, 'updated_at': now},
      where: 'shop_id = ?',
      whereArgs: [fromShopId],
    );
  }
  final existingTarget = await executor.query(
    'shops',
    columns: ['id'],
    where: 'uuid = ?',
    whereArgs: [toShopId],
    limit: 1,
  );
  if (existingTarget.isNotEmpty) {
    await executor.update(
      'shops',
      {'deleted_at': now, 'updated_at': now},
      where: 'uuid = ? AND id != ?',
      whereArgs: [fromShopId, existingTarget.single['id']],
    );
    return;
  }
  await executor.update(
    'shops',
    {'uuid': toShopId, 'updated_at': now},
    where: shopRowId == null ? 'uuid = ?' : 'id = ?',
    whereArgs: [shopRowId ?? fromShopId],
  );
}
