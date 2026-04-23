import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/product.dart';
import '../models/bill.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static const _shopNameKey = 'shop_name';
  static const _lowStockThresholdKey = 'low_stock_threshold';
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('storely.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(
      path,
      version: 8,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
    await _ensureSchema(db);
    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    await _createProductTable(db);
    await _createSettingsTable(db);
    await _createOptionTables(db);
    await _createBillTables(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createBillTables(db);
    if (oldVersion < 3) {
      await _addColumnIfMissing(db, 'products', 'item_code', 'item_code TEXT');
      await _addColumnIfMissing(db, 'products', 'category', 'category TEXT');
      await _addColumnIfMissing(db, 'products', 'supplier', 'supplier TEXT');
    }
    if (oldVersion < 4) {
      await _addColumnIfMissing(
        db,
        'products',
        'source',
        "source TEXT NOT NULL DEFAULT 'mobile'",
      );
      await _createOptionTables(db);
      await _seedOptionsFromProducts(db);
    }
    if (oldVersion < 5) {
      await _createSettingsTable(db);
    }
    if (oldVersion < 8) await _upgradeBillTables(db);
  }

  Future<void> _ensureSchema(Database db) async {
    await _createProductTable(db);
    await _createSettingsTable(db);
    await _addColumnIfMissing(db, 'products', 'item_code', 'item_code TEXT');
    await _addColumnIfMissing(db, 'products', 'category', 'category TEXT');
    await _addColumnIfMissing(db, 'products', 'supplier', 'supplier TEXT');
    await _addColumnIfMissing(
      db,
      'products',
      'source',
      "source TEXT NOT NULL DEFAULT 'mobile'",
    );
    await _createOptionTables(db);
    await _createBillTables(db);
    await _upgradeBillTables(db);
    await _seedOptionsFromProducts(db);
  }

  Future<void> _createProductTable(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_code TEXT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        category TEXT,
        mrp REAL NOT NULL,
        quantity INTEGER NOT NULL,
        supplier TEXT,
        source TEXT NOT NULL DEFAULT 'mobile',
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createSettingsTable(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS app_settings(
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createOptionTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS category_options(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        created_at TEXT NOT NULL
      )
    ''');
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS supplier_options(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        created_at TEXT NOT NULL
      )
    ''');
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

  Future<void> _seedOptionsFromProducts(DatabaseExecutor executor) async {
    final categories = await executor.rawQuery(
      'SELECT DISTINCT category FROM products WHERE category IS NOT NULL AND TRIM(category) != ""',
    );
    for (final row in categories) {
      await _insertOption(executor, 'category_options', row['category']);
    }

    final suppliers = await executor.rawQuery(
      'SELECT DISTINCT supplier FROM products WHERE supplier IS NOT NULL AND TRIM(supplier) != ""',
    );
    for (final row in suppliers) {
      await _insertOption(executor, 'supplier_options', row['supplier']);
    }
  }

  Future<void> _createBillTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS bills(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT NOT NULL DEFAULT 'Walk-in Customer',
        customer_phone TEXT,
        subtotal_amount REAL NOT NULL DEFAULT 0,
        discount_percent REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL,
        item_count INTEGER NOT NULL,
        is_paid INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      )
    ''');
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS bill_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bill_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        mrp REAL NOT NULL,
        quantity INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _upgradeBillTables(DatabaseExecutor executor) async {
    await _addColumnIfMissing(
      executor,
      'bills',
      'customer_name',
      "customer_name TEXT NOT NULL DEFAULT 'Walk-in Customer'",
    );
    await _addColumnIfMissing(
      executor,
      'bills',
      'customer_phone',
      'customer_phone TEXT',
    );
    await _addColumnIfMissing(
      executor,
      'bills',
      'subtotal_amount',
      'subtotal_amount REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'bills',
      'discount_percent',
      'discount_percent REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'bills',
      'discount_amount',
      'discount_amount REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'bills',
      'is_paid',
      'is_paid INTEGER NOT NULL DEFAULT 1',
    );
    await executor.execute('''
      UPDATE bills
      SET subtotal_amount = total_amount + discount_amount
      WHERE subtotal_amount = 0
    ''');
  }

  // ── Shop Info ──
  Future<String?> getShopName() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_shopNameKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value'] as String?;
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveShopName(String name) async {
    final db = await database;
    final value = _normaliseName(name);
    if (value == null) {
      throw ArgumentError('Shop name is required');
    }
    await db.insert('app_settings', {
      'key': _shopNameKey,
      'value': value,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> getLowStockThreshold() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_lowStockThresholdKey],
      limit: 1,
    );
    if (rows.isEmpty) return 5;
    final value = int.tryParse(rows.first['value']?.toString() ?? '');
    return value == null || value < 0 ? 5 : value;
  }

  Future<void> saveLowStockThreshold(int value) async {
    if (value < 0) {
      throw ArgumentError('Minimum stock cannot be negative');
    }
    final db = await database;
    await db.insert('app_settings', {
      'key': _lowStockThresholdKey,
      'value': value.toString(),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ── Product CRUD ──
  Future<int> insertProduct(Product product) async {
    final db = await database;
    return db.transaction((txn) async {
      var productToInsert = product;
      final needsMobileCode =
          productToInsert.source == ProductSource.mobile &&
          (productToInsert.itemCode == null ||
              productToInsert.itemCode!.trim().isEmpty);

      if (needsMobileCode) {
        productToInsert = productToInsert.copyWith(
          itemCode: await _nextMobileItemCode(txn),
        );
      }

      final id = await txn.insert(
        'products',
        productToInsert.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await _saveProductOptions(txn, productToInsert);
      return id;
    });
  }

  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final maps = await db.query('products', orderBy: 'created_at ASC');
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  Future<bool> isNameUnique(String name, {int? excludeId}) async {
    final db = await database;
    final result = await db.query(
      'products',
      where: excludeId != null
          ? 'LOWER(name) = LOWER(?) AND id != ?'
          : 'LOWER(name) = LOWER(?)',
      whereArgs: excludeId != null ? [name, excludeId] : [name],
    );
    return result.isEmpty;
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    return db.transaction((txn) async {
      final count = await txn.update(
        'products',
        product.toMap(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
      await _saveProductOptions(txn, product);
      return count;
    });
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getCategories() async {
    final db = await database;
    return _getOptions(db, 'category_options', 'category');
  }

  Future<List<String>> getSuppliers() async {
    final db = await database;
    return _getOptions(db, 'supplier_options', 'supplier');
  }

  Future<void> addCategoryOption(String name) async {
    final db = await database;
    await _insertOption(db, 'category_options', name);
  }

  Future<void> updateCategoryOption(String oldName, String newName) async {
    final db = await database;
    await _updateOption(db, 'category_options', 'category', oldName, newName);
  }

  Future<void> deleteCategoryOption(String name) async {
    final db = await database;
    await _deleteOption(db, 'category_options', 'category', name);
  }

  Future<void> addSupplierOption(String name) async {
    final db = await database;
    await _insertOption(db, 'supplier_options', name);
  }

  Future<void> updateSupplierOption(String oldName, String newName) async {
    final db = await database;
    await _updateOption(db, 'supplier_options', 'supplier', oldName, newName);
  }

  Future<void> deleteSupplierOption(String name) async {
    final db = await database;
    await _deleteOption(db, 'supplier_options', 'supplier', name);
  }

  // ── Bulk Import ──
  Future<int> replaceAllProducts(List<Product> products) async {
    final db = await database;
    final cleanProducts = _uniqueProductsByName(
      products,
    ).map(_asImportedProduct).toList();

    return db.transaction((txn) async {
      await txn.delete('products');
      int count = 0;
      for (final p in cleanProducts) {
        await txn.insert(
          'products',
          p.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await _saveProductOptions(txn, p);
        count++;
      }
      return count;
    });
  }

  Future<Map<String, int>> mergeProducts(List<Product> products) async {
    final db = await database;
    final cleanProducts = _uniqueProductsByName(
      products,
    ).map(_asImportedProduct).toList();

    return db.transaction((txn) async {
      int added = 0, updated = 0;
      for (final p in cleanProducts) {
        // Try to match by item_code first, then by name
        List<Map<String, dynamic>> existing = [];
        if (p.itemCode != null && p.itemCode!.isNotEmpty) {
          existing = await txn.query(
            'products',
            where: 'item_code = ?',
            whereArgs: [p.itemCode],
          );
        }
        if (existing.isEmpty) {
          existing = await txn.query(
            'products',
            where: 'LOWER(name) = LOWER(?)',
            whereArgs: [p.name],
          );
        }

        if (existing.isNotEmpty) {
          final existingId = existing.first['id'] as int;
          await txn.update(
            'products',
            p.copyWith(id: existingId).toMap(),
            where: 'id = ?',
            whereArgs: [existingId],
          );
          await _saveProductOptions(txn, p);
          updated++;
        } else {
          await txn.insert(
            'products',
            p.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await _saveProductOptions(txn, p);
          added++;
        }
      }
      return {'added': added, 'updated': updated};
    });
  }

  List<Product> _uniqueProductsByName(List<Product> products) {
    final byName = <String, Product>{};
    for (final product in products) {
      byName[product.name.trim().toLowerCase()] = product;
    }
    return byName.values.toList();
  }

  Product _asImportedProduct(Product product) =>
      product.copyWith(source: ProductSource.imported);

  Future<List<String>> _getOptions(
    DatabaseExecutor executor,
    String table,
    String productColumn,
  ) async {
    final optionRows = await executor.query(table, orderBy: 'name ASC');
    final productRows = await executor.rawQuery(
      'SELECT DISTINCT $productColumn FROM products WHERE $productColumn IS NOT NULL AND TRIM($productColumn) != ""',
    );
    final values = <String>{};
    for (final row in optionRows) {
      final name = row['name'] as String?;
      if (name != null && name.trim().isNotEmpty) values.add(name.trim());
    }
    for (final row in productRows) {
      final name = row[productColumn] as String?;
      if (name != null && name.trim().isNotEmpty) values.add(name.trim());
    }
    final sorted = values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  Future<void> _saveProductOptions(
    DatabaseExecutor executor,
    Product product,
  ) async {
    await _insertOption(executor, 'category_options', product.category);
    await _insertOption(executor, 'supplier_options', product.supplier);
  }

  Future<void> _insertOption(
    DatabaseExecutor executor,
    String table,
    Object? name,
  ) async {
    final value = _normaliseName(name?.toString());
    if (value == null) return;
    await executor.insert(table, {
      'name': value,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _updateOption(
    Database db,
    String table,
    String productColumn,
    String oldName,
    String newName,
  ) async {
    final oldValue = _normaliseName(oldName);
    final newValue = _normaliseName(newName);
    if (oldValue == null || newValue == null) {
      throw ArgumentError('Name is required');
    }

    await db.transaction((txn) async {
      if (oldValue.toLowerCase() == newValue.toLowerCase()) {
        await txn.update(
          table,
          {'name': newValue},
          where: 'LOWER(name) = LOWER(?)',
          whereArgs: [oldValue],
        );
        await txn.update(
          'products',
          {productColumn: newValue},
          where: 'LOWER($productColumn) = LOWER(?)',
          whereArgs: [oldValue],
        );
        return;
      }

      await _insertOption(txn, table, newValue);
      await txn.update(
        'products',
        {productColumn: newValue},
        where: 'LOWER($productColumn) = LOWER(?)',
        whereArgs: [oldValue],
      );
      await txn.delete(
        table,
        where: 'LOWER(name) = LOWER(?)',
        whereArgs: [oldValue],
      );
    });
  }

  Future<void> _deleteOption(
    Database db,
    String table,
    String productColumn,
    String name,
  ) async {
    final value = _normaliseName(name);
    if (value == null) return;

    await db.transaction((txn) async {
      await txn.delete(
        table,
        where: 'LOWER(name) = LOWER(?)',
        whereArgs: [value],
      );
      await txn.update(
        'products',
        {productColumn: null},
        where: 'LOWER($productColumn) = LOWER(?)',
        whereArgs: [value],
      );
    });
  }

  String? _normaliseName(String? value) {
    final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<String> _nextMobileItemCode(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'products',
      columns: ['item_code'],
      where: 'LOWER(item_code) LIKE ?',
      whereArgs: ['mitm%'],
    );

    var maxNumber = 0;
    final codePattern = RegExp(r'^mitm(\d+)$', caseSensitive: false);
    for (final row in rows) {
      final code = row['item_code'] as String?;
      if (code == null) continue;
      final match = codePattern.firstMatch(code.trim());
      if (match == null) continue;
      final number = int.tryParse(match.group(1)!);
      if (number != null && number > maxNumber) maxNumber = number;
    }

    return 'mitm${(maxNumber + 1).toString().padLeft(3, '0')}';
  }

  // ── Bill CRUD ──
  Future<int> insertBill(Bill bill, List<BillItem> items) async {
    final db = await database;
    return db.transaction((txn) async {
      final billId = await txn.insert('bills', bill.toMap());
      for (final item in items) {
        await txn.insert('bill_items', item.toMap(billId));
      }
      return billId;
    });
  }

  Future<List<Bill>> getAllBills() async {
    final db = await database;
    final billMaps = await db.query('bills', orderBy: 'created_at DESC');
    final bills = <Bill>[];
    for (final map in billMaps) {
      final itemMaps = await db.query(
        'bill_items',
        where: 'bill_id = ?',
        whereArgs: [map['id']],
      );
      final items = itemMaps.map((m) => BillItem.fromMap(m)).toList();
      bills.add(Bill.fromMap(map, items));
    }
    return bills;
  }

  Future<int> deleteBill(int id) async {
    final db = await database;
    await db.delete('bill_items', where: 'bill_id = ?', whereArgs: [id]);
    return await db.delete('bills', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateBillPaidStatus(int id, bool isPaid) async {
    final db = await database;
    return db.update(
      'bills',
      {'is_paid': isPaid ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getBillCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM bills');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<double> getTodaySales() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount),0) as s FROM bills WHERE created_at LIKE ?',
      ['$today%'],
    );
    return (r.first['s'] as num).toDouble();
  }

  Future<int> getTodayBillCount() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM bills WHERE created_at LIKE ?',
      ['$today%'],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<Bill>> getUnpaidBills({int? limit}) async {
    final db = await database;
    final billMaps = await db.query(
      'bills',
      where: 'is_paid = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    final bills = <Bill>[];
    for (final map in billMaps) {
      final itemMaps = await db.query(
        'bill_items',
        where: 'bill_id = ?',
        whereArgs: [map['id']],
      );
      final items = itemMaps.map((m) => BillItem.fromMap(m)).toList();
      bills.add(Bill.fromMap(map, items));
    }
    return bills;
  }
}
