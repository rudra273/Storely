part of 'database_helper.dart';

mixin DatabaseSettings {
  static const _shopNameKey = 'shop_name';
  static const _lowStockThresholdKey = 'low_stock_threshold';
  static const _defaultGstPercentKey = 'default_gst_percent';
  static const _defaultOverheadCostKey = 'default_overhead_cost';
  static const _defaultProfitMarginPercentKey = 'default_profit_margin_percent';
  static const _gstRegisteredKey = 'gst_registered';
  static const _showPurchasePriceGloballyKey = 'show_purchase_price_globally';

  Future<Database> get database;
  Future<void> _seedDefaultInvoiceSeries(DatabaseExecutor executor);

  Future<String?> getShopName() async {
    final profile = await getShopProfile();
    if (profile != null) return profile.name;
    final db = await database;
    final shopId = await _activeShopId(db);
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'shop_id = ? AND key = ? AND deleted_at IS NULL',
      whereArgs: [shopId, _shopNameKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value'] as String?;
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveShopName(String name) async {
    await _requireAdminMutation();
    final current = await getShopProfile();
    if (current != null) {
      await saveShopProfile(
        ShopProfile(
          id: current.id,
          uuid: current.uuid,
          name: name,
          phone: current.phone,
          email: current.email,
          gstin: current.gstin,
          address: current.address,
          gstRegistered: current.gstRegistered,
          createdAt: current.createdAt,
          updatedAt: current.updatedAt,
        ),
      );
      return;
    }
    final db = await database;
    final shopId = await _activeShopId(db);
    final value = _normaliseName(name);
    if (value == null) {
      throw ArgumentError('Shop name is required');
    }
    await db.insert('app_settings', {
      'key': _shopNameKey,
      'shop_id': shopId,
      'value': value,
      'updated_at': _nowIso(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ShopProfile?> getShopProfile() async {
    final db = await database;
    final pricing = await getGlobalPricingSettings();
    final shopId = await _activeShopId(db);
    final rows = await db.query(
      'shops',
      where: 'deleted_at IS NULL AND uuid = ?',
      whereArgs: [shopId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return ShopProfile.fromMap(
        rows.single,
        gstRegistered: pricing.gstRegistered,
      );
    }

    final legacyName = await _getLegacyShopName(db);
    if (legacyName == null) return null;
    return ShopProfile(name: legacyName, gstRegistered: pricing.gstRegistered);
  }

  Future<void> saveShopProfile(ShopProfile profile) async {
    await _requireAdminMutation();
    final db = await database;
    final name = _normaliseName(profile.name);
    if (name == null) throw ArgumentError('Shop name is required');

    await db.transaction((txn) async {
      final shopId = await _activeShopId(txn);
      final now = _nowIso();
      final existing = await txn.query(
        'shops',
        columns: ['id', 'uuid', 'created_at'],
        where: 'uuid = ?',
        whereArgs: [shopId],
        limit: 1,
      );
      final map = profile.toMap()
        ..remove('id')
        ..['uuid'] = shopId
        ..['name'] = name
        ..['updated_at'] = now;
      if (existing.isEmpty) {
        map['created_at'] = profile.createdAt.toIso8601String();
        await txn.insert('shops', map);
      } else {
        map['created_at'] = existing.single['created_at'];
        await txn.update(
          'shops',
          map,
          where: 'id = ?',
          whereArgs: [existing.single['id']],
        );
      }
      await _saveSetting(txn, _shopNameKey, name);
      await _saveSetting(
        txn,
        _gstRegisteredKey,
        profile.gstRegistered ? '1' : '0',
      );
    });
    notifyDatabaseChanged();
  }

  Future<String?> _getLegacyShopName(DatabaseExecutor executor) async {
    final rows = await executor.query(
      'app_settings',
      columns: ['value'],
      where: 'shop_id = ? AND key = ? AND deleted_at IS NULL',
      whereArgs: [await _activeShopId(executor), _shopNameKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value'] as String?;
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<int> getLowStockThreshold() async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'shop_id = ? AND key = ? AND deleted_at IS NULL',
      whereArgs: [shopId, _lowStockThresholdKey],
      limit: 1,
    );
    if (rows.isEmpty) return 5;
    final value = int.tryParse(rows.first['value']?.toString() ?? '');
    return value == null || value < 0 ? 5 : value;
  }

  Future<void> saveLowStockThreshold(int value) async {
    await _requireAdminMutation();
    if (value < 0) {
      throw ArgumentError('Minimum stock cannot be negative');
    }
    final db = await database;
    final shopId = await _activeShopId(db);
    await db.insert('app_settings', {
      'key': _lowStockThresholdKey,
      'shop_id': shopId,
      'value': value.toString(),
      'updated_at': _nowIso(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    notifyDatabaseChanged();
  }

  Future<List<String>> getUnits() async {
    final db = await database;
    final rows = await db.query(
      'units',
      columns: ['name'],
      where: 'deleted_at IS NULL',
      orderBy: 'name ASC',
    );
    final values = <String>{...Product.presetUnits};
    for (final row in rows) {
      final name = _normaliseName(row['name']?.toString());
      if (name != null) values.add(name);
    }

    final presets = Product.presetUnits
        .where((unit) => values.any((v) => v.toLowerCase() == unit))
        .toList();
    final custom = values.where((unit) => !_isPresetUnit(unit)).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [...presets, ...custom];
  }

  Future<void> addUnitOption(String name) async {
    await _requireAdminMutation();
    final db = await database;
    await _ensureUnit(db, name);
    notifyDatabaseChanged();
  }

  Future<void> deleteUnitOption(String name) async {
    await _requireAdminMutation();
    final db = await database;
    final value = _normaliseName(name);
    if (value == null) return;
    await db.update(
      'units',
      {'deleted_at': _nowIso(), 'updated_at': _nowIso()},
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [value],
    );
    notifyDatabaseChanged();
  }

  Future<GlobalPricingSettings> getGlobalPricingSettings() async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final rows = await db.query(
      'app_settings',
      where: 'shop_id = ? AND deleted_at IS NULL',
      whereArgs: [shopId],
    );
    final values = {
      for (final row in rows) row['key'] as String: row['value']?.toString(),
    };
    return GlobalPricingSettings(
      defaultGstPercent:
          double.tryParse(values[_defaultGstPercentKey] ?? '') ?? 18,
      defaultOverheadCost:
          double.tryParse(values[_defaultOverheadCostKey] ?? '') ?? 0,
      defaultProfitMarginPercent:
          double.tryParse(values[_defaultProfitMarginPercentKey] ?? '') ?? 0,
      gstRegistered: values[_gstRegisteredKey] == '1',
      showPurchasePriceGlobally: values[_showPurchasePriceGloballyKey] == '1',
    );
  }

  Future<void> saveGlobalPricingSettings(GlobalPricingSettings settings) async {
    await _requireAdminMutation();
    final db = await database;
    await db.transaction((txn) async {
      await _saveSetting(
        txn,
        _defaultGstPercentKey,
        settings.defaultGstPercent.toString(),
      );
      await _saveSetting(
        txn,
        _defaultOverheadCostKey,
        settings.defaultOverheadCost.toString(),
      );
      await _saveSetting(
        txn,
        _defaultProfitMarginPercentKey,
        settings.defaultProfitMarginPercent.toString(),
      );
      await _saveSetting(
        txn,
        _gstRegisteredKey,
        settings.gstRegistered ? '1' : '0',
      );
      await _saveSetting(
        txn,
        _showPurchasePriceGloballyKey,
        settings.showPurchasePriceGlobally ? '1' : '0',
      );
    });
    notifyDatabaseChanged();
  }

  Future<BillSettings> getBillSettings() async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final rows = await db.query(
      'bill_settings',
      where: 'shop_id = ? AND deleted_at IS NULL',
      whereArgs: [shopId],
      limit: 1,
    );
    if (rows.isNotEmpty) return BillSettings.fromMap(rows.single);
    final now = DateTime.now().toUtc();
    return BillSettings(shopId: shopId, createdAt: now, updatedAt: now);
  }

  Future<void> saveBillSettings(BillSettings settings) async {
    await _requireAdminMutation();
    final db = await database;
    await db.transaction((txn) async {
      final shopId = await _activeShopId(txn);
      final now = _nowIso();
      final existing = await txn.query(
        'bill_settings',
        columns: ['id', 'uuid', 'created_at'],
        where: 'shop_id = ? AND deleted_at IS NULL',
        whereArgs: [shopId],
        limit: 1,
      );
      final createdAt = existing.isEmpty
          ? now
          : existing.single['created_at']?.toString() ?? now;
      final uuid = existing.isEmpty
          ? (settings.uuid.isEmpty ? _newUuid() : settings.uuid)
          : existing.single['uuid'] as String;
      final map =
          settings
              .copyWith(
                id: existing.isEmpty ? null : existing.single['id'] as int?,
                uuid: uuid,
                shopId: shopId,
                createdAt: DateTime.parse(createdAt),
                updatedAt: DateTime.parse(now),
              )
              .toMap()
            ..remove('id');
      await txn.insert(
        'bill_settings',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    notifyDatabaseChanged();
  }

  Future<InvoiceSeriesSettings> getDefaultInvoiceSeriesSettings() async {
    final db = await database;
    final shopId = await _activeShopId(db);
    var rows = await db.query(
      'invoice_series',
      where:
          'shop_id = ? AND deleted_at IS NULL AND is_active = 1 AND is_default = 1',
      whereArgs: [shopId],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) {
      await _seedDefaultInvoiceSeries(db);
      rows = await db.query(
        'invoice_series',
        where:
            'shop_id = ? AND deleted_at IS NULL AND is_active = 1 AND is_default = 1',
        whereArgs: [shopId],
        orderBy: 'id ASC',
        limit: 1,
      );
    }
    if (rows.isEmpty) return const InvoiceSeriesSettings();
    return InvoiceSeriesSettings.fromMap(rows.single);
  }

  Future<void> saveDefaultInvoiceSeriesSettings(
    InvoiceSeriesSettings settings,
  ) async {
    await _requireAdminMutation();
    final template = _normaliseName(settings.formatTemplate);
    if (template == null || !template.contains('{SEQ}')) {
      throw ArgumentError('Bill number pattern must include {SEQ}');
    }
    final db = await database;
    await db.transaction((txn) async {
      final shopId = await _activeShopId(txn);
      var rows = await txn.query(
        'invoice_series',
        columns: ['id'],
        where:
            'shop_id = ? AND deleted_at IS NULL AND is_active = 1 AND is_default = 1',
        whereArgs: [shopId],
        orderBy: 'id ASC',
        limit: 1,
      );
      if (rows.isEmpty) {
        await _seedDefaultInvoiceSeries(txn);
        rows = await txn.query(
          'invoice_series',
          columns: ['id'],
          where:
              'shop_id = ? AND deleted_at IS NULL AND is_active = 1 AND is_default = 1',
          whereArgs: [shopId],
          orderBy: 'id ASC',
          limit: 1,
        );
      }
      if (rows.isEmpty) {
        throw StateError('No active invoice series is configured');
      }
      await txn.update(
        'invoice_series',
        {
          'name': _normaliseName(settings.name) ?? 'Default',
          'format_template': template,
          'sequence_padding': settings.sequencePadding.clamp(1, 8),
          'reset_period': settings.resetPeriod,
          'updated_at': _nowIso(),
        },
        where: 'id = ?',
        whereArgs: [rows.single['id']],
      );
    });
    notifyDatabaseChanged();
  }
}

Future<void> _saveSetting(
  DatabaseExecutor executor,
  String key,
  String value,
) async {
  await executor.insert('app_settings', {
    'key': key,
    'shop_id': await _activeShopId(executor),
    'value': value,
    'updated_at': _nowIso(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
