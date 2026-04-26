part of 'database_helper.dart';

mixin DatabaseSchema {
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(
      path,
      version: 15,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
    await _ensureSchema(db);
    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    await _createCleanSchema(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 15) {
      await _dropLegacySchema(db);
      await _createCleanSchema(db);
      return;
    }
    await _ensureSchema(db);
  }

  Future<void> _ensureSchema(Database db) async {
    await _createCleanSchema(db);
  }

  Future<void> _dropLegacySchema(DatabaseExecutor executor) async {
    for (final table in [
      'bill_items',
      'bills',
      'stock_movements',
      'product_purchase_entries',
      'products',
      'customers',
      'suppliers',
      'supplier_options',
      'categories',
      'category_options',
      'units',
      'unit_options',
      'app_settings',
      'shops',
    ]) {
      await executor.execute('DROP TABLE IF EXISTS $table');
    }
  }

  Future<void> _createCleanSchema(DatabaseExecutor executor) async {
    await _createShopTables(executor);
    await _createSettingsTable(executor);
    await _createReferenceTables(executor);
    await _createProductTable(executor);
    await _createCustomerTables(executor);
    await _createBillTables(executor);
    await _createStockMovementTables(executor);
    await _seedPresetUnits(executor);
  }

  Future<void> _createShopTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS shops(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        gstin TEXT,
        address TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
  }

  Future<void> _createSettingsTable(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS app_settings(
        key TEXT NOT NULL,
        shop_id TEXT NOT NULL DEFAULT 'local-shop',
        value TEXT,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        PRIMARY KEY (shop_id, key)
      )
    ''');
  }

  Future<void> _createReferenceTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL COLLATE NOCASE,
        gst_percent REAL,
        overhead_cost REAL,
        profit_margin_percent REAL,
        commission_percent REAL,
        direct_price_toggle INTEGER NOT NULL DEFAULT 0,
        manual_price REAL,
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS units(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL COLLATE NOCASE,
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS suppliers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL COLLATE NOCASE,
        phone TEXT,
        email TEXT,
        gstin TEXT,
        address TEXT,
        notes TEXT,
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_uuid
      ON categories(uuid)
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_shop_name
      ON categories(shop_id, name)
      WHERE deleted_at IS NULL
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_categories_shop_updated
      ON categories(shop_id, updated_at)
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_units_uuid ON units(uuid)
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_units_shop_name
      ON units(shop_id, name)
      WHERE deleted_at IS NULL
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_units_shop_updated
      ON units(shop_id, updated_at)
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_suppliers_uuid ON suppliers(uuid)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_suppliers_shop_name
      ON suppliers(shop_id, name)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_suppliers_shop_updated
      ON suppliers(shop_id, updated_at)
    ''');
  }

  Future<void> _createProductTable(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        product_code TEXT,
        barcode TEXT,
        name TEXT NOT NULL COLLATE NOCASE,
        category_id INTEGER,
        supplier_id INTEGER,
        selling_price REAL NOT NULL DEFAULT 0,
        purchase_price REAL NOT NULL DEFAULT 0,
        gst_percent REAL,
        overhead_cost REAL,
        profit_margin_percent REAL,
        direct_price_toggle INTEGER NOT NULL DEFAULT 0,
        manual_price REAL,
        quantity_cache REAL NOT NULL DEFAULT 0,
        unit_id INTEGER,
        source TEXT NOT NULL DEFAULT 'mobile',
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (category_id) REFERENCES categories(id),
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
        FOREIGN KEY (unit_id) REFERENCES units(id)
      )
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_products_uuid ON products(uuid)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_products_shop_updated
      ON products(shop_id, updated_at)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_products_shop_product_code
      ON products(shop_id, product_code)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_products_shop_barcode
      ON products(shop_id, barcode)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_products_supplier ON products(supplier_id)
    ''');
  }

  Future<void> _createCustomerTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT 'Walk-in Customer',
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT,
        total_purchase_amount REAL NOT NULL DEFAULT 0,
        bill_count INTEGER NOT NULL DEFAULT 0,
        last_purchase_at TEXT,
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_uuid ON customers(uuid)
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_shop_phone
      ON customers(shop_id, phone)
      WHERE phone IS NOT NULL AND TRIM(phone) != '' AND deleted_at IS NULL
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_customers_shop_updated
      ON customers(shop_id, updated_at)
    ''');
  }

  Future<void> _createBillTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS bills(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        bill_number TEXT NOT NULL,
        customer_id INTEGER,
        customer_uuid TEXT,
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
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS bill_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        bill_id INTEGER NOT NULL,
        bill_uuid TEXT NOT NULL,
        product_id INTEGER,
        product_uuid TEXT,
        product_name TEXT NOT NULL,
        unit_name TEXT,
        purchase_price_snapshot REAL NOT NULL DEFAULT 0,
        selling_price_snapshot REAL NOT NULL DEFAULT 0,
        cost_snapshot REAL NOT NULL DEFAULT 0,
        profit_snapshot REAL NOT NULL DEFAULT 0,
        commission_snapshot REAL NOT NULL DEFAULT 0,
        gst_snapshot REAL NOT NULL DEFAULT 0,
        was_direct_price INTEGER NOT NULL DEFAULT 1,
        quantity REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL,
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (bill_id) REFERENCES bills(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_bills_uuid ON bills(uuid)
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_bills_shop_bill_number
      ON bills(shop_id, bill_number)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bills_shop_created
      ON bills(shop_id, created_at)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bills_shop_updated
      ON bills(shop_id, updated_at)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bills_customer_id ON bills(customer_id)
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_bill_items_uuid
      ON bill_items(uuid)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bill_items_bill_id
      ON bill_items(bill_id)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bill_items_product_uuid
      ON bill_items(product_uuid)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bill_items_shop_updated
      ON bill_items(shop_id, updated_at)
    ''');
  }

  Future<void> _createStockMovementTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS stock_movements(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        product_uuid TEXT NOT NULL,
        movement_type TEXT NOT NULL,
        quantity_delta REAL NOT NULL,
        unit_cost REAL,
        source_type TEXT,
        source_id INTEGER,
        source_uuid TEXT,
        import_batch_key TEXT,
        notes TEXT,
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_movements_uuid
      ON stock_movements(uuid)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_movements_product_created
      ON stock_movements(product_id, created_at)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_movements_source
      ON stock_movements(source_type, source_id)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_movements_shop_updated
      ON stock_movements(shop_id, updated_at)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_movements_import_batch
      ON stock_movements(import_batch_key)
    ''');
  }

  Future<void> _seedPresetUnits(DatabaseExecutor executor) async {
    final now = _nowIso();
    for (final unit in Product.presetUnits) {
      await executor.insert('units', {
        'uuid': _newUuid(),
        'shop_id': _defaultShopId,
        'name': unit,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> syncCustomersFromBills(DatabaseExecutor executor) async {
    final bills = await executor.query(
      'bills',
      where:
          "deleted_at IS NULL AND customer_phone IS NOT NULL AND TRIM(customer_phone) != ''",
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
        {'customer_id': null, 'customer_uuid': null},
        where: 'id = ?',
        whereArgs: [billId],
      );
    }

    final existingCustomers = await executor.query('customers');
    final customerIdsByPhone = {
      for (final customer in existingCustomers)
        if (customer['phone'] != null)
          customer['phone'] as String: customer['id'] as int,
    };
    final customerUuidsByPhone = {
      for (final customer in existingCustomers)
        if (customer['phone'] != null)
          customer['phone'] as String: customer['uuid'] as String,
    };
    final customerNamesByPhone = {
      for (final customer in existingCustomers)
        if (customer['phone'] != null)
          customer['phone'] as String: _normaliseName(
            customer['name']?.toString(),
          ),
    };
    final now = _nowIso();

    await executor.update('customers', {
      'total_purchase_amount': 0,
      'bill_count': 0,
      'last_purchase_at': null,
      'updated_at': now,
    });

    for (final ledger in ledgers.values) {
      final existingId = customerIdsByPhone[ledger.phone];
      final existingName = customerNamesByPhone[ledger.phone];
      final data = {
        'name': existingName ?? ledger.name,
        'phone': ledger.phone,
        'total_purchase_amount': ledger.totalPurchaseAmount,
        'bill_count': ledger.billCount,
        'last_purchase_at': ledger.lastPurchaseAt,
        'updated_at': now,
      };

      final customerId =
          existingId ??
          await executor.insert('customers', {
            ...data,
            'uuid': _newUuid(),
            'shop_id': _defaultShopId,
            'created_at': now,
          });
      final customerUuid =
          customerUuidsByPhone[ledger.phone] ??
          (await executor.query(
                'customers',
                columns: ['uuid'],
                where: 'id = ?',
                whereArgs: [customerId],
                limit: 1,
              )).single['uuid']
              as String;
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
          {'customer_id': customerId, 'customer_uuid': customerUuid},
          where: 'id = ?',
          whereArgs: [billId],
        );
      }
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
