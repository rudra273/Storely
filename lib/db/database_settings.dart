part of 'database_helper.dart';

mixin DatabaseSettings {
  static const _shopNameKey = 'shop_name';
  static const _lowStockThresholdKey = 'low_stock_threshold';
  static const _defaultGstPercentKey = 'default_gst_percent';
  static const _defaultOverheadCostKey = 'default_overhead_cost';
  static const _defaultProfitMarginPercentKey = 'default_profit_margin_percent';
  static const _gstRegisteredKey = 'gst_registered';
  static const _gstSchemeKey = 'gst_scheme';
  static const _showPurchasePriceGloballyKey = 'show_purchase_price_globally';

  Future<Database> get database;
  Future<void> _seedDefaultInvoiceSeries(DatabaseExecutor executor);

  Future<SettingsEditBaseline> captureSettingsEditBaseline() async {
    final db = await database;
    return db.transaction((txn) async {
      await _seedDefaultInvoiceSeries(txn);
      final shopId = await _activeShopId(txn);
      return SettingsEditBaseline._(
        shopId,
        await _settingsSnapshot(txn, shopId),
      );
    });
  }

  Future<void> _assertSettingsBaseline(
    DatabaseExecutor txn,
    SettingsEditBaseline? baseline,
  ) async {
    if (baseline == null) {
      return; // Legacy programmatic callers stay compatible.
    }
    final shopId = await _activeShopId(txn);
    if (shopId != baseline.shopId ||
        await _settingsSnapshot(txn, shopId) != baseline._snapshot) {
      throw StateError(
        'Shop settings changed while you were editing. Your entries are kept; reopen settings before saving.',
      );
    }
  }

  Future<String> _settingsSnapshot(DatabaseExecutor txn, String shopId) async {
    final snapshot = <String, Object?>{};
    for (final table in [
      'shops',
      'app_settings',
      'bill_settings',
      'invoice_series',
    ]) {
      final rows = await txn.query(
        table,
        where:
            '${table == 'shops' ? 'uuid' : 'shop_id'} = ? AND deleted_at IS NULL',
        whereArgs: [shopId],
      );
      final values = rows.map((row) {
        final keys =
            row.keys
                .where(
                  (key) => !{
                    'id',
                    'sync_dirty',
                    'server_updated_at',
                    'device_id',
                    'created_at',
                    'updated_at',
                    'next_sequence',
                    'last_sequence_key',
                  }.contains(key),
                )
                .toList()
              ..sort();
        return jsonEncode({for (final key in keys) key: row[key]});
      }).toList()..sort();
      snapshot[table] = values;
    }
    return jsonEncode(snapshot);
  }

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

  /// The seeded "My Shop" row is a placeholder; saving that exact name is
  /// nevertheless a valid setup choice, proven by the existing explicit key.
  Future<bool> hasCompletedShopSetup() async {
    final name = (await getShopProfile())?.name.trim();
    if (name == null || name.isEmpty) return false;
    if (name != 'My Shop') return true;
    return await _getLegacyShopName(await database) != null;
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
          gstScheme: current.gstScheme,
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
    final scheme = GstScheme.clean(
      await _getSetting(db, _gstSchemeKey),
      fallbackRegistered: pricing.gstRegistered,
    );
    if (rows.isNotEmpty) {
      return ShopProfile.fromMap(rows.single, gstScheme: scheme);
    }

    final legacyName = await _getLegacyShopName(db);
    if (legacyName == null) return null;
    return ShopProfile(name: legacyName, gstScheme: scheme);
  }

  Future<void> saveShopProfile(
    ShopProfile profile, {
    SettingsEditBaseline? baseline,
  }) async {
    await _requireAdminMutation();
    final db = await database;
    final name = _normaliseName(profile.name);
    if (name == null) throw ArgumentError('Shop name is required');

    await db.transaction((txn) async {
      await _assertSettingsBaseline(txn, baseline);
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
      await _saveSetting(txn, _gstSchemeKey, profile.gstScheme);
      // Pricing reads this flag: only the regular scheme charges GST and
      // claims input credit; composition prices like an unregistered shop.
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

  Future<double> getLowStockThreshold() async {
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
    return LowStockThreshold.parse(rows.first['value']?.toString())?.value ?? 5;
  }

  Future<void> saveLowStockThreshold(
    num value, {
    SettingsEditBaseline? baseline,
  }) async {
    await _persistLowStockThreshold(value, baseline);
  }

  Future<SettingsEditBaseline> saveLowStockThresholdWithBaseline(
    num value, {
    required SettingsEditBaseline baseline,
  }) => _persistLowStockThreshold(value, baseline);

  Future<SettingsEditBaseline> _persistLowStockThreshold(
    num value,
    SettingsEditBaseline? baseline,
  ) async {
    await _requireAdminMutation();
    final threshold = LowStockThreshold.parse(value.toString());
    if (threshold == null) {
      throw const FormatException(
        'Minimum stock must be between 0 and 999999999 with at most 4 decimal places.',
      );
    }
    final db = await database;
    final saved = await db.transaction((txn) async {
      await _assertSettingsBaseline(txn, baseline);
      if (!_canMutateAsAdmin()) {
        throw StateError(
          'Only a shop owner/admin can change the minimum stock.',
        );
      }
      await _saveSetting(txn, _lowStockThresholdKey, threshold.text);
      final shopId = await _activeShopId(txn);
      return SettingsEditBaseline._(
        shopId,
        await _settingsSnapshot(txn, shopId),
      );
    });
    notifyDatabaseChanged();
    return saved;
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

  Future<GlobalPricingSettings> getGlobalPricingSettings() async =>
      _getGlobalPricingSettingsFromExecutor(await database);

  Future<void> saveGlobalPricingSettings(
    GlobalPricingSettings settings, {
    SettingsEditBaseline? baseline,
  }) async {
    await _persistGlobalPricingSettings(settings, baseline);
  }

  Future<SettingsEditBaseline> savePricingSettingsWithBaseline(
    GlobalPricingSettings settings, {
    required SettingsEditBaseline baseline,
  }) => _persistGlobalPricingSettings(settings, baseline);

  Future<SettingsEditBaseline> _persistGlobalPricingSettings(
    GlobalPricingSettings settings,
    SettingsEditBaseline? baseline,
  ) async {
    await _requireAdminMutation();
    final db = await database;
    final saved = await db.transaction((txn) async {
      await _assertSettingsBaseline(txn, baseline);
      final current = await _getGlobalPricingSettingsFromExecutor(txn);
      final rows = await txn.query(
        'app_settings',
        columns: ['key'],
        where: 'shop_id = ? AND deleted_at IS NULL',
        whereArgs: [await _activeShopId(txn)],
      );
      final keys = rows.map((row) => row['key']).toSet();
      Future<void> changed(String key, Object value, Object old) async {
        final input = settings.storedDefaults[key];
        final changedInput =
            input != null && input != current.storedDefaults[key];
        if (!keys.contains(key) || value != old || changedInput) {
          await _saveSetting(txn, key, input ?? value.toString());
        }
      }

      await changed(
        _defaultGstPercentKey,
        settings.defaultGstPercent,
        current.defaultGstPercent,
      );
      await changed(
        _defaultOverheadCostKey,
        settings.defaultOverheadCost,
        current.defaultOverheadCost,
      );
      await changed(
        _defaultProfitMarginPercentKey,
        settings.defaultProfitMarginPercent,
        current.defaultProfitMarginPercent,
      );
      await changed(
        _gstRegisteredKey,
        settings.gstRegistered ? '1' : '0',
        current.gstRegistered ? '1' : '0',
      );
      await changed(
        _showPurchasePriceGloballyKey,
        settings.showPurchasePriceGlobally ? '1' : '0',
        current.showPurchasePriceGlobally ? '1' : '0',
      );
      final shopId = await _activeShopId(txn);
      return SettingsEditBaseline._(
        shopId,
        await _settingsSnapshot(txn, shopId),
      );
    });
    notifyDatabaseChanged();
    return saved;
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

  Future<void> saveBillSettings(
    BillSettings settings, {
    SettingsEditBaseline? baseline,
  }) async {
    await _requireAdminMutation();
    final db = await database;
    await db.transaction((txn) async {
      await _assertSettingsBaseline(txn, baseline);
      await _saveBillSettings(txn, settings);
    });
    notifyDatabaseChanged();
  }

  Future<void> _saveBillSettings(
    DatabaseExecutor txn,
    BillSettings settings,
  ) async {
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
  }

  Future<void> saveInvoiceSettings(
    BillSettings settings,
    InvoiceSeriesSettings series, {
    required SettingsEditBaseline baseline,
  }) async {
    await _requireAdminMutation();
    final db = await database;
    await db.transaction((txn) async {
      await _assertSettingsBaseline(txn, baseline);
      await _saveBillSettings(txn, settings);
      await _saveInvoiceSeries(txn, series);
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
    final db = await database;
    await db.transaction((txn) => _saveInvoiceSeries(txn, settings));
    notifyDatabaseChanged();
  }

  Future<void> _saveInvoiceSeries(
    DatabaseExecutor txn,
    InvoiceSeriesSettings settings,
  ) async {
    final template = _normaliseName(settings.formatTemplate);
    final problem = InvoiceNumbering.validate(
      template: template ?? '',
      padding: settings.sequencePadding,
      resetPeriod: settings.resetPeriod,
    );
    if (problem != null) throw ArgumentError(problem);
    if (settings.nextSequence < 1) {
      throw ArgumentError('Next invoice number must be at least 1');
    }
    final shopId = await _activeShopId(txn);
    var rows = await txn.query(
      'invoice_series',
      columns: ['id', 'next_sequence'],
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
        columns: ['id', 'next_sequence'],
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
    final existingNext = (rows.single['next_sequence'] as num?)?.toInt() ?? 1;
    final updateValues = <String, Object?>{
      'name': _normaliseName(settings.name) ?? 'Default',
      'format_template': template,
      'sequence_padding': settings.sequencePadding.clamp(1, 8),
      'reset_period': settings.resetPeriod,
      'updated_at': _nowIso(),
    };
    if (settings.nextSequence > existingNext) {
      updateValues['next_sequence'] = settings.nextSequence;
      updateValues['last_sequence_key'] = InvoiceNumbering.resetKey(
        DateTime.now(),
        settings.resetPeriod,
      );
    }
    await txn.update(
      'invoice_series',
      updateValues,
      where: 'id = ?',
      whereArgs: [rows.single['id']],
    );
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

Future<String?> _getSetting(DatabaseExecutor executor, String key) async {
  final rows = await executor.query(
    'app_settings',
    columns: ['value'],
    where: 'shop_id = ? AND key = ? AND deleted_at IS NULL',
    whereArgs: [await _activeShopId(executor), key],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.single['value']?.toString();
}

/// Frozen persisted configuration values, never serialized into cloud settings.
class SettingsEditBaseline {
  final String shopId;
  final String _snapshot;
  const SettingsEditBaseline._(this.shopId, this._snapshot);
  Map<String, dynamic> toLocalMap() => {
    'shop_id': shopId,
    'snapshot': _snapshot,
  };
  factory SettingsEditBaseline.fromLocalMap(Map<String, dynamic> map) {
    if (map['shop_id'] is! String || map['snapshot'] is! String) {
      throw const FormatException('Unreadable checkout settings baseline.');
    }
    return SettingsEditBaseline._(
      map['shop_id'] as String,
      map['snapshot'] as String,
    );
  }
}
