part of 'database_helper.dart';

mixin DatabaseSchema {
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(
      path,
      version: 24,
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
    await _markMigrationDone(db, _gstInvoiceNumberKey);
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
    await _ensureInventoryColumns(db);
    await _ensureV22Columns(db);
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
    await _ensureInventoryColumns(db);
    await _ensureV22Columns(db);
    await _runOneShotMigrations(db);
    await _ensureSyncTracking(db);
  }

  // ---------------------------------------------------------------------------
  // Cloud change tracking
  //
  // Every synced row carries sync_dirty: 1 = changed on this device and not
  // yet uploaded, 0 = in sync. SQLite triggers maintain it, so no write path
  // can forget to:
  // - a local insert defaults to 1;
  // - a local update of any synced column sets it to 1;
  // - a row written by the cloud import sets sync_dirty = 2, which a trigger
  //   turns into 0 (it came from the cloud, nothing to upload).
  // Derived columns (stock cache, customer totals, payment summary...) are
  // recomputed on every device, so changing them never queues an upload.
  // ---------------------------------------------------------------------------

  static const syncDirtyFromCloud = 2;

  static const _syncTrackedTables = ['shops', ...storelyCloudTables];

  static const _localOnlyColumns = <String, Set<String>>{
    'products': {'quantity_cache', 'selling_price'},
    'customers': {'total_purchase_amount', 'bill_count', 'last_purchase_at'},
    'invoice_series': {'next_sequence', 'last_sequence_key'},
    'bills': {
      'paid_amount',
      'balance_due',
      'payment_status',
      'is_paid',
      'payment_method',
      'customer_id',
    },
  };

  Future<void> _ensureSyncTracking(DatabaseExecutor executor) async {
    for (final table in _syncTrackedTables) {
      await _ensureColumns(executor, table, {
        'sync_dirty': 'INTEGER NOT NULL DEFAULT 1',
      });
      final info = await executor.rawQuery('PRAGMA table_info($table)');
      final excluded = {'id', 'sync_dirty', ...?_localOnlyColumns[table]};
      final tracked = info
          .map((row) => row['name'].toString())
          .where((name) => !excluded.contains(name))
          .join(', ');
      await executor.execute('DROP TRIGGER IF EXISTS trg_${table}_dirty');
      await executor.execute('''
        CREATE TRIGGER trg_${table}_dirty
        AFTER UPDATE OF $tracked ON $table
        WHEN NEW.sync_dirty = OLD.sync_dirty
        BEGIN
          UPDATE $table SET sync_dirty = 1 WHERE rowid = NEW.rowid;
        END
      ''');
      await executor.execute(
        'DROP TRIGGER IF EXISTS trg_${table}_from_cloud_update',
      );
      await executor.execute('''
        CREATE TRIGGER trg_${table}_from_cloud_update
        AFTER UPDATE OF sync_dirty ON $table
        WHEN NEW.sync_dirty = $syncDirtyFromCloud
        BEGIN
          UPDATE $table SET sync_dirty = 0 WHERE rowid = NEW.rowid;
        END
      ''');
      await executor.execute(
        'DROP TRIGGER IF EXISTS trg_${table}_from_cloud_insert',
      );
      await executor.execute('''
        CREATE TRIGGER trg_${table}_from_cloud_insert
        AFTER INSERT ON $table
        WHEN NEW.sync_dirty = $syncDirtyFromCloud
        BEGIN
          UPDATE $table SET sync_dirty = 0 WHERE rowid = NEW.rowid;
        END
      ''');
    }
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
  static const _gstInvoiceNumberKey = 'v2_gst_invoice_number_default';

  Future<void> _runOneShotMigrations(DatabaseExecutor executor) async {
    if (!await _isMigrationDone(executor, _v16BillingBackfillKey)) {
      await _backfillV16Billing(executor);
      await _markMigrationDone(executor, _v16BillingBackfillKey);
    }
    if (!await _isMigrationDone(executor, _v21IndexRebuildKey)) {
      await _rebuildV21Indexes(executor);
      await _markMigrationDone(executor, _v21IndexRebuildKey);
    }
    if (!await _isMigrationDone(executor, _gstInvoiceNumberKey)) {
      await _moveLegacyInvoiceDefault(executor);
      await _markMigrationDone(executor, _gstInvoiceNumberKey);
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
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS purchase_documents(
        uuid TEXT PRIMARY KEY, shop_id TEXT NOT NULL, payload TEXT NOT NULL,
        origin TEXT NOT NULL, sync_state TEXT NOT NULL
          CHECK(sync_state IN ('pending','synced','error','local')),
        last_error TEXT, created_at TEXT NOT NULL, purchase_date TEXT NOT NULL, deleted_at TEXT
      )
    ''');
    await executor.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_documents_shop ON purchase_documents(shop_id, purchase_date, uuid)',
    );
    await executor.execute('''CREATE TABLE IF NOT EXISTS purchase_drafts(
      uuid TEXT PRIMARY KEY, shop_id TEXT NOT NULL, revision INTEGER NOT NULL,
      status TEXT NOT NULL CHECK(status IN ('editing','posted')), payload TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )''');
    await executor.execute(
      "CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_draft_active ON purchase_drafts(shop_id) WHERE status = 'editing'",
    );
    await _createCloudSyncTables(executor);
    await _createHeldBillTables(executor);
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS user_preferences(
        id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL UNIQUE, shop_id TEXT NOT NULL,
        owner_user_id TEXT NOT NULL, key TEXT NOT NULL, value TEXT NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
        UNIQUE(shop_id, owner_user_id, key)
      )
    ''');
    await _createExpenseTables(executor);
    await _createAuditTables(executor);
  }

  /// Device-owned cart backups. Restored carts from another device are read-only.
  Future<void> _createHeldBillTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS held_bills(
        id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT,
        shop_id TEXT NOT NULL, owner_user_id TEXT, origin_device_id TEXT NOT NULL DEFAULT '',
        kind TEXT NOT NULL DEFAULT 'held', label TEXT NOT NULL, items_json TEXT NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
      )
    ''');
  }

  Future<void> _ensureV22Columns(DatabaseExecutor executor) async {
    await _ensureColumns(executor, 'held_bills', {
      'uuid': 'TEXT',
      'owner_user_id': 'TEXT',
      'origin_device_id': "TEXT NOT NULL DEFAULT ''",
      'deleted_at': 'TEXT',
    });
    final device = await executor.query(
      'cloud_sync_state',
      where: 'key = ?',
      whereArgs: ['device_id'],
    );
    final deviceId = device.isEmpty
        ? _newUuid()
        : device.single['value'] as String;
    if (device.isEmpty) {
      await executor.insert('cloud_sync_state', {
        'key': 'device_id',
        'value': deviceId,
        'updated_at': _nowIso(),
      });
    }
    final legacy = await executor.query(
      'held_bills',
      where: "uuid IS NULL OR uuid = '' OR origin_device_id = ''",
    );
    for (final row in legacy) {
      await executor.update(
        'held_bills',
        {
          'uuid': (row['uuid'] as String?)?.isNotEmpty == true
              ? row['uuid']
              : _newUuid(),
          'origin_device_id': deviceId,
          'created_at': DateTime.parse(
            row['created_at'] as String,
          ).toUtc().toIso8601String(),
          'updated_at': DateTime.parse(
            row['updated_at'] as String,
          ).toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await executor.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_held_uuid ON held_bills(uuid)',
    );
    await executor.execute(
      'CREATE INDEX IF NOT EXISTS idx_held_device ON held_bills(shop_id, origin_device_id, kind)',
    );
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
        round_off_total INTEGER NOT NULL DEFAULT 1,
        paper_size TEXT NOT NULL DEFAULT 'a4',
        upi_id TEXT,
        show_upi_qr INTEGER NOT NULL DEFAULT 1,
        show_amount_in_words INTEGER NOT NULL DEFAULT 1,
        show_hsn_summary INTEGER NOT NULL DEFAULT 1,
        terms_text TEXT,
        bank_details TEXT,
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
        round_off_amount REAL NOT NULL DEFAULT 0,
        document_type TEXT NOT NULL DEFAULT 'invoice',
        original_bill_uuid TEXT,
        original_bill_number TEXT,
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
        original_item_uuid TEXT,
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
      'format_template': InvoiceNumbering.defaultTemplate,
      'sequence_padding': 4,
      'reset_period': InvoiceNumbering.defaultResetPeriod,
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
      'round_off_amount': 'REAL NOT NULL DEFAULT 0',
      'document_type': "TEXT NOT NULL DEFAULT 'invoice'",
      'original_bill_uuid': 'TEXT',
      'original_bill_number': 'TEXT',
      'paid_amount': 'REAL NOT NULL DEFAULT 0',
      'balance_due': 'REAL NOT NULL DEFAULT 0',
      'payment_status': "TEXT NOT NULL DEFAULT 'unpaid'",
      'lifecycle_status': "TEXT NOT NULL DEFAULT 'finalized'",
      'cancelled_at': 'TEXT',
      'cancel_reason': 'TEXT',
      'duplicated_from_bill_uuid': 'TEXT',
    });
    await _ensureColumns(executor, 'bill_items', {
      'original_item_uuid': 'TEXT',
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
      'round_off_total': 'INTEGER NOT NULL DEFAULT 1',
      'paper_size': "TEXT NOT NULL DEFAULT 'a4'",
      'upi_id': "TEXT",
      'show_upi_qr': "INTEGER NOT NULL DEFAULT 1",
      'show_amount_in_words': "INTEGER NOT NULL DEFAULT 1",
      'show_hsn_summary': "INTEGER NOT NULL DEFAULT 1",
      'terms_text': "TEXT",
      'bank_details': "TEXT",
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

  /// 2.0 inventory controls: per-product stock tracking and reorder level,
  /// and a reason on manual stock adjustments.
  Future<void> _ensureInventoryColumns(DatabaseExecutor executor) async {
    await _ensureColumns(executor, 'products', {
      'track_stock': 'INTEGER NOT NULL DEFAULT 1',
      'reorder_level': 'REAL',
    });
    await _ensureColumns(executor, 'stock_movements', {
      'reason': 'TEXT',
      'batch_no': 'TEXT',
      'expiry_date': 'TEXT',
    });
    await _ensureColumns(executor, 'products', {'mrp_price': 'REAL'});
    await _ensureColumns(executor, 'bill_items', {'mrp_snapshot': 'REAL'});
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

  /// The pre-2.0 default bill number (INV-20261023-0001) is 17 characters,
  /// over the GST limit of 16, and resets daily. Series nobody customised
  /// move to the GST-safe financial-year default; custom patterns are kept.
  Future<void> _moveLegacyInvoiceDefault(DatabaseExecutor executor) async {
    await executor.update(
      'invoice_series',
      {
        'format_template': InvoiceNumbering.defaultTemplate,
        'reset_period': InvoiceNumbering.defaultResetPeriod,
        'next_sequence': 1,
        'last_sequence_key': null,
        'updated_at': _nowIso(),
      },
      where: 'format_template = ? AND deleted_at IS NULL',
      whereArgs: [InvoiceNumbering.legacyTemplate],
    );
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
    final now = _nowIso();

    // Aggregates (total, count, last purchase) are derived from bills on
    // every device, so they are written only when they change and never bump
    // updated_at; bills are re-linked only when their link is wrong. This
    // runs every time customers load, and used to re-stamp every customer and
    // bill, which made them all "newer" and overwrote other phones' edits.
    final customersByPhone = {
      for (final customer in existingCustomers)
        if (customer['phone'] != null) customer['phone'] as String: customer,
    };
    for (final customer in existingCustomers) {
      final phone = customer['phone'] as String?;
      if (phone != null && ledgers.containsKey(phone)) continue;
      await _setCustomerAggregates(
        executor,
        customer,
        total: 0,
        count: 0,
        lastPurchaseAt: null,
      );
    }

    for (final ledger in ledgers.values) {
      final existing = customersByPhone[ledger.phone];
      int customerId;
      String customerUuid;
      if (existing == null) {
        customerUuid = _newUuid();
        customerId = await executor.insert('customers', {
          'uuid': customerUuid,
          'shop_id': await _activeShopId(executor),
          'name': ledger.name,
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
          'created_at': now,
          'updated_at': now,
        });
      } else {
        customerId = existing['id'] as int;
        customerUuid = existing['uuid'] as String;
        await _setCustomerAggregates(
          executor,
          existing,
          total: ledger.totalPurchaseAmount,
          count: ledger.billCount,
          lastPurchaseAt: ledger.lastPurchaseAt,
        );
      }

      for (final billId in ledger.billIds) {
        await executor.update(
          'bills',
          {'customer_id': customerId, 'customer_uuid': customerUuid},
          where: 'id = ? AND (customer_uuid IS NOT ? OR customer_id IS NOT ?)',
          whereArgs: [billId, customerUuid, customerId],
        );
      }
    }
  }

  Future<void> _setCustomerAggregates(
    DatabaseExecutor executor,
    Map<String, Object?> customer, {
    required double total,
    required int count,
    required String? lastPurchaseAt,
  }) async {
    final currentTotal =
        (customer['total_purchase_amount'] as num?)?.toDouble() ?? 0;
    if ((currentTotal - total).abs() < 0.005 &&
        (customer['bill_count'] as num?)?.toInt() == count &&
        customer['last_purchase_at'] == lastPurchaseAt) {
      return;
    }
    await executor.update(
      'customers',
      {
        'total_purchase_amount': total,
        'bill_count': count,
        'last_purchase_at': lastPurchaseAt,
      },
      where: 'id = ?',
      whereArgs: [customer['id']],
    );
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
