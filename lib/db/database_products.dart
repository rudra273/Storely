part of 'database_helper.dart';

mixin DatabaseProducts {
  Future<Database> get database;
  Future<GlobalPricingSettings> getGlobalPricingSettings();

  Future<int> insertProduct(Product product) async {
    final db = await database;
    return db.transaction((txn) async {
      final productToInsert = await _prepareProductForWrite(txn, product);
      final id = await txn.insert(
        'products',
        productToInsert.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      if (productToInsert.quantity > 0) {
        await _insertStockMovement(
          txn,
          productId: id,
          productUuid: productToInsert.uuid,
          movementType: StockMovementType.purchase,
          quantityDelta: productToInsert.quantity,
          unitCost: productToInsert.purchasePrice,
          sourceType: productToInsert.source == ProductSource.imported
              ? 'import'
              : 'manual',
          createdAt: productToInsert.createdAt,
        );
      }
      return id;
    });
  }

  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final maps = await _queryProducts(db, orderBy: 'p.created_at ASC');
    return maps.map((map) => Product.fromMap(map)).toList();
  }

  Future<Map<int, ProductPurchaseSummary>> getProductPurchaseSummaries() async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT s.product_id,
             substr(s.created_at, 1, 10) AS purchase_date,
             s.unit_cost AS purchase_price,
             totals.total_purchased
      FROM stock_movements s
      JOIN (
        SELECT product_id, MAX(created_at) AS latest_created_at,
               COALESCE(SUM(quantity_delta), 0) AS total_purchased
        FROM stock_movements
        WHERE deleted_at IS NULL AND movement_type = ?
        GROUP BY product_id
      ) totals
        ON totals.product_id = s.product_id
       AND totals.latest_created_at = s.created_at
      WHERE s.deleted_at IS NULL AND s.movement_type = ?
    ''',
      [StockMovementType.purchase, StockMovementType.purchase],
    );
    return {
      for (final row in rows)
        row['product_id'] as int: ProductPurchaseSummary(
          productId: row['product_id'] as int,
          lastPurchaseDate: DateTime.tryParse(row['purchase_date'] as String),
          lastPurchasePrice: (row['purchase_price'] as num?)?.toDouble(),
          totalPurchased: (row['total_purchased'] as num?)?.toDouble() ?? 0,
        ),
    };
  }

  Future<List<StockMovement>> getStockMovementsForProduct(int productId) async {
    final db = await database;
    final rows = await db.query(
      'stock_movements',
      where: 'deleted_at IS NULL AND product_id = ?',
      whereArgs: [productId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map((row) => StockMovement.fromMap(row)).toList();
  }

  Future<Set<int>> getProductIdsPurchasedOn(DateTime date) async {
    final db = await database;
    final rows = await db.query(
      'stock_movements',
      distinct: true,
      columns: ['product_id'],
      where:
          "deleted_at IS NULL AND movement_type = ? AND substr(created_at, 1, 10) = ?",
      whereArgs: [StockMovementType.purchase, _dateOnly(date)],
    );
    return rows.map((row) => row['product_id'] as int).toSet();
  }

  Future<bool> isNameUnique(String name, {int? excludeId}) async {
    final db = await database;
    final result = await db.query(
      'products',
      where: excludeId != null
          ? 'deleted_at IS NULL AND LOWER(name) = LOWER(?) AND id != ?'
          : 'deleted_at IS NULL AND LOWER(name) = LOWER(?)',
      whereArgs: excludeId != null ? [name, excludeId] : [name],
    );
    return result.isEmpty;
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    return db.transaction((txn) async {
      final productToUpdate = await _prepareProductForWrite(
        txn,
        product.copyWith(updatedAt: DateTime.now()),
      );
      return txn.update(
        'products',
        productToUpdate.toMap(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
    });
  }

  Future<int> restockProduct(
    Product product, {
    required num quantityAdded,
    required DateTime purchaseDate,
    String source = ProductSource.mobile,
  }) async {
    if (product.id == null) throw ArgumentError('Product id is required');
    final db = await database;
    return db.transaction((txn) async {
      final existing = await _queryProducts(
        txn,
        where: 'p.id = ?',
        whereArgs: [product.id],
        limit: 1,
      );
      if (existing.isEmpty) return 0;
      final current = Product.fromMap(existing.single);
      final updatedProduct = await _prepareProductForWrite(
        txn,
        product.copyWith(
          quantity: current.quantity + quantityAdded,
          source: source,
          updatedAt: DateTime.now(),
        ),
      );
      final count = await txn.update(
        'products',
        updatedProduct.toMap(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
      await _insertStockMovement(
        txn,
        productId: product.id!,
        productUuid: updatedProduct.uuid,
        movementType: StockMovementType.purchase,
        quantityDelta: quantityAdded.toDouble(),
        unitCost: updatedProduct.purchasePrice,
        sourceType: source == ProductSource.imported ? 'import' : 'manual',
        createdAt: purchaseDate,
      );
      return count;
    });
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    final now = _nowIso();
    return db.update(
      'products',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<String>> getCategories() async {
    final db = await database;
    return _getNames(db, 'categories');
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
      final id = await _ensureCategory(txn, name);
      await txn.update(
        'categories',
        {...settings.toPricingMap(), 'updated_at': _nowIso()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<String>> getSuppliers() async {
    final db = await database;
    return _getNames(db, 'suppliers');
  }

  Future<List<SupplierProfile>> getSupplierProfiles() async {
    final db = await database;
    final rows = await db.query(
      'suppliers',
      where: 'deleted_at IS NULL',
      orderBy: 'name ASC',
    );
    return rows.map((row) => SupplierProfile.fromMap(row)).toList();
  }

  Future<SupplierProfile?> getSupplierProfile(String name) async {
    final db = await database;
    final value = _normaliseName(name);
    if (value == null) return null;
    final rows = await db.query(
      'suppliers',
      where: 'deleted_at IS NULL AND LOWER(name) = LOWER(?)',
      whereArgs: [value],
      limit: 1,
    );
    return rows.isEmpty ? null : SupplierProfile.fromMap(rows.single);
  }

  Future<void> addCategoryOption(String name) async {
    final db = await database;
    await _ensureCategory(db, name);
  }

  Future<void> updateCategoryOption(String oldName, String newName) async {
    final db = await database;
    await _updateNameOption(db, 'categories', oldName, newName);
  }

  Future<void> deleteCategoryOption(String name) async {
    final db = await database;
    await _softDeleteNameOption(db, 'categories', name);
  }

  Future<void> addSupplierOption(String name) async {
    final db = await database;
    await _ensureSupplier(db, name);
  }

  Future<void> saveSupplierProfile(
    SupplierProfile supplier, {
    String? oldName,
  }) async {
    final db = await database;
    final name = _normaliseName(supplier.name);
    if (name == null) throw ArgumentError('Supplier name is required');

    await db.transaction((txn) async {
      final now = _nowIso();
      final oldValue = _normaliseName(oldName);
      final existing = supplier.id != null
          ? await txn.query(
              'suppliers',
              columns: ['id', 'uuid', 'created_at'],
              where: 'id = ?',
              whereArgs: [supplier.id],
              limit: 1,
            )
          : oldValue == null
          ? await txn.query(
              'suppliers',
              columns: ['id', 'uuid', 'created_at'],
              where: 'deleted_at IS NULL AND LOWER(name) = LOWER(?)',
              whereArgs: [name],
              limit: 1,
            )
          : await txn.query(
              'suppliers',
              columns: ['id', 'uuid', 'created_at'],
              where: 'deleted_at IS NULL AND LOWER(name) = LOWER(?)',
              whereArgs: [oldValue],
              limit: 1,
            );

      final map =
          supplier
              .copyWith(
                name: name,
                uuid: supplier.uuid.isEmpty ? _newUuid() : supplier.uuid,
                shopId: supplier.shopId.isEmpty
                    ? _defaultShopId
                    : supplier.shopId,
                updatedAt: DateTime.parse(now),
              )
              .toMap()
            ..remove('id');

      if (existing.isEmpty) {
        map['uuid'] = supplier.uuid.isEmpty ? _newUuid() : supplier.uuid;
        map['shop_id'] = supplier.shopId.isEmpty
            ? _defaultShopId
            : supplier.shopId;
        map['created_at'] = supplier.createdAt.toIso8601String();
        map['updated_at'] = now;
        await txn.insert('suppliers', map);
      } else {
        final row = existing.single;
        map['uuid'] = row['uuid'];
        map['created_at'] = row['created_at'];
        map['updated_at'] = now;
        await txn.update(
          'suppliers',
          map,
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
    });
  }

  Future<void> updateSupplierOption(String oldName, String newName) async {
    final db = await database;
    await _updateNameOption(db, 'suppliers', oldName, newName);
  }

  Future<void> deleteSupplierOption(String name) async {
    final db = await database;
    await _softDeleteNameOption(db, 'suppliers', name);
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
    final productMaps = await _queryProducts(db);
    final categoryRows = await db.query(
      'categories',
      where: 'deleted_at IS NULL',
    );
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
        if ((product.sellingPrice - breakdown.sellingPrice).abs() < 0.005) {
          continue;
        }
        await txn.update(
          'products',
          {'selling_price': breakdown.sellingPrice, 'updated_at': _nowIso()},
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
    final rows = await _queryProducts(
      db,
      where: 'p.id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<Product?> findProductForBilling({
    int? id,
    String? itemCode,
    String? barcode,
    required String name,
  }) async {
    final db = await database;
    if (id != null) {
      final rows = await _queryProducts(
        db,
        where: 'p.id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) return Product.fromMap(rows.first);
    }
    final code = _normaliseName(itemCode);
    if (code != null) {
      final rows = await _queryProducts(
        db,
        where: 'p.product_code = ?',
        whereArgs: [code],
        limit: 1,
      );
      if (rows.isNotEmpty) return Product.fromMap(rows.first);
    }
    final barcodeValue = _normaliseName(barcode);
    if (barcodeValue != null) {
      final rows = await _queryProducts(
        db,
        where: 'p.barcode = ?',
        whereArgs: [barcodeValue],
        limit: 1,
      );
      if (rows.isNotEmpty) return Product.fromMap(rows.first);
    }
    final rows = await _queryProducts(
      db,
      where: 'LOWER(p.name) = LOWER(?)',
      whereArgs: [name],
      limit: 1,
    );
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  Future<BillItem> buildBillItemForProduct(Product product) async {
    final breakdown = await resolveProductPrice(product);
    return BillItem(
      uuid: _newUuid(),
      shopId: product.shopId,
      productId: product.id,
      productUuid: product.uuid,
      productName: product.name,
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
        final Product writeProduct;
        if (existing.isNotEmpty) {
          id = existing.first['id'] as int;
          final current = Product.fromMap(existing.first);
          writeProduct = await _prepareProductForWrite(
            txn,
            p.copyWith(
              id: id,
              uuid: current.uuid,
              createdAt: current.createdAt,
            ),
          );
          await txn.update(
            'products',
            writeProduct.toMap(),
            where: 'id = ?',
            whereArgs: [id],
          );
        } else {
          writeProduct = await _prepareProductForWrite(txn, p);
          id = await txn.insert(
            'products',
            writeProduct.toMap()..remove('id'),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await _insertStockMovement(
          txn,
          productId: id,
          productUuid: writeProduct.uuid,
          movementType: StockMovementType.purchase,
          quantityDelta: p.quantity,
          unitCost: writeProduct.purchasePrice,
          sourceType: 'import',
          importBatchKey: batchKey,
          createdAt: date,
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
          final merged = await _prepareProductForWrite(
            txn,
            p.copyWith(
              id: existingId,
              uuid: current.uuid,
              quantity: current.quantity + p.quantity,
              createdAt: current.createdAt,
            ),
          );
          await txn.update(
            'products',
            merged.toMap(),
            where: 'id = ?',
            whereArgs: [existingId],
          );
          await _insertStockMovement(
            txn,
            productId: existingId,
            productUuid: merged.uuid,
            movementType: StockMovementType.purchase,
            quantityDelta: p.quantity,
            unitCost: merged.purchasePrice,
            sourceType: 'import',
            importBatchKey: batchKey,
            createdAt: date,
          );
          updated++;
        } else {
          final writeProduct = await _prepareProductForWrite(txn, p);
          final id = await txn.insert(
            'products',
            writeProduct.toMap()..remove('id'),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await _insertStockMovement(
            txn,
            productId: id,
            productUuid: writeProduct.uuid,
            movementType: StockMovementType.purchase,
            quantityDelta: p.quantity,
            unitCost: writeProduct.purchasePrice,
            sourceType: 'import',
            importBatchKey: batchKey,
            createdAt: date,
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
    final code = _normaliseName(product.productCode);
    if (code != null) {
      final rows = await _queryProducts(
        executor,
        where: 'p.product_code = ?',
        whereArgs: [code],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows;
    }

    final barcode = _normaliseName(product.barcode);
    if (barcode != null) {
      final rows = await _queryProducts(
        executor,
        where: 'p.barcode = ?',
        whereArgs: [barcode],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows;
    }

    return _queryProducts(
      executor,
      where: 'LOWER(p.name) = LOWER(?)',
      whereArgs: [product.name],
      limit: 1,
    );
  }

  Future<Product> _prepareProductForWrite(
    DatabaseExecutor executor,
    Product product,
  ) async {
    final now = DateTime.now();
    final categoryId = product.category == null
        ? product.categoryId
        : await _ensureCategory(executor, product.category!);
    final supplierId = product.supplier == null
        ? product.supplierId
        : await _ensureSupplier(executor, product.supplier!);
    final unitId = product.unit == null
        ? product.unitId
        : await _ensureUnit(executor, product.unit!);
    return product.copyWith(
      uuid: product.uuid.isEmpty ? _newUuid() : product.uuid,
      shopId: product.shopId.isEmpty ? _defaultShopId : product.shopId,
      categoryId: categoryId,
      supplierId: supplierId,
      unitId: unitId,
      createdAt: product.createdAt,
      updatedAt: now,
    );
  }

  Future<void> _insertStockMovement(
    DatabaseExecutor executor, {
    required int productId,
    required String productUuid,
    required String movementType,
    required double quantityDelta,
    double? unitCost,
    String? sourceType,
    int? sourceId,
    String? sourceUuid,
    String? importBatchKey,
    String? notes,
    DateTime? createdAt,
  }) async {
    if (quantityDelta == 0) return;
    final now = DateTime.now();
    await executor.insert('stock_movements', {
      'uuid': _newUuid(),
      'shop_id': _defaultShopId,
      'product_id': productId,
      'product_uuid': productUuid,
      'movement_type': movementType,
      'quantity_delta': quantityDelta,
      'unit_cost': unitCost,
      'source_type': sourceType,
      'source_id': sourceId,
      'source_uuid': sourceUuid,
      'import_batch_key': importBatchKey,
      'notes': notes,
      'created_at': (createdAt ?? now).toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  Future<bool> _hasImportBatch(
    DatabaseExecutor executor,
    String batchKey,
  ) async {
    final rows = await executor.query(
      'stock_movements',
      columns: ['id'],
      where: 'deleted_at IS NULL AND import_batch_key = ?',
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
      'stock_movements',
      columns: ['id'],
      where: 'deleted_at IS NULL AND import_batch_key LIKE ?',
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
        product.quantity.toStringAsFixed(3),
        product.purchasePrice.toStringAsFixed(2),
        (product.supplier ?? '').trim().toLowerCase(),
      ].join('|');
    }).toList()..sort();
    return rowKeys.join(';;');
  }

  String _productIdentity(Product product) {
    final code = _normaliseName(product.productCode);
    if (code != null) return 'code:${code.toLowerCase()}';
    final barcode = _normaliseName(product.barcode);
    if (barcode != null) return 'barcode:${barcode.toLowerCase()}';
    return 'name:${product.name.trim().toLowerCase()}';
  }
}

Future<List<Map<String, dynamic>>> _queryProducts(
  DatabaseExecutor executor, {
  String? where,
  List<Object?>? whereArgs,
  String? orderBy,
  int? limit,
}) {
  final conditions = ['p.deleted_at IS NULL'];
  if (where != null && where.trim().isNotEmpty) {
    conditions.add('($where)');
  }
  return executor.rawQuery('''
    SELECT p.*,
           c.name AS category_name,
           s.name AS supplier_name,
           u.name AS unit_name
    FROM products p
    LEFT JOIN categories c ON c.id = p.category_id
    LEFT JOIN suppliers s ON s.id = p.supplier_id
    LEFT JOIN units u ON u.id = p.unit_id
    WHERE ${conditions.join(' AND ')}
    ${orderBy == null ? '' : 'ORDER BY $orderBy'}
    ${limit == null ? '' : 'LIMIT $limit'}
  ''', whereArgs);
}

Future<CategoryPricingSettings?> _getCategoryPricing(
  DatabaseExecutor executor,
  String name,
) async {
  final value = _normaliseName(name);
  if (value == null) return null;
  final rows = await executor.query(
    'categories',
    where: 'deleted_at IS NULL AND LOWER(name) = LOWER(?)',
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

Future<List<String>> _getNames(DatabaseExecutor executor, String table) async {
  final rows = await executor.query(
    table,
    columns: ['name'],
    where: 'deleted_at IS NULL',
    orderBy: 'name ASC',
  );
  return rows
      .map((row) => _normaliseName(row['name']?.toString()))
      .whereType<String>()
      .toList();
}

Future<int> _ensureCategory(DatabaseExecutor executor, String name) {
  return _ensureNameRecord(executor, 'categories', name);
}

Future<int> _ensureSupplier(DatabaseExecutor executor, String name) {
  return _ensureNameRecord(executor, 'suppliers', name);
}

Future<int> _ensureUnit(DatabaseExecutor executor, String name) {
  return _ensureNameRecord(executor, 'units', name);
}

Future<int> _ensureNameRecord(
  DatabaseExecutor executor,
  String table,
  String name,
) async {
  final value = _normaliseName(name);
  if (value == null) throw ArgumentError('Name is required');
  final rows = await executor.query(
    table,
    columns: ['id'],
    where: 'deleted_at IS NULL AND LOWER(name) = LOWER(?)',
    whereArgs: [value],
    limit: 1,
  );
  if (rows.isNotEmpty) return rows.single['id'] as int;
  final now = _nowIso();
  return executor.insert(table, {
    'uuid': _newUuid(),
    'shop_id': _defaultShopId,
    'name': value,
    'created_at': now,
    'updated_at': now,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}

Future<void> _updateNameOption(
  Database db,
  String table,
  String oldName,
  String newName,
) async {
  final oldValue = _normaliseName(oldName);
  final newValue = _normaliseName(newName);
  if (oldValue == null || newValue == null) {
    throw ArgumentError('Name is required');
  }
  await db.transaction((txn) async {
    final existing = await txn.query(
      table,
      columns: ['id'],
      where: 'deleted_at IS NULL AND LOWER(name) = LOWER(?)',
      whereArgs: [oldValue],
      limit: 1,
    );
    if (existing.isEmpty) {
      await _ensureNameRecord(txn, table, newValue);
      return;
    }
    await txn.update(
      table,
      {'name': newValue, 'updated_at': _nowIso()},
      where: 'id = ?',
      whereArgs: [existing.single['id']],
    );
  });
}

Future<void> _softDeleteNameOption(
  Database db,
  String table,
  String name,
) async {
  final value = _normaliseName(name);
  if (value == null) return;
  final now = _nowIso();
  await db.update(
    table,
    {'deleted_at': now, 'updated_at': now},
    where: 'deleted_at IS NULL AND LOWER(name) = LOWER(?)',
    whereArgs: [value],
  );
}
