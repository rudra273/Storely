part of 'database_helper.dart';

mixin DatabaseProducts {
  Future<Database> get database;
  Future<GlobalPricingSettings> getGlobalPricingSettings();

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
      await _insertPurchaseEntry(
        txn,
        productId: id,
        product: productToInsert,
        quantityAdded: productToInsert.quantity,
        purchaseDate: productToInsert.createdAt,
        source: productToInsert.source,
      );
      return id;
    });
  }

  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final maps = await db.query('products', orderBy: 'created_at ASC');
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  Future<Map<int, ProductPurchaseSummary>> getProductPurchaseSummaries() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT p.product_id,
             p.purchase_date,
             p.purchase_price,
             totals.total_purchased
      FROM product_purchase_entries p
      JOIN (
        SELECT product_id, MAX(purchase_date || 'T' || created_at) AS latest_key,
               COALESCE(SUM(quantity_added), 0) AS total_purchased
        FROM product_purchase_entries
        GROUP BY product_id
      ) totals
        ON totals.product_id = p.product_id
       AND totals.latest_key = p.purchase_date || 'T' || p.created_at
    ''');
    return {
      for (final row in rows)
        row['product_id'] as int: ProductPurchaseSummary(
          productId: row['product_id'] as int,
          lastPurchaseDate: DateTime.tryParse(row['purchase_date'] as String),
          lastPurchasePrice: (row['purchase_price'] as num?)?.toDouble(),
          totalPurchased: row['total_purchased'] as int? ?? 0,
        ),
    };
  }

  Future<Set<int>> getProductIdsPurchasedOn(DateTime date) async {
    final db = await database;
    final rows = await db.query(
      'product_purchase_entries',
      distinct: true,
      columns: ['product_id'],
      where: 'purchase_date = ?',
      whereArgs: [_dateOnly(date)],
    );
    return rows.map((row) => row['product_id'] as int).toSet();
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

  Future<int> restockProduct(
    Product product, {
    required int quantityAdded,
    required DateTime purchaseDate,
    String source = ProductSource.mobile,
  }) async {
    if (product.id == null) throw ArgumentError('Product id is required');
    final db = await database;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [product.id],
        limit: 1,
      );
      if (existing.isEmpty) return 0;
      final current = Product.fromMap(existing.single);
      final updatedProduct = product.copyWith(
        quantity: current.quantity + quantityAdded,
        source: source,
      );
      final count = await txn.update(
        'products',
        updatedProduct.toMap(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
      await _saveProductOptions(txn, updatedProduct);
      await _insertPurchaseEntry(
        txn,
        productId: product.id!,
        product: updatedProduct,
        quantityAdded: quantityAdded,
        purchaseDate: purchaseDate,
        source: source,
      );
      return count;
    });
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.delete(
        'product_purchase_entries',
        where: 'product_id = ?',
        whereArgs: [id],
      );
      return txn.delete('products', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<String>> getCategories() async {
    final db = await database;
    return _getOptions(db, 'category_options', 'category');
  }

  Future<CategoryPricingSettings?> getCategoryPricing(String name) async {
    final db = await database;
    return _getCategoryPricing(db, name);
  }

  Future<void> saveCategoryPricing(CategoryPricingSettings settings) async {
    final db = await database;
    final name = _normaliseName(settings.name);
    if (name == null) throw ArgumentError('Category name is required');
    await db.transaction((txn) async {
      await _insertOption(txn, 'category_options', name);
      await txn.update(
        'category_options',
        settings.toPricingMap(),
        where: 'LOWER(name) = LOWER(?)',
        whereArgs: [name],
      );
    });
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

  Future<PriceBreakdown> resolveProductPrice(Product product) async {
    final db = await database;
    final global = await getGlobalPricingSettings();
    final category = product.category == null
        ? null
        : await _getCategoryPricing(db, product.category!);
    return _resolveProductPrice(product, global, category);
  }

  Future<int> refreshAllProductSellingPrices() async {
    final db = await database;
    final global = await getGlobalPricingSettings();
    final productMaps = await db.query('products');
    final categoryRows = await db.query('category_options');
    final categories = {
      for (final row in categoryRows)
        (row['name'] as String).toLowerCase(): CategoryPricingSettings.fromMap(
          row,
        ),
    };

    var updated = 0;
    await db.transaction((txn) async {
      for (final map in productMaps) {
        final product = Product.fromMap(map);
        final category = product.category == null
            ? null
            : categories[product.category!.toLowerCase()];
        final breakdown = _resolveProductPrice(product, global, category);
        if ((product.mrp - breakdown.sellingPrice).abs() < 0.005) continue;
        await txn.update(
          'products',
          {'mrp': breakdown.sellingPrice},
          where: 'id = ?',
          whereArgs: [product.id],
        );
        updated++;
      }
    });
    return updated;
  }

  Future<Product?> getProductById(int id) async {
    final db = await database;
    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<Product?> findProductForBilling({
    int? id,
    String? itemCode,
    required String name,
  }) async {
    final db = await database;
    if (id != null) {
      final rows = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) return Product.fromMap(rows.first);
    }
    final code = _normaliseName(itemCode);
    if (code != null) {
      final rows = await db.query(
        'products',
        where: 'item_code = ?',
        whereArgs: [code],
        limit: 1,
      );
      if (rows.isNotEmpty) return Product.fromMap(rows.first);
    }
    final rows = await db.query(
      'products',
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [name],
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<BillItem> buildBillItemForProduct(Product product) async {
    final breakdown = await resolveProductPrice(product);
    return BillItem(
      productId: product.id,
      productName: product.name,
      mrp: breakdown.sellingPrice,
      unit: product.unit,
      purchasePriceSnapshot: breakdown.purchasePrice,
      sellingPriceSnapshot: breakdown.sellingPrice,
      costSnapshot: breakdown.totalCost,
      profitSnapshot: breakdown.profitAmount,
      commissionSnapshot: 0,
      gstSnapshot: breakdown.gstAmount,
      wasDirectPrice: breakdown.wasDirectPrice,
    );
  }

  Future<int> replaceAllProducts(
    List<Product> products, {
    DateTime? purchaseDate,
  }) async {
    final db = await database;
    final date = purchaseDate ?? DateTime.now();
    final cleanProducts = _uniqueProductsByIdentity(
      products,
    ).map(_asImportedProduct).toList();
    final batchKey = _importBatchKey(cleanProducts, date);

    return db.transaction((txn) async {
      int count = 0;
      for (final p in cleanProducts) {
        final existing = await _findExistingProductRows(txn, p);
        final int id;
        if (existing.isNotEmpty) {
          id = existing.first['id'] as int;
          final current = Product.fromMap(existing.first);
          await txn.update(
            'products',
            p.copyWith(id: id, createdAt: current.createdAt).toMap(),
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          id = await txn.insert(
            'products',
            p.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await _saveProductOptions(txn, p);
        await _insertPurchaseEntry(
          txn,
          productId: id,
          product: p,
          quantityAdded: p.quantity,
          purchaseDate: date,
          importBatchKey: batchKey,
          source: ProductSource.imported,
        );
        count++;
      }
      return count;
    });
  }

  Future<ProductImportResult> mergeProducts(
    List<Product> products, {
    DateTime? purchaseDate,
  }) async {
    final db = await database;
    final date = purchaseDate ?? DateTime.now();
    final cleanProducts = _uniqueProductsByIdentity(
      products,
    ).map(_asImportedProduct).toList();
    final batchKey = _importBatchKey(cleanProducts, date);
    final rowSetKey = _importRowSetKey(cleanProducts);

    return db.transaction((txn) async {
      int added = 0, updated = 0;
      final possibleDuplicate = await _hasImportBatch(txn, batchKey);
      final duplicateOnDifferentDate = !possibleDuplicate
          ? await _hasImportRowSet(txn, rowSetKey)
          : false;
      for (final p in cleanProducts) {
        final existing = await _findExistingProductRows(txn, p);

        if (existing.isNotEmpty) {
          final existingId = existing.first['id'] as int;
          final current = Product.fromMap(existing.first);
          final merged = p.copyWith(
            id: existingId,
            quantity: current.quantity + p.quantity,
            createdAt: current.createdAt,
          );
          await txn.update(
            'products',
            merged.toMap(),
            where: 'id = ?',
            whereArgs: [existingId],
          );
          await _saveProductOptions(txn, merged);
          await _insertPurchaseEntry(
            txn,
            productId: existingId,
            product: merged,
            quantityAdded: p.quantity,
            purchaseDate: date,
            importBatchKey: batchKey,
            source: ProductSource.imported,
          );
          updated++;
        } else {
          final id = await txn.insert(
            'products',
            p.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await _saveProductOptions(txn, p);
          await _insertPurchaseEntry(
            txn,
            productId: id,
            product: p,
            quantityAdded: p.quantity,
            purchaseDate: date,
            importBatchKey: batchKey,
            source: ProductSource.imported,
          );
          added++;
        }
      }
      return ProductImportResult(
        added: added,
        updated: updated,
        possibleDuplicate: possibleDuplicate,
        duplicateOnDifferentDate: duplicateOnDifferentDate,
      );
    });
  }

  Future<ProductImportResult> previewImportDuplicate(
    List<Product> products, {
    DateTime? purchaseDate,
  }) async {
    final db = await database;
    final cleanProducts = _uniqueProductsByIdentity(products);
    final sameDateDuplicate = purchaseDate != null
        ? await _hasImportBatch(
            db,
            _importBatchKey(cleanProducts, purchaseDate),
          )
        : false;
    final differentDateDuplicate = !sameDateDuplicate
        ? await _hasImportRowSet(db, _importRowSetKey(cleanProducts))
        : false;
    return ProductImportResult(
      added: 0,
      updated: 0,
      possibleDuplicate: sameDateDuplicate,
      duplicateOnDifferentDate: differentDateDuplicate,
    );
  }

  Future<bool> wouldImportDuplicate(
    List<Product> products, {
    required DateTime purchaseDate,
  }) async {
    final result = await previewImportDuplicate(
      products,
      purchaseDate: purchaseDate,
    );
    return result.possibleDuplicate || result.duplicateOnDifferentDate;
  }

  List<Product> _uniqueProductsByIdentity(List<Product> products) {
    final byIdentity = <String, Product>{};
    for (final product in products) {
      byIdentity[_productIdentity(product)] = product;
    }
    return byIdentity.values.toList();
  }

  Product _asImportedProduct(Product product) =>
      product.copyWith(source: ProductSource.imported);

  Future<List<Map<String, dynamic>>> _findExistingProductRows(
    DatabaseExecutor executor,
    Product product,
  ) async {
    final code = _normaliseName(product.itemCode);
    if (code != null) {
      final rows = await executor.query(
        'products',
        where: 'item_code = ?',
        whereArgs: [code],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows;
    }

    return executor.query(
      'products',
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [product.name],
      limit: 1,
    );
  }

  Future<void> _insertPurchaseEntry(
    DatabaseExecutor executor, {
    required int productId,
    required Product product,
    required int quantityAdded,
    required DateTime purchaseDate,
    String? importBatchKey,
    required String source,
  }) async {
    if (quantityAdded <= 0) return;
    await executor.insert('product_purchase_entries', {
      'product_id': productId,
      'purchase_date': _dateOnly(purchaseDate),
      'quantity_added': quantityAdded,
      'purchase_price': product.purchasePrice,
      'supplier': product.supplier,
      'import_batch_key': importBatchKey,
      'source': source,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> _hasImportBatch(
    DatabaseExecutor executor,
    String batchKey,
  ) async {
    final rows = await executor.query(
      'product_purchase_entries',
      columns: ['id'],
      where: 'import_batch_key = ?',
      whereArgs: [batchKey],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<bool> _hasImportRowSet(
    DatabaseExecutor executor,
    String rowSetKey,
  ) async {
    final rows = await executor.query(
      'product_purchase_entries',
      columns: ['id'],
      where: 'import_batch_key LIKE ?',
      whereArgs: ['%::$rowSetKey'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  String _importBatchKey(List<Product> products, DateTime purchaseDate) {
    return '${_dateOnly(purchaseDate)}::${_importRowSetKey(products)}';
  }

  String _importRowSetKey(List<Product> products) {
    final rowKeys = products.map((product) {
      return [
        _productIdentity(product),
        product.quantity,
        product.purchasePrice.toStringAsFixed(2),
        (product.supplier ?? '').trim().toLowerCase(),
      ].join('|');
    }).toList()..sort();
    return rowKeys.join(';;');
  }

  String _productIdentity(Product product) {
    final code = _normaliseName(product.itemCode);
    if (code != null) return 'code:${code.toLowerCase()}';
    return 'name:${product.name.trim().toLowerCase()}';
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
}

Future<CategoryPricingSettings?> _getCategoryPricing(
  DatabaseExecutor executor,
  String name,
) async {
  final value = _normaliseName(name);
  if (value == null) return null;
  final rows = await executor.query(
    'category_options',
    where: 'LOWER(name) = LOWER(?)',
    whereArgs: [value],
    limit: 1,
  );
  return rows.isEmpty ? null : CategoryPricingSettings.fromMap(rows.first);
}

PriceBreakdown _resolveProductPrice(
  Product product,
  GlobalPricingSettings global,
  CategoryPricingSettings? category,
) {
  return PricingCalculator.resolveProductPrice(product, global, category);
}

Future<List<String>> _getOptions(
  DatabaseExecutor executor,
  String table,
  String productColumn,
) async {
  final optionRows = await executor.query(table, orderBy: 'name ASC');
  final productRows = await executor.rawQuery(
    "SELECT DISTINCT $productColumn FROM products WHERE $productColumn IS NOT NULL AND TRIM($productColumn) != ''",
  );
  final values = <String>{};
  for (final row in optionRows) {
    final name = _normaliseName(row['name']?.toString());
    if (name != null) values.add(name);
  }
  for (final row in productRows) {
    final name = _normaliseName(row[productColumn]?.toString());
    if (name != null) values.add(name);
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
  await _insertUnitOption(executor, product.unit);
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

Future<void> _insertUnitOption(DatabaseExecutor executor, Object? name) async {
  final value = _normaliseName(name?.toString());
  if (value == null || _isPresetUnit(value)) return;
  await executor.insert('unit_options', {
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
