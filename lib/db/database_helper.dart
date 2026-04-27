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

const _uuid = Uuid();
const _defaultShopId = 'local-shop';

class DatabaseHelper
    with
        DatabaseSchema,
        DatabaseSettings,
        DatabaseProducts,
        DatabaseBills,
        DatabaseSync {
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
}

void notifyDatabaseChanged() {
  DatabaseHelper.instance.onDatabaseChanged?.call();
}

String? _normaliseName(String? value) {
  final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _newUuid() => _uuid.v4();

String _nowIso() => DateTime.now().toIso8601String();

bool _isPresetUnit(String value) {
  return Product.presetUnits.any(
    (unit) => unit.toLowerCase() == value.trim().toLowerCase(),
  );
}

String _dateOnly(DateTime value) {
  final local = DateTime(value.year, value.month, value.day);
  return local.toIso8601String().substring(0, 10);
}
