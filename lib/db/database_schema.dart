part of 'database_helper.dart';

mixin DatabaseSchema {
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(
      path,
      version: 11,
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
    if (oldVersion < 9) await _upgradeUnitSchema(db);
    if (oldVersion < 10) await _upgradePricingSchema(db);
    if (oldVersion < 11) await _upgradeProductPricingOverrides(db);
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
    await _upgradeUnitSchema(db);
    await _upgradePricingSchema(db);
    await _upgradeProductPricingOverrides(db);
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
        purchase_price REAL NOT NULL DEFAULT 0,
        gst_percent REAL,
        overhead_cost REAL,
        profit_margin_percent REAL,
        direct_price_toggle INTEGER NOT NULL DEFAULT 0,
        manual_price REAL,
        quantity INTEGER NOT NULL,
        unit TEXT,
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
        gst_percent REAL,
        overhead_cost REAL,
        profit_margin_percent REAL,
        commission_percent REAL,
        direct_price_toggle INTEGER NOT NULL DEFAULT 0,
        manual_price REAL,
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
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS unit_options(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE COLLATE NOCASE,
        created_at TEXT NOT NULL
      )
    ''');
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

    final units = await executor.rawQuery(
      'SELECT DISTINCT unit FROM products WHERE unit IS NOT NULL AND TRIM(unit) != ""',
    );
    for (final row in units) {
      await _insertUnitOption(executor, row['unit']);
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
        profit_commission_percent REAL NOT NULL DEFAULT 0,
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
        product_id INTEGER,
        product_name TEXT NOT NULL,
        mrp REAL NOT NULL,
        unit TEXT,
        purchase_price_snapshot REAL NOT NULL DEFAULT 0,
        selling_price_snapshot REAL NOT NULL DEFAULT 0,
        cost_snapshot REAL NOT NULL DEFAULT 0,
        profit_snapshot REAL NOT NULL DEFAULT 0,
        commission_snapshot REAL NOT NULL DEFAULT 0,
        gst_snapshot REAL NOT NULL DEFAULT 0,
        was_direct_price INTEGER NOT NULL DEFAULT 1,
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
      'profit_commission_percent',
      'profit_commission_percent REAL NOT NULL DEFAULT 0',
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

  Future<void> _upgradeUnitSchema(DatabaseExecutor executor) async {
    await _addColumnIfMissing(executor, 'products', 'unit', 'unit TEXT');
    await _createOptionTables(executor);
    await _addColumnIfMissing(executor, 'bill_items', 'unit', 'unit TEXT');
    await _seedOptionsFromProducts(executor);
  }

  Future<void> _upgradePricingSchema(DatabaseExecutor executor) async {
    await _addColumnIfMissing(
      executor,
      'products',
      'purchase_price',
      'purchase_price REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'products',
      'direct_price_toggle',
      'direct_price_toggle INTEGER NOT NULL DEFAULT 1',
    );
    await _addColumnIfMissing(
      executor,
      'products',
      'manual_price',
      'manual_price REAL',
    );
    await executor.execute('''
      UPDATE products
      SET purchase_price = mrp
      WHERE purchase_price = 0
    ''');
    await executor.execute('''
      UPDATE products
      SET manual_price = mrp
      WHERE manual_price IS NULL
    ''');

    await _addColumnIfMissing(
      executor,
      'category_options',
      'gst_percent',
      'gst_percent REAL',
    );
    await _addColumnIfMissing(
      executor,
      'category_options',
      'overhead_cost',
      'overhead_cost REAL',
    );
    await _addColumnIfMissing(
      executor,
      'category_options',
      'profit_margin_percent',
      'profit_margin_percent REAL',
    );
    await _addColumnIfMissing(
      executor,
      'category_options',
      'commission_percent',
      'commission_percent REAL',
    );
    await _addColumnIfMissing(
      executor,
      'category_options',
      'direct_price_toggle',
      'direct_price_toggle INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'category_options',
      'manual_price',
      'manual_price REAL',
    );

    await _addColumnIfMissing(
      executor,
      'bill_items',
      'product_id',
      'product_id INTEGER',
    );
    await _addColumnIfMissing(
      executor,
      'bill_items',
      'purchase_price_snapshot',
      'purchase_price_snapshot REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'bill_items',
      'selling_price_snapshot',
      'selling_price_snapshot REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'bill_items',
      'cost_snapshot',
      'cost_snapshot REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'bill_items',
      'profit_snapshot',
      'profit_snapshot REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'bill_items',
      'commission_snapshot',
      'commission_snapshot REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'bill_items',
      'gst_snapshot',
      'gst_snapshot REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      executor,
      'bill_items',
      'was_direct_price',
      'was_direct_price INTEGER NOT NULL DEFAULT 1',
    );
    await executor.execute('''
      UPDATE bill_items
      SET selling_price_snapshot = mrp
      WHERE selling_price_snapshot = 0
    ''');
    await executor.execute('''
      UPDATE bill_items
      SET purchase_price_snapshot = mrp,
          cost_snapshot = mrp
      WHERE cost_snapshot = 0
    ''');
  }

  Future<void> _upgradeProductPricingOverrides(
    DatabaseExecutor executor,
  ) async {
    await _addColumnIfMissing(
      executor,
      'products',
      'gst_percent',
      'gst_percent REAL',
    );
    await _addColumnIfMissing(
      executor,
      'products',
      'overhead_cost',
      'overhead_cost REAL',
    );
    await _addColumnIfMissing(
      executor,
      'products',
      'profit_margin_percent',
      'profit_margin_percent REAL',
    );
  }
}
