part of 'database_helper.dart';

mixin DatabaseSchema {
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(
      path,
      version: 14,
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
    await _createCustomerTables(db);
    await _createBillTables(db);
    await _createProductPurchaseTables(db);
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
    if (oldVersion < 12) await _upgradeCustomerSchema(db);
    if (oldVersion < 13) await _upgradeProductPurchaseSchema(db);
    if (oldVersion < 14) await _upgradeBillPaymentMethodSchema(db);
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
    await _createCustomerTables(db);
    await _createBillTables(db);
    await _createProductPurchaseTables(db);
    await _upgradeCustomerSchema(db);
    await _upgradeProductPurchaseSchema(db);
    await _upgradeUnitSchema(db);
    await _upgradePricingSchema(db);
    await _upgradeProductPricingOverrides(db);
    await _upgradeBillTables(db);
    await _upgradeBillPaymentMethodSchema(db);
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

  Future<void> _createCustomerTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL DEFAULT 'Walk-in Customer',
        phone TEXT NOT NULL UNIQUE,
        total_purchase_amount REAL NOT NULL DEFAULT 0,
        bill_count INTEGER NOT NULL DEFAULT 0,
        last_purchase_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createProductPurchaseTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS product_purchase_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        purchase_date TEXT NOT NULL,
        quantity_added INTEGER NOT NULL,
        purchase_price REAL NOT NULL,
        supplier TEXT,
        import_batch_key TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_product_purchase_entries_product_date
      ON product_purchase_entries(product_id, purchase_date)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_product_purchase_entries_batch
      ON product_purchase_entries(import_batch_key)
    ''');
  }

  Future<void> _seedOptionsFromProducts(DatabaseExecutor executor) async {
    final categories = await executor.rawQuery(
      "SELECT DISTINCT category FROM products WHERE category IS NOT NULL AND TRIM(category) != ''",
    );
    for (final row in categories) {
      await _insertOption(executor, 'category_options', row['category']);
    }

    final suppliers = await executor.rawQuery(
      "SELECT DISTINCT supplier FROM products WHERE supplier IS NOT NULL AND TRIM(supplier) != ''",
    );
    for (final row in suppliers) {
      await _insertOption(executor, 'supplier_options', row['supplier']);
    }

    final units = await executor.rawQuery(
      "SELECT DISTINCT unit FROM products WHERE unit IS NOT NULL AND TRIM(unit) != ''",
    );
    for (final row in units) {
      await _insertUnitOption(executor, row['unit']);
    }
  }

  Future<void> _createBillTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS bills(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        customer_name TEXT NOT NULL DEFAULT 'Walk-in Customer',
        customer_phone TEXT,
        subtotal_amount REAL NOT NULL DEFAULT 0,
        discount_percent REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        profit_commission_percent REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL,
        item_count INTEGER NOT NULL,
        is_paid INTEGER NOT NULL DEFAULT 1,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
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
      'customer_id',
      'customer_id INTEGER',
    );
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
    await _addColumnIfMissing(
      executor,
      'bills',
      'payment_method',
      "payment_method TEXT NOT NULL DEFAULT 'cash'",
    );
    await executor.execute('''
      UPDATE bills
      SET subtotal_amount = total_amount + discount_amount
      WHERE subtotal_amount = 0
    ''');
  }

  Future<void> _upgradeCustomerSchema(DatabaseExecutor executor) async {
    await _createCustomerTables(executor);
    await _addColumnIfMissing(
      executor,
      'bills',
      'customer_id',
      'customer_id INTEGER',
    );
    await _syncCustomersFromBills(executor);
  }

  Future<void> _upgradeBillPaymentMethodSchema(
    DatabaseExecutor executor,
  ) async {
    await _addColumnIfMissing(
      executor,
      'bills',
      'payment_method',
      "payment_method TEXT NOT NULL DEFAULT 'cash'",
    );
  }

  Future<void> _syncCustomersFromBills(DatabaseExecutor executor) async {
    final bills = await executor.query(
      'bills',
      where: "customer_phone IS NOT NULL AND TRIM(customer_phone) != ''",
      orderBy: 'created_at ASC',
    );
    final ledgers = <String, _CustomerLedgerDraft>{};
    final invalidBillIds = <int>[];

    for (final bill in bills) {
      final billId = bill['id'] as int;
      final phone = _normaliseCustomerPhone(bill['customer_phone']);
      if (phone == null) {
        invalidBillIds.add(billId);
        continue;
      }
      final name =
          _normaliseName(bill['customer_name']?.toString()) ??
          'Walk-in Customer';
      final total = (bill['total_amount'] as num?)?.toDouble() ?? 0;
      final createdAt =
          bill['created_at']?.toString() ?? DateTime.now().toIso8601String();

      final ledger = ledgers.putIfAbsent(
        phone,
        () => _CustomerLedgerDraft(
          name: name,
          phone: phone,
          lastPurchaseAt: createdAt,
        ),
      );
      ledger.addBill(
        billId: billId,
        name: name,
        totalAmount: total,
        createdAt: createdAt,
      );
    }

    for (final billId in invalidBillIds) {
      await executor.update(
        'bills',
        {'customer_id': null},
        where: 'id = ?',
        whereArgs: [billId],
      );
    }
    await executor.update('bills', {
      'customer_id': null,
    }, where: "customer_phone IS NULL OR TRIM(customer_phone) = ''");

    final existingCustomers = await executor.query('customers');
    final customerIdsByPhone = {
      for (final customer in existingCustomers)
        customer['phone'] as String: customer['id'] as int,
    };
    final now = DateTime.now().toIso8601String();

    await executor.update('customers', {
      'total_purchase_amount': 0,
      'bill_count': 0,
      'last_purchase_at': null,
      'updated_at': now,
    });

    if (ledgers.isEmpty) return;

    for (final ledger in ledgers.values) {
      final existingId = customerIdsByPhone[ledger.phone];
      final data = {
        'name': ledger.name,
        'phone': ledger.phone,
        'total_purchase_amount': ledger.totalPurchaseAmount,
        'bill_count': ledger.billCount,
        'last_purchase_at': ledger.lastPurchaseAt,
        'updated_at': now,
      };

      final customerId =
          existingId ??
          await executor.insert('customers', {...data, 'created_at': now});
      if (existingId != null) {
        await executor.update(
          'customers',
          data,
          where: 'id = ?',
          whereArgs: [existingId],
        );
      }

      for (final billId in ledger.billIds) {
        await executor.update(
          'bills',
          {'customer_id': customerId},
          where: 'id = ?',
          whereArgs: [billId],
        );
      }
    }
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

  Future<void> _upgradeProductPurchaseSchema(DatabaseExecutor executor) async {
    await _createProductPurchaseTables(executor);
    final existingEntries = await executor.rawQuery(
      'SELECT COUNT(*) AS c FROM product_purchase_entries',
    );
    final count = Sqflite.firstIntValue(existingEntries) ?? 0;
    if (count > 0) return;

    final products = await executor.query('products');
    final now = DateTime.now().toIso8601String();
    for (final product in products) {
      final quantity = product['quantity'] as int? ?? 0;
      if (quantity <= 0) continue;
      final createdAt = product['created_at'] as String? ?? now;
      await executor.insert('product_purchase_entries', {
        'product_id': product['id'],
        'purchase_date': createdAt.substring(0, 10),
        'quantity_added': quantity,
        'purchase_price':
            (product['purchase_price'] as num?)?.toDouble() ??
            (product['mrp'] as num?)?.toDouble() ??
            0,
        'supplier': product['supplier'],
        'source': product['source'] ?? ProductSource.mobile,
        'created_at': now,
      });
    }
  }
}

class _CustomerLedgerDraft {
  String name;
  final String phone;
  String lastPurchaseAt;
  final List<int> billIds = [];
  double totalPurchaseAmount = 0;
  int billCount = 0;

  _CustomerLedgerDraft({
    required this.name,
    required this.phone,
    required this.lastPurchaseAt,
  });

  void addBill({
    required int billId,
    required String name,
    required double totalAmount,
    required String createdAt,
  }) {
    billIds.add(billId);
    totalPurchaseAmount += totalAmount;
    billCount += 1;
    if (createdAt.compareTo(lastPurchaseAt) >= 0) {
      lastPurchaseAt = createdAt;
      if (name != 'Walk-in Customer') {
        this.name = name;
      }
    }
  }
}
