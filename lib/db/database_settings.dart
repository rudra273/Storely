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

  Future<List<String>> getUnits() async {
    final db = await database;
    final values = <String>{...Product.presetUnits};
    final optionRows = await db.query('unit_options', orderBy: 'name ASC');
    final productRows = await db.rawQuery(
      "SELECT DISTINCT unit FROM products WHERE unit IS NOT NULL AND TRIM(unit) != ''",
    );

    for (final row in optionRows) {
      final value = _normaliseName(row['name']?.toString());
      if (value != null) values.add(value);
    }
    for (final row in productRows) {
      final value = _normaliseName(row['unit']?.toString());
      if (value != null) values.add(value);
    }

    final presets = Product.presetUnits
        .where((unit) => values.any((v) => v.toLowerCase() == unit))
        .toList();
    final custom = values.where((unit) => !_isPresetUnit(unit)).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [...presets, ...custom];
  }

  Future<void> addUnitOption(String name) async {
    final db = await database;
    await _insertUnitOption(db, name);
  }

  Future<void> deleteUnitOption(String name) async {
    final db = await database;
    final value = _normaliseName(name);
    if (value == null || _isPresetUnit(value)) return;
    await db.delete(
      'unit_options',
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [value],
    );
  }

  Future<GlobalPricingSettings> getGlobalPricingSettings() async {
    final db = await database;
    final rows = await db.query('app_settings');
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
  }
}

Future<void> _saveSetting(
  DatabaseExecutor executor,
  String key,
  String value,
) async {
  await executor.insert('app_settings', {
    'key': key,
    'value': value,
    'updated_at': DateTime.now().toIso8601String(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
