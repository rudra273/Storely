import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/bill.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/pricing.dart';

part 'database_schema.dart';
part 'database_settings.dart';
part 'database_products.dart';
part 'database_bills.dart';

class DatabaseHelper
    with DatabaseSchema, DatabaseSettings, DatabaseProducts, DatabaseBills {
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
}

String? _normaliseName(String? value) {
  final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

bool _isPresetUnit(String value) {
  return Product.presetUnits.any(
    (unit) => unit.toLowerCase() == value.trim().toLowerCase(),
  );
}

Future<void> _addColumnIfMissing(
  DatabaseExecutor executor,
  String table,
  String column,
  String definition,
) async {
  final columns = await executor.rawQuery('PRAGMA table_info($table)');
  final hasColumn = columns.any((row) => row['name'] == column);
  if (!hasColumn) {
    await executor.execute('ALTER TABLE $table ADD COLUMN $definition');
  }
}
