part of 'database_helper.dart';

mixin DatabaseSchema {
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(
      path,
      version: 21,
      onConfigure: _configureDB,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
    await _ensureSchema(db);
    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    // Fresh database: build the current schema directly. No backfill is needed
    // because there is no legacy data to repair. Mark one-shot migrations as
    // already satisfied so they never run for a brand-new install.
    await _createCleanSchema(db);
    await _seedBaseData(db);
    await _markMigrationDone(db, _v16BillingBackfillKey);
    await _markMigrationDone(db, _v21IndexRebuildKey);
  }

  Future<void> _configureDB(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    // Real upgrade path for existing installs. Ensure additive schema, then run
    // one-shot data migrations (each gated by its own marker so it runs once).
    await _createCleanSchema(db);
    await _ensureV16Columns(db);
    await _ensureV20Columns(db);
    await _seedBaseData(db);
    await _runOneShotMigrations(db);
  }

  /// Lightweight, idempotent schema check run on every open AFTER create/upgrade.
  ///
  /// This is defensive only — it guarantees additive tables/columns exist even
  /// if a previous version's onUpgrade was interrupted. It MUST NOT run data
  /// backfills (those are one-shot and live in [_runOneShotMigrations]); doing
  /// so on every launch is the "migration leak" this method deliberately avoids.
  Future<void> _ensureSchema(Database db) async {
    await _createCleanSchema(db);
    await _ensureV16Columns(db);
    await _ensureV20Columns(db);
    await _runOneShotMigrations(db);
  }

  // ---------------------------------------------------------------------------
  // One-shot data migrations
  //
  // Each migration records a marker in cloud_sync_state once it has run, so it
  // executes exactly once per database regardless of how many times the app
  // opens or how the schema version was (mis)tracked by older builds.
  // ---------------------------------------------------------------------------

  static const _migrationMarkerPrefix = 'migration_done:';
  static const _v16BillingBackfillKey = 'v16_billing_backfill';
  static const _v21IndexRebuildKey = 'v21_index_rebuild';

  Future<void> _runOneShotMigrations(DatabaseExecutor executor) async {
    if (!await _isMigrationDone(executor, _v16BillingBackfillKey)) {
      await _backfillV16Billing(executor);
      await _markMigrationDone(executor, _v16BillingBackfillKey);
    }
    if (!await _isMigrationDone(executor, _v21IndexRebuildKey)) {
      await _rebuildV21Indexes(executor);
      await _markMigrationDone(executor, _v21IndexRebuildKey);
    }
  }

  Future<bool> _isMigrationDone(DatabaseExecutor executor, String key) async {
    final rows = await executor.query(
      'cloud_sync_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['$_migrationMarkerPrefix$key'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _markMigrationDone(DatabaseExecutor executor, String key) async {
    await executor.insert('cloud_sync_state', {
      'key': '$_migrationMarkerPrefix$key',
      'value': _nowIso(),
      'updated_at': _nowIso(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Pure DDL (CREATE TABLE/INDEX IF NOT EXISTS). Idempotent and safe to run on
  /// every open. Does NOT seed data or create the local shop — that lives in
  /// [_seedBaseData] so it is not repeated needlessly on each launch.
  Future<void> _createCleanSchema(DatabaseExecutor executor) async {
    await _createShopTables(executor);
    await _createSettingsTable(executor);
    await _createBillSettingsTable(executor);
    await _createReferenceTables(executor);
    await _createProductTable(executor);
    await _createCustomerTables(executor);
    await _createBillTables(executor);
    await _createInvoiceSeriesTables(executor);
    await _createPaymentTables(executor);
    await _createStockMovementTables(executor);
    await _createCloudSyncTables(executor);
  }

  /// Seed the local shop and preset reference data. Guarded so it is safe to
  /// re-run, but only invoked on create/upgrade rather than every open.
  ///
  /// Always runs inside sqflite's implicit migration transaction (or the
  /// every-open [_ensureSchema] path), so any legacy shop-id migration triggered
  /// here must not open a nested transaction — see [_activeShopId].
  Future<void> _seedBaseData(DatabaseExecutor executor) async {
    await _activeShopId(executor, inImplicitTransaction: true);
    await _seedPresetUnits(executor);
    await _seedDefaultInvoiceSeries(executor);
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
	        shop_id TEXT NOT NULL,
	        value TEXT,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        PRIMARY KEY (shop_id, key)
      )
    ''');
  }

  Future<void> _createBillSettingsTable(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS bill_settings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        invoice_title TEXT NOT NULL DEFAULT 'TAX INVOICE',
        footer_text TEXT NOT NULL DEFAULT 'Thank you for your business.',
        show_invoice_title INTEGER NOT NULL DEFAULT 1,
        show_shop_logo INTEGER NOT NULL DEFAULT 1,
        shop_logo_base64 TEXT,
        show_digital_signature INTEGER NOT NULL DEFAULT 0,
        digital_signature_base64 TEXT,
        show_shop_name INTEGER NOT NULL DEFAULT 1,
        show_shop_address INTEGER NOT NULL DEFAULT 1,
        show_shop_phone INTEGER NOT NULL DEFAULT 1,
        show_shop_email INTEGER NOT NULL DEFAULT 1,
        show_shop_gstin INTEGER NOT NULL DEFAULT 1,
        show_customer_name INTEGER NOT NULL DEFAULT 1,
        show_customer_phone INTEGER NOT NULL DEFAULT 1,
        show_customer_address INTEGER NOT NULL DEFAULT 1,
        show_customer_gstin INTEGER NOT NULL DEFAULT 1,
        show_customer_legal_name INTEGER NOT NULL DEFAULT 1,
        show_customer_trade_name INTEGER NOT NULL DEFAULT 1,
        show_customer_place_of_supply INTEGER NOT NULL DEFAULT 1,
        show_invoice_number INTEGER NOT NULL DEFAULT 1,
        show_invoice_date INTEGER NOT NULL DEFAULT 1,
        show_invoice_place_of_supply INTEGER NOT NULL DEFAULT 1,
        show_invoice_supply_type INTEGER NOT NULL DEFAULT 1,
        show_payment_details INTEGER NOT NULL DEFAULT 1,
        show_gst_breakdown INTEGER NOT NULL DEFAULT 1,
        show_item_serial_column INTEGER NOT NULL DEFAULT 1,
        show_item_name_column INTEGER NOT NULL DEFAULT 1,
        show_hsn_column INTEGER NOT NULL DEFAULT 1,
        show_quantity_column INTEGER NOT NULL DEFAULT 1,
        show_rate_column INTEGER NOT NULL DEFAULT 1,
        show_gst_percent_column INTEGER NOT NULL DEFAULT 1,
        show_gst_amount_column INTEGER NOT NULL DEFAULT 1,
        show_amount_column INTEGER NOT NULL DEFAULT 1,
        show_subtotal INTEGER NOT NULL DEFAULT 1,
        show_discount INTEGER NOT NULL DEFAULT 1,
        show_taxable_amount INTEGER NOT NULL DEFAULT 1,
        show_cgst_sgst_igst INTEGER NOT NULL DEFAULT 1,
        show_gst_total INTEGER NOT NULL DEFAULT 1,
        show_grand_total INTEGER NOT NULL DEFAULT 1,
        show_footer_text INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_bill_settings_uuid
      ON bill_settings(uuid)
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_bill_settings_shop
      ON bill_settings(shop_id)
      WHERE deleted_at IS NULL
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bill_settings_shop_updated
      ON bill_settings(shop_id, updated_at)
    ''');
  }

  Future<void> _createReferenceTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS categories(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL COLLATE NOCASE,
        hsn_code TEXT,
        hsn_type TEXT,
        hsn_description TEXT,
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
        hsn_code TEXT,
        hsn_type TEXT,
        hsn_description TEXT,
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
      CREATE UNIQUE INDEX IF NOT EXISTS idx_products_shop_product_code
      ON products(shop_id, LOWER(product_code))
      WHERE product_code IS NOT NULL AND TRIM(product_code) != '' AND deleted_at IS NULL
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_products_shop_barcode
      ON products(shop_id, LOWER(barcode))
      WHERE barcode IS NOT NULL AND TRIM(barcode) != '' AND deleted_at IS NULL
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
        gstin TEXT,
        gst_legal_name TEXT,
        gst_trade_name TEXT,
        gst_registration_status TEXT,
        gst_taxpayer_type TEXT,
        gst_verified_at TEXT,
        gst_source TEXT,
        place_of_supply_state_code TEXT,
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
        invoice_series_uuid TEXT,
        bill_type TEXT NOT NULL DEFAULT 'b2c',
        customer_id INTEGER,
        customer_uuid TEXT,
        customer_name TEXT NOT NULL DEFAULT 'Walk-in Customer',
        customer_phone TEXT,
        customer_gstin TEXT,
        customer_gst_legal_name TEXT,
        customer_gst_trade_name TEXT,
        customer_address_snapshot TEXT,
        place_of_supply_state_code TEXT,
        subtotal_amount REAL NOT NULL DEFAULT 0,
        discount_percent REAL NOT NULL DEFAULT 0,
        discount_amount REAL NOT NULL DEFAULT 0,
        profit_commission_percent REAL NOT NULL DEFAULT 0,
        taxable_amount REAL NOT NULL DEFAULT 0,
        cgst_amount REAL NOT NULL DEFAULT 0,
        sgst_amount REAL NOT NULL DEFAULT 0,
        igst_amount REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL,
        item_count INTEGER NOT NULL,
        is_paid INTEGER NOT NULL DEFAULT 1,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        paid_amount REAL NOT NULL DEFAULT 0,
        balance_due REAL NOT NULL DEFAULT 0,
        payment_status TEXT NOT NULL DEFAULT 'unpaid',
        lifecycle_status TEXT NOT NULL DEFAULT 'finalized',
        cancelled_at TEXT,
        cancel_reason TEXT,
        duplicated_from_bill_uuid TEXT,
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
        hsn_code_snapshot TEXT,
        hsn_type_snapshot TEXT,
        unit_name TEXT,
        purchase_price_snapshot REAL NOT NULL DEFAULT 0,
        selling_price_snapshot REAL NOT NULL DEFAULT 0,
        cost_snapshot REAL NOT NULL DEFAULT 0,
        profit_snapshot REAL NOT NULL DEFAULT 0,
        commission_snapshot REAL NOT NULL DEFAULT 0,
        gst_snapshot REAL NOT NULL DEFAULT 0,
        gst_percent_snapshot REAL,
        taxable_value_snapshot REAL NOT NULL DEFAULT 0,
        cgst_amount_snapshot REAL NOT NULL DEFAULT 0,
        sgst_amount_snapshot REAL NOT NULL DEFAULT 0,
        igst_amount_snapshot REAL NOT NULL DEFAULT 0,
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

  Future<void> _createInvoiceSeriesTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS invoice_series(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        name TEXT NOT NULL,
        format_template TEXT NOT NULL,
        sequence_padding INTEGER NOT NULL DEFAULT 4,
        reset_period TEXT NOT NULL DEFAULT 'financial_year',
        allocation_mode TEXT NOT NULL DEFAULT 'local_device',
        next_sequence INTEGER NOT NULL DEFAULT 1,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        device_token_required INTEGER NOT NULL DEFAULT 1,
        last_sequence_key TEXT,
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_invoice_series_uuid
      ON invoice_series(uuid)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_invoice_series_shop_updated
      ON invoice_series(shop_id, updated_at)
    ''');
  }

  Future<void> _createPaymentTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS bill_payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        shop_id TEXT NOT NULL,
        bill_uuid TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        payment_reference TEXT,
        notes TEXT,
        received_at TEXT NOT NULL,
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_bill_payments_uuid
      ON bill_payments(uuid)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bill_payments_bill_uuid
      ON bill_payments(bill_uuid)
    ''');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bill_payments_shop_updated
      ON bill_payments(shop_id, updated_at)
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
	        supplier_id INTEGER,
	        supplier_uuid TEXT,
	        source_document_type TEXT,
	        source_document_id INTEGER,
	        source_document_uuid TEXT,
	        import_batch_key TEXT,
	        import_row_number INTEGER,
	        notes TEXT,
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
	        FOREIGN KEY (product_id) REFERENCES products(id),
	        FOREIGN KEY (supplier_id) REFERENCES suppliers(id)
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
	      ON stock_movements(source_document_type, source_document_uuid)
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

  Future<void> _createCloudSyncTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS cloud_sync_state(
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _seedPresetUnits(DatabaseExecutor executor) async {
    final now = _nowIso();
    final shopId = await _activeShopId(executor);
    for (final unit in Product.presetUnits) {
      await executor.insert('units', {
        'uuid': _newUuid(),
        'shop_id': shopId,
        'name': unit,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _seedDefaultInvoiceSeries(DatabaseExecutor executor) async {
    final shopId = await _activeShopId(executor);
    final existing = await executor.query(
      'invoice_series',
      columns: ['id'],
      where: 'shop_id = ? AND deleted_at IS NULL',
      whereArgs: [shopId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    final now = _nowIso();
    await executor.insert('invoice_series', {
      'uuid': _newUuid(),
      'shop_id': shopId,
      'name': 'Default',
      'format_template': 'INV-{YYYY}{MM}{DD}-{SEQ}',
      'sequence_padding': 4,
      'reset_period': 'daily',
      'allocation_mode': 'local_device',
      'next_sequence': 1,
      'is_default': 1,
      'is_active': 1,
      'device_token_required': 1,
      'device_id': 'local',
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<void> _ensureV16Columns(DatabaseExecutor executor) async {
    await _ensureColumns(executor, 'categories', {
      'hsn_code': 'TEXT',
      'hsn_type': 'TEXT',
      'hsn_description': 'TEXT',
    });
    await _ensureColumns(executor, 'products', {
      'hsn_code': 'TEXT',
      'hsn_type': 'TEXT',
      'hsn_description': 'TEXT',
    });
    await _ensureColumns(executor, 'customers', {
      'gstin': 'TEXT',
      'gst_legal_name': 'TEXT',
      'gst_trade_name': 'TEXT',
      'gst_registration_status': 'TEXT',
      'gst_taxpayer_type': 'TEXT',
      'gst_verified_at': 'TEXT',
      'gst_source': 'TEXT',
      'place_of_supply_state_code': 'TEXT',
    });
    await _ensureColumns(executor, 'bills', {
      'invoice_series_uuid': 'TEXT',
      'bill_type': "TEXT NOT NULL DEFAULT 'b2c'",
      'customer_gstin': 'TEXT',
      'customer_gst_legal_name': 'TEXT',
      'customer_gst_trade_name': 'TEXT',
      'customer_address_snapshot': 'TEXT',
      'place_of_supply_state_code': 'TEXT',
      'taxable_amount': 'REAL NOT NULL DEFAULT 0',
      'cgst_amount': 'REAL NOT NULL DEFAULT 0',
      'sgst_amount': 'REAL NOT NULL DEFAULT 0',
      'igst_amount': 'REAL NOT NULL DEFAULT 0',
      'paid_amount': 'REAL NOT NULL DEFAULT 0',
      'balance_due': 'REAL NOT NULL DEFAULT 0',
      'payment_status': "TEXT NOT NULL DEFAULT 'unpaid'",
      'lifecycle_status': "TEXT NOT NULL DEFAULT 'finalized'",
      'cancelled_at': 'TEXT',
      'cancel_reason': 'TEXT',
      'duplicated_from_bill_uuid': 'TEXT',
    });
    await _ensureColumns(executor, 'bill_items', {
      'hsn_code_snapshot': 'TEXT',
      'hsn_type_snapshot': 'TEXT',
      'gst_percent_snapshot': 'REAL',
      'taxable_value_snapshot': 'REAL NOT NULL DEFAULT 0',
      'cgst_amount_snapshot': 'REAL NOT NULL DEFAULT 0',
      'sgst_amount_snapshot': 'REAL NOT NULL DEFAULT 0',
      'igst_amount_snapshot': 'REAL NOT NULL DEFAULT 0',
    });
    await _ensureColumns(executor, 'bill_settings', {
      'show_invoice_title': 'INTEGER NOT NULL DEFAULT 1',
      'show_shop_name': 'INTEGER NOT NULL DEFAULT 1',
      'show_customer_name': 'INTEGER NOT NULL DEFAULT 1',
      'show_customer_gstin': 'INTEGER NOT NULL DEFAULT 1',
      'show_customer_legal_name': 'INTEGER NOT NULL DEFAULT 1',
      'show_customer_trade_name': 'INTEGER NOT NULL DEFAULT 1',
      'show_customer_place_of_supply': 'INTEGER NOT NULL DEFAULT 1',
      'show_invoice_number': 'INTEGER NOT NULL DEFAULT 1',
      'show_invoice_date': 'INTEGER NOT NULL DEFAULT 1',
      'show_invoice_place_of_supply': 'INTEGER NOT NULL DEFAULT 1',
      'show_invoice_supply_type': 'INTEGER NOT NULL DEFAULT 1',
      'show_item_serial_column': 'INTEGER NOT NULL DEFAULT 1',
      'show_item_name_column': 'INTEGER NOT NULL DEFAULT 1',
      'show_quantity_column': 'INTEGER NOT NULL DEFAULT 1',
      'show_rate_column': 'INTEGER NOT NULL DEFAULT 1',
      'show_gst_percent_column': 'INTEGER NOT NULL DEFAULT 1',
      'show_gst_amount_column': 'INTEGER NOT NULL DEFAULT 1',
      'show_amount_column': 'INTEGER NOT NULL DEFAULT 1',
      'show_subtotal': 'INTEGER NOT NULL DEFAULT 1',
      'show_discount': 'INTEGER NOT NULL DEFAULT 1',
      'show_taxable_amount': 'INTEGER NOT NULL DEFAULT 1',
      'show_cgst_sgst_igst': 'INTEGER NOT NULL DEFAULT 1',
      'show_gst_total': 'INTEGER NOT NULL DEFAULT 1',
      'show_grand_total': 'INTEGER NOT NULL DEFAULT 1',
      'show_footer_text': 'INTEGER NOT NULL DEFAULT 1',
    });
  }

  /// Columns added by the v20 stock_movements redesign. Installs that created
  /// the table before v20 (DB <= 16) never get them from CREATE TABLE IF NOT
  /// EXISTS, and every stock write references them — without this, upgraded
  /// devices throw "no such column" on the first bill or purchase entry.
  Future<void> _ensureV20Columns(DatabaseExecutor executor) async {
    await _ensureColumns(executor, 'stock_movements', {
      'supplier_id': 'INTEGER REFERENCES suppliers(id)',
      'supplier_uuid': 'TEXT',
      'source_document_type': 'TEXT',
      'source_document_id': 'INTEGER',
      'source_document_uuid': 'TEXT',
      'import_row_number': 'INTEGER',
    });
  }

  /// v20 changed these index definitions but kept their names, so the CREATE
  /// INDEX IF NOT EXISTS in [_createCleanSchema] silently keeps the old
  /// definitions on upgraded devices. Drop and recreate them once. Duplicate
  /// product codes/barcodes that the old non-unique indexes allowed are
  /// cleared (the newest row keeps the value) so the UNIQUE indexes can build.
  Future<void> _rebuildV21Indexes(DatabaseExecutor executor) async {
    await executor.execute('DROP INDEX IF EXISTS idx_stock_movements_source');
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_stock_movements_source
      ON stock_movements(source_document_type, source_document_uuid)
    ''');

    await _clearDuplicateProductValues(executor, 'product_code');
    await executor.execute(
      'DROP INDEX IF EXISTS idx_products_shop_product_code',
    );
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_products_shop_product_code
      ON products(shop_id, LOWER(product_code))
      WHERE product_code IS NOT NULL AND TRIM(product_code) != '' AND deleted_at IS NULL
    ''');

    await _clearDuplicateProductValues(executor, 'barcode');
    await executor.execute('DROP INDEX IF EXISTS idx_products_shop_barcode');
    await executor.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_products_shop_barcode
      ON products(shop_id, LOWER(barcode))
      WHERE barcode IS NOT NULL AND TRIM(barcode) != '' AND deleted_at IS NULL
    ''');
  }

  /// The predicate and grouping here must mirror the partial UNIQUE index
  /// expression exactly — that is what guarantees the index build cannot fail
  /// after this runs.
  Future<void> _clearDuplicateProductValues(
    DatabaseExecutor executor,
    String column,
  ) async {
    await executor.rawUpdate(
      '''
      UPDATE products
      SET $column = NULL, updated_at = ?
      WHERE $column IS NOT NULL AND TRIM($column) != '' AND deleted_at IS NULL
        AND id NOT IN (
          SELECT MAX(id) FROM products
          WHERE $column IS NOT NULL AND TRIM($column) != '' AND deleted_at IS NULL
          GROUP BY shop_id, LOWER($column)
        )
    ''',
      [_nowIso()],
    );
  }

  Future<void> _ensureColumns(
    DatabaseExecutor executor,
    String table,
    Map<String, String> columns,
  ) async {
    final existing = await executor.rawQuery('PRAGMA table_info($table)');
    final names = existing.map((row) => row['name']?.toString()).toSet();
    for (final entry in columns.entries) {
      if (names.contains(entry.key)) continue;
      await executor.execute(
        'ALTER TABLE $table ADD COLUMN ${entry.key} ${entry.value}',
      );
    }
  }

  Future<void> _backfillV16Billing(DatabaseExecutor executor) async {
    final now = _nowIso();
    await executor.rawUpdate('''
      UPDATE bill_items
      SET taxable_value_snapshot = MAX(selling_price_snapshot - gst_snapshot, 0)
      WHERE taxable_value_snapshot = 0
    ''');
    await executor.rawUpdate('''
      UPDATE bills
      SET paid_amount = CASE WHEN is_paid = 1 THEN total_amount ELSE 0 END,
          balance_due = CASE WHEN is_paid = 1 THEN 0 ELSE total_amount END,
          payment_status = CASE WHEN is_paid = 1 THEN 'paid' ELSE 'unpaid' END,
          taxable_amount = CASE WHEN taxable_amount = 0 THEN total_amount ELSE taxable_amount END
      WHERE payment_status = 'unpaid' AND paid_amount = 0 AND balance_due = 0
    ''');
    final paidBills = await executor.query(
      'bills',
      columns: [
        'uuid',
        'shop_id',
        'total_amount',
        'payment_method',
        'created_at',
      ],
      where:
          "deleted_at IS NULL AND is_paid = 1 AND uuid NOT IN (SELECT bill_uuid FROM bill_payments WHERE deleted_at IS NULL)",
    );
    for (final bill in paidBills) {
      await executor.insert('bill_payments', {
        'uuid': _newUuid(),
        'shop_id': bill['shop_id'] ?? await _activeShopId(executor),
        'bill_uuid': bill['uuid'],
        'amount': bill['total_amount'],
        'payment_method': bill['payment_method'] ?? 'cash',
        'notes': 'Migrated from paid status',
        'received_at': bill['created_at'] ?? now,
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
        gstin: bill['customer_gstin']?.toString(),
        gstLegalName: bill['customer_gst_legal_name']?.toString(),
        gstTradeName: bill['customer_gst_trade_name']?.toString(),
        address: bill['customer_address_snapshot']?.toString(),
        placeOfSupplyStateCode: bill['place_of_supply_state_code']?.toString(),
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
        'gstin': ledger.gstin,
        'gst_legal_name': ledger.gstLegalName,
        'gst_trade_name': ledger.gstTradeName,
        'address': ledger.address,
        'gst_source': ledger.gstin == null ? null : 'manual',
        'gst_verified_at': ledger.gstin == null ? null : now,
        'place_of_supply_state_code': ledger.placeOfSupplyStateCode,
        'updated_at': now,
      };
      if (existingId != null) {
        data
          ..remove('gstin')
          ..remove('gst_legal_name')
          ..remove('gst_trade_name')
          ..remove('address')
          ..remove('gst_source')
          ..remove('gst_verified_at')
          ..remove('place_of_supply_state_code');
      }

      final customerId =
          existingId ??
          await executor.insert('customers', {
            ...data,
            'uuid': _newUuid(),
            'shop_id': await _activeShopId(executor),
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
  String? gstin;
  String? gstLegalName;
  String? gstTradeName;
  String? address;
  String? placeOfSupplyStateCode;

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
    String? gstin,
    String? gstLegalName,
    String? gstTradeName,
    String? address,
    String? placeOfSupplyStateCode,
  }) {
    billIds.add(billId);
    totalPurchaseAmount += totalAmount;
    billCount += 1;
    if (createdAt.compareTo(lastPurchaseAt) >= 0) {
      lastPurchaseAt = createdAt;
      if (name != 'Walk-in Customer') {
        this.name = name;
      }
      this.gstin = _normaliseName(gstin)?.toUpperCase();
      this.gstLegalName = _normaliseName(gstLegalName);
      this.gstTradeName = _normaliseName(gstTradeName);
      this.address = _normaliseName(address);
      this.placeOfSupplyStateCode = _normaliseName(placeOfSupplyStateCode);
    }
  }
}
