import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/bill.dart';
import '../models/bill_settings.dart';
import '../models/bill_totals.dart';
import '../models/invoice_numbering.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/held_bill.dart';
import '../models/product.dart';
import '../models/product_purchase.dart';
import '../utils/money.dart';
import '../models/pricing.dart';
import '../models/shop_profile.dart';
import '../models/supplier.dart';

part 'database_schema.dart';
part 'database_settings.dart';
part 'database_products.dart';
part 'database_bills.dart';
part 'database_sync.dart';
part 'database_kpi.dart';
part 'database_expenses.dart';
part 'database_reports.dart';
part 'database_audit.dart';

const _uuid = Uuid();
const _legacyShopId = 'local-shop';

class DatabaseHelper
    with
        DatabaseSchema,
        DatabaseSettings,
        DatabaseProducts,
        DatabaseBills,
        DatabaseSync,
        DatabaseKpi,
        DatabaseExpenses,
        DatabaseReports,
        DatabaseAudit {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  /// Database file name. Tests switch it to simulate several devices.
  @visibleForTesting
  static String databaseFileName = 'storely.db';

  DatabaseHelper._init();

  /// Full path of the database file (for backups and the startup error
  /// screen's "save a copy").
  static Future<String> databasePath() async =>
      join(await getDatabasesPath(), databaseFileName);

  @override
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB(databaseFileName);
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

  /// Read-only check used to skip (rather than throw on) admin-only work that
  /// runs implicitly on screen load — e.g. recomputing display prices. Returns
  /// true when the current user may perform catalog/settings writes. Defaults to
  /// true (local-only / no cloud guard installed).
  bool Function()? isAdminMutationAllowed;

  /// Who is making changes, for the audit log (e.g. the cloud user's email).
  /// Null means this phone's owner without a cloud account.
  String? Function()? auditActor;

  Future<String> currentShopId() async {
    final db = await database;
    return _activeShopId(db);
  }

  /// Joins this device to an existing cloud shop. Only allowed while the
  /// device has no business data (the sync engine checks), so everything
  /// here is untouched defaults: the cloud is the source of truth for the
  /// shop's profile, settings and catalog. Drop the local defaults and keep
  /// the shop row only as a placeholder that loses to the cloud copy, so a
  /// joining phone can never upload "My Shop" / preset units / default
  /// settings over the shop's real ones.
  Future<void> adoptCloudShopId(String shopId) async {
    final db = await database;
    await db.transaction((txn) async {
      final current = await _activeShopId(txn);
      if (current == shopId) return;
      for (final table in const [
        'app_settings',
        'bill_settings',
        'invoice_series',
        'units',
        'categories',
        'suppliers',
      ]) {
        await txn.delete(table, where: 'shop_id = ?', whereArgs: [current]);
      }
      await txn.update(
        'shops',
        {
          'uuid': shopId,
          'created_at': _placeholderTimestamp,
          'updated_at': _placeholderTimestamp,
          'sync_dirty': DatabaseSchema.syncDirtyFromCloud,
        },
        where: 'uuid = ?',
        whereArgs: [current],
      );
    });
  }

  /// Older than any real edit, so the cloud copy always wins.
  static const _placeholderTimestamp = '1970-01-01T00:00:00.000Z';
}

void notifyDatabaseChanged() {
  DatabaseHelper.instance.onDatabaseChanged?.call();
}

Future<void> _requireAdminMutation() async {
  final guard = DatabaseHelper.instance.assertAdminMutation;
  if (guard != null) await guard();
}

/// True when the current user may perform admin-only catalog/settings writes.
/// Used by implicit, load-time recomputes that must NOT crash for staff users
/// (or for a signed-in user whose role hasn't resolved yet) — they simply skip
/// the write instead of throwing the way [_requireAdminMutation] does.
bool _canMutateAsAdmin() {
  final check = DatabaseHelper.instance.isAdminMutationAllowed;
  return check == null || check();
}

String? _normaliseName(String? value) {
  final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _newUuid() => _uuid.v4();

/// Sync bookkeeping (updated_at, deleted_at): UTC, compared across devices.
String _nowIso() => DateTime.now().toUtc().toIso8601String();

/// Business dates (bill created_at, payment received_at, stock movement
/// created_at): local wall-clock time without a zone, because reports group
/// them by the shop's calendar day with substr(col, 1, 10). Mixing in UTC put
/// anything between 00:00 and 05:30 IST on the previous day.
String _localIso([DateTime? time]) =>
    (time ?? DateTime.now()).toLocal().toIso8601String();

bool _isPresetUnit(String value) {
  return Product.presetUnits.any(
    (unit) => unit.toLowerCase() == value.trim().toLowerCase(),
  );
}

String _dateOnly(DateTime value) {
  final local = DateTime(value.year, value.month, value.day);
  return local.toIso8601String().substring(0, 10);
}

/// Resolves the active shop UUID, migrating a legacy `'local-shop'` row if
/// needed.
///
/// [inImplicitTransaction] must be true when called from `onCreate`/`onUpgrade`
/// (or any other context that already holds sqflite's implicit transaction on a
/// `Database` handle). In that case the legacy migration must NOT open its own
/// transaction — sqflite forbids nesting one on a mid-migration `Database` and
/// doing so throws. The surrounding migration is already atomic, so skipping the
/// extra wrapper is safe.
Future<String> _activeShopId(
  DatabaseExecutor executor, {
  bool inImplicitTransaction = false,
}) async {
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
      return _migrateLegacyShopId(
        executor,
        rows.first['id'] as int,
        inImplicitTransaction: inImplicitTransaction,
      );
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
  int shopRowId, {
  bool inImplicitTransaction = false,
}) async {
  final uuid = _newUuid();
  // Rewriting shop_id across every table must be atomic — a crash mid-loop
  // would partition the user's data between the old and new shop_id. When we
  // hold a top-level Database handle, run inside a fresh transaction; when
  // we're already inside one (a Txn, or onCreate/onUpgrade's implicit
  // transaction on a Database handle), it is atomic by definition and opening
  // a nested transaction would throw.
  if (executor is Database && !inImplicitTransaction) {
    await executor.transaction((txn) async {
      await _replaceShopId(txn, _legacyShopId, uuid, shopRowId: shopRowId);
    });
  } else {
    await _replaceShopId(executor, _legacyShopId, uuid, shopRowId: shopRowId);
  }
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
