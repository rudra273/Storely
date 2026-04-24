part of 'database_helper.dart';

mixin DatabaseSettings {
  static const _shopNameKey = 'shop_name';
  static const _lowStockThresholdKey = 'low_stock_threshold';

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
      'SELECT DISTINCT unit FROM products WHERE unit IS NOT NULL AND TRIM(unit) != ""',
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
}
