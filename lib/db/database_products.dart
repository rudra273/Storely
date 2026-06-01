part of 'database_helper.dart';

mixin DatabaseProducts {
  Future<Database> get database;
  Future<GlobalPricingSettings> getGlobalPricingSettings();

  Future<int> insertProduct(Product product, {DateTime? purchaseDate}) async {
    await _requireAdminMutation();
    final db = await database;
    return db.transaction((txn) async {
      final id = await _insertProductInTransaction(
        txn,
        product,
        purchaseDate: purchaseDate,
      );
      notifyDatabaseChanged();
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
    await _requireAdminMutation();
    final db = await database;
    return db.transaction((txn) async {
      final existing = product.id == null
          ? const <Map<String, dynamic>>[]
          : await _queryProducts(
              txn,
              where: 'p.id = ?',
              whereArgs: [product.id],
              limit: 1,
            );
      final current = existing.isEmpty
          ? null
          : Product.fromMap(existing.single);
      final productToUpdate = await _prepareProductForWrite(
        txn,
        product.copyWith(updatedAt: DateTime.now().toUtc()),
      );
      await _assertProductCodeAndBarcodeUnique(
        txn,
        productToUpdate,
        excludeId: product.id,
      );
      final count = await txn.update(
        'products',
        productToUpdate.toMap(),
        where: 'id = ?',
        whereArgs: [product.id],
      );
      if (count > 0 && current != null) {
        final quantityDelta = productToUpdate.quantity - current.quantity;
        await _insertStockMovement(
          txn,
          productId: product.id!,
          productUuid: productToUpdate.uuid,
          movementType: StockMovementType.adjustment,
          quantityDelta: quantityDelta,
          unitCost: productToUpdate.purchasePrice,
          sourceType: 'manual',
          notes: 'Manual stock adjustment',
        );
        await _syncProductQuantityCache(txn, product.id!);
      }
      notifyDatabaseChanged();
      return count;
    });
  }

  Future<int> restockProduct(
    Product product, {
    required num quantityAdded,
    required DateTime purchaseDate,
    String source = ProductSource.mobile,
  }) async {
    await _requireAdminMutation();
    if (product.id == null) throw ArgumentError('Product id is required');
    final db = await database;
    return db.transaction((txn) async {
      final count = await _restockProductInTransaction(
        txn,
        product,
        quantityAdded: quantityAdded,
        purchaseDate: purchaseDate,
        source: source,
      );
      notifyDatabaseChanged();
      return count;
    });
  }

  Future<int> commitProductPurchaseBatch(
    List<ProductPurchaseCommit> commits, {
    required DateTime purchaseDate,
  }) async {
    await _requireAdminMutation();
    if (commits.isEmpty) return 0;
    final db = await database;
    return db.transaction((txn) async {
      var committed = 0;
      for (final commit in commits) {
        final target = commit.restockTarget;
        if (target != null) {
          if (target.id == null) {
            throw ArgumentError('Restock target id is required');
          }
          final restockProduct = commit.product.copyWith(
            id: target.id,
            uuid: target.uuid,
            shopId: target.shopId,
            createdAt: target.createdAt,
          );
          final count = await _restockProductInTransaction(
            txn,
            restockProduct,
            quantityAdded: commit.quantityAdded,
            purchaseDate: purchaseDate,
            source: commit.product.source,
          );
          if (count == 0) {
            throw StateError('Product "${target.name}" no longer exists');
          }
        } else {
          await _insertProductInTransaction(
            txn,
            commit.product,
            purchaseDate: purchaseDate,
          );
        }
        committed++;
      }
      notifyDatabaseChanged();
      return committed;
    });
  }

  Future<int> deleteProduct(int id) async {
    await _requireAdminMutation();
    final db = await database;
    final now = _nowIso();
    final count = await db.update(
      'products',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (count > 0) notifyDatabaseChanged();
    return count;
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
    await _requireAdminMutation();
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
    await _requireAdminMutation();
    final db = await database;
    await _ensureCategory(db, name);
  }

  Future<void> updateCategoryOption(String oldName, String newName) async {
    await _requireAdminMutation();
    final db = await database;
    await _updateNameOption(db, 'categories', oldName, newName);
  }

  Future<void> deleteCategoryOption(String name) async {
    await _requireAdminMutation();
    final db = await database;
    await _softDeleteNameOption(db, 'categories', name);
  }

  Future<void> addSupplierOption(String name) async {
    await _requireAdminMutation();
    final db = await database;
    await _ensureSupplier(db, name);
  }

  Future<void> saveSupplierProfile(
    SupplierProfile supplier, {
    String? oldName,
  }) async {
    await _requireAdminMutation();
    final db = await database;
    final name = _normaliseName(supplier.name);
    if (name == null) throw ArgumentError('Supplier name is required');

    await db.transaction((txn) async {
      final now = _nowIso();
      final shopId = await _activeShopId(txn);
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
                shopId: supplier.shopId.isEmpty ? shopId : supplier.shopId,
                updatedAt: DateTime.parse(now),
              )
              .toMap()
            ..remove('id');

      if (existing.isEmpty) {
        map['uuid'] = supplier.uuid.isEmpty ? _newUuid() : supplier.uuid;
        map['shop_id'] = supplier.shopId.isEmpty ? shopId : supplier.shopId;
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
    await _requireAdminMutation();
    final db = await database;
    await _updateNameOption(db, 'suppliers', oldName, newName);
  }

  Future<void> deleteSupplierOption(String name) async {
    await _requireAdminMutation();
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
    await _requireAdminMutation();
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
    String? productUuid,
    String? itemCode,
    String? barcode,
    required String name,
  }) async {
    final db = await database;
    final uuid = _normaliseName(productUuid);
    if (uuid != null) {
      final rows = await _queryProducts(
        db,
        where: 'p.uuid = ?',
        whereArgs: [uuid],
        limit: 1,
      );
      if (rows.isNotEmpty) return Product.fromMap(rows.first);
    }
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
    final db = await database;
    final category = product.category == null
        ? null
        : await _getCategoryPricing(db, product.category!);
    final breakdown = await resolveProductPrice(product);
    final outputGst = breakdown.outputGstAmount;
    return BillItem(
      uuid: _newUuid(),
      shopId: product.shopId,
      productId: product.id,
      productUuid: product.uuid,
      productName: product.name,
      hsnCodeSnapshot: product.hsnCode ?? category?.hsnCode,
      hsnTypeSnapshot: product.hsnType ?? category?.hsnType,
      unit: product.unit,
      purchasePriceSnapshot: breakdown.purchasePrice,
      sellingPriceSnapshot: breakdown.sellingPrice,
      costSnapshot: breakdown.totalCost,
      profitSnapshot: breakdown.profitAmount,
      commissionSnapshot: 0,
      gstSnapshot: outputGst,
      gstPercentSnapshot: breakdown.gstPercent,
      taxableValueSnapshot: breakdown.preGstSellingPrice,
      cgstAmountSnapshot: breakdown.gstRegistered ? outputGst / 2 : 0,
      sgstAmountSnapshot: breakdown.gstRegistered ? outputGst / 2 : 0,
      wasDirectPrice: breakdown.wasDirectPrice,
    );
  }

  Future<int> replaceAllProducts(
    List<Product> products, {
    DateTime? purchaseDate,
  }) async {
    await _requireAdminMutation();
    final db = await database;
    final date = purchaseDate ?? DateTime.now();
    final cleanProducts = _productsGroupedByIdentity(
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
        final ledgerQuantity = await _ledgerQuantityForProduct(txn, id);
        final stocktakeDelta = p.quantity - ledgerQuantity;
        await _insertStockMovement(
          txn,
          productId: id,
          productUuid: writeProduct.uuid,
          movementType: StockMovementType.stocktake,
          quantityDelta: stocktakeDelta,
          unitCost: writeProduct.purchasePrice,
          sourceType: 'import',
          supplierId: writeProduct.supplierId,
          importBatchKey: batchKey,
          notes: 'Import replacement stocktake',
          createdAt: date,
        );
        await _syncProductQuantityCache(txn, id);
        count++;
      }
      notifyDatabaseChanged();
      return count;
    });
  }

  Future<ProductImportResult> mergeProducts(
    List<Product> products, {
    DateTime? purchaseDate,
  }) async {
    await _requireAdminMutation();
    final db = await database;
    final date = purchaseDate ?? DateTime.now();
    final cleanProducts = products.map(_asImportedProduct).toList();
    final batchKey = _importBatchKey(cleanProducts, date);
    final rowSetKey = _importRowSetKey(cleanProducts);

    return db.transaction((txn) async {
      int added = 0, updated = 0;
      final possibleDuplicate = await _hasImportBatch(txn, batchKey);
      final duplicateOnDifferentDate = !possibleDuplicate
          ? await _hasImportRowSet(txn, rowSetKey)
          : false;
      for (var rowNumber = 0; rowNumber < cleanProducts.length; rowNumber++) {
        final p = cleanProducts[rowNumber];
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
            supplierId: merged.supplierId,
            importBatchKey: batchKey,
            importRowNumber: rowNumber + 1,
            createdAt: date,
          );
          await _syncProductQuantityCache(txn, existingId);
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
            supplierId: writeProduct.supplierId,
            importBatchKey: batchKey,
            importRowNumber: rowNumber + 1,
            createdAt: date,
          );
          await _syncProductQuantityCache(txn, id);
          added++;
        }
      }
      notifyDatabaseChanged();
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
    final cleanProducts = products;
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

  List<Product> _productsGroupedByIdentity(List<Product> products) {
    final byIdentity = <String, Product>{};
    for (final product in products) {
      final identity = _productIdentity(product);
      final existing = byIdentity[identity];
      byIdentity[identity] = existing == null
          ? product
          : product.copyWith(quantity: existing.quantity + product.quantity);
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

  Future<void> _assertProductCodeAndBarcodeUnique(
    DatabaseExecutor executor,
    Product product, {
    int? excludeId,
  }) async {
    Future<void> checkField(
      String column,
      String label,
      String? rawValue,
    ) async {
      final value = _normaliseName(rawValue);
      if (value == null) return;
      final rows = await _queryProducts(
        executor,
        where: excludeId == null
            ? 'LOWER(p.$column) = LOWER(?)'
            : 'LOWER(p.$column) = LOWER(?) AND p.id != ?',
        whereArgs: excludeId == null ? [value] : [value, excludeId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        throw ArgumentError('$label "$value" already exists');
      }
    }

    await checkField('product_code', 'Product code', product.productCode);
    await checkField('barcode', 'Barcode', product.barcode);
  }

  Future<int> _insertProductInTransaction(
    DatabaseExecutor executor,
    Product product, {
    DateTime? purchaseDate,
  }) async {
    final productToInsert = await _prepareProductForWrite(executor, product);
    await _assertProductCodeAndBarcodeUnique(executor, productToInsert);
    final id = await executor.insert(
      'products',
      productToInsert.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
    if (productToInsert.quantity > 0) {
      await _insertStockMovement(
        executor,
        productId: id,
        productUuid: productToInsert.uuid,
        movementType: StockMovementType.purchase,
        quantityDelta: productToInsert.quantity,
        unitCost: productToInsert.purchasePrice,
        sourceType: productToInsert.source == ProductSource.imported
            ? 'import'
            : 'manual',
        supplierId: productToInsert.supplierId,
        createdAt: purchaseDate ?? productToInsert.createdAt,
      );
      await _syncProductQuantityCache(executor, id);
    }
    return id;
  }

  Future<int> _restockProductInTransaction(
    DatabaseExecutor executor,
    Product product, {
    required num quantityAdded,
    required DateTime purchaseDate,
    String source = ProductSource.mobile,
  }) async {
    if (product.id == null) throw ArgumentError('Product id is required');
    final existing = await _queryProducts(
      executor,
      where: 'p.id = ?',
      whereArgs: [product.id],
      limit: 1,
    );
    if (existing.isEmpty) return 0;
    final current = Product.fromMap(existing.single);
    final updatedProduct = await _prepareProductForWrite(
      executor,
      product.copyWith(
        quantity: current.quantity + quantityAdded,
        source: source,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await _assertProductCodeAndBarcodeUnique(
      executor,
      updatedProduct,
      excludeId: product.id,
    );
    final count = await executor.update(
      'products',
      updatedProduct.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
    await _insertStockMovement(
      executor,
      productId: product.id!,
      productUuid: updatedProduct.uuid,
      movementType: StockMovementType.purchase,
      quantityDelta: quantityAdded.toDouble(),
      unitCost: updatedProduct.purchasePrice,
      sourceType: source == ProductSource.imported ? 'import' : 'manual',
      supplierId: updatedProduct.supplierId,
      createdAt: purchaseDate,
    );
    await _syncProductQuantityCache(executor, product.id!);
    return count;
  }

  Future<Product> _prepareProductForWrite(
    DatabaseExecutor executor,
    Product product,
  ) async {
    if (product.quantity < 0) {
      throw ArgumentError('Product quantity cannot be negative');
    }
    final now = DateTime.now().toUtc();
    final shopId = await _activeShopId(executor);
    final categoryId = product.category == null
        ? product.categoryId
        : await _ensureCategory(executor, product.category!);
    final supplierId = product.supplier == null
        ? product.supplierId
        : await _ensureSupplier(executor, product.supplier!);
    final unitId = product.unit == null
        ? product.unitId
        : await _ensureUnit(executor, product.unit!);
    final globalPricing = await _getGlobalPricingSettingsFromExecutor(executor);
    final categoryPricing = product.category == null
        ? null
        : await _getCategoryPricing(executor, product.category!);
    final pricedProduct = product.copyWith(
      uuid: product.uuid.isEmpty ? _newUuid() : product.uuid,
      shopId: product.shopId.isEmpty || product.shopId == _legacyShopId
          ? shopId
          : product.shopId,
      categoryId: categoryId,
      supplierId: supplierId,
      unitId: unitId,
      createdAt: product.createdAt,
      updatedAt: now,
    );
    final breakdown = _resolveProductPrice(
      pricedProduct,
      globalPricing,
      categoryPricing,
    );
    return pricedProduct.copyWith(sellingPrice: breakdown.sellingPrice);
  }

  Future<void> _insertStockMovement(
    DatabaseExecutor executor, {
    required int productId,
    required String productUuid,
    required String movementType,
    required double quantityDelta,
    double? unitCost,
    String? sourceType,
    int? supplierId,
    String? supplierUuid,
    String? sourceDocumentType,
    int? sourceDocumentId,
    String? sourceDocumentUuid,
    String? importBatchKey,
    int? importRowNumber,
    String? notes,
    DateTime? createdAt,
  }) async {
    if (quantityDelta == 0) return;
    final now = DateTime.now().toUtc();
    final shopId = await _activeShopId(executor);
    final resolvedSupplierUuid =
        supplierUuid ??
        (supplierId == null
            ? null
            : await _uuidForId(executor, 'suppliers', supplierId));
    await executor.insert('stock_movements', {
      'uuid': _newUuid(),
      'shop_id': shopId,
      'product_id': productId,
      'product_uuid': productUuid,
      'movement_type': movementType,
      'quantity_delta': quantityDelta,
      'unit_cost': unitCost,
      'source_type': sourceType,
      'supplier_id': supplierId,
      'supplier_uuid': resolvedSupplierUuid,
      'source_document_type': sourceDocumentType,
      'source_document_id': sourceDocumentId,
      'source_document_uuid': sourceDocumentUuid,
      'import_batch_key': importBatchKey,
      'import_row_number': importRowNumber,
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

  Future<double> _ledgerQuantityForProduct(
    DatabaseExecutor executor,
    int productId,
  ) async {
    final rows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(quantity_delta), 0) AS quantity
      FROM stock_movements
      WHERE deleted_at IS NULL AND product_id = ?
      ''',
      [productId],
    );
    return (rows.single['quantity'] as num?)?.toDouble() ?? 0.0;
  }

  Future<void> _syncProductQuantityCache(
    DatabaseExecutor executor,
    int productId,
  ) async {
    final quantity = await _ledgerQuantityForProduct(executor, productId);
    await executor.update(
      'products',
      {'quantity_cache': quantity, 'updated_at': _nowIso()},
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<void> rebuildAllProductQuantityCaches(
    DatabaseExecutor executor,
  ) async {
    await executor.rawUpdate(
      '''
      UPDATE products
      SET quantity_cache = COALESCE((
            SELECT SUM(quantity_delta)
            FROM stock_movements
            WHERE stock_movements.deleted_at IS NULL
              AND stock_movements.product_id = products.id
          ), 0),
          updated_at = ?
      WHERE deleted_at IS NULL
      ''',
      [_nowIso()],
    );
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

Future<GlobalPricingSettings> _getGlobalPricingSettingsFromExecutor(
  DatabaseExecutor executor,
) async {
  final shopId = await _activeShopId(executor);
  final rows = await executor.query(
    'app_settings',
    where: 'shop_id = ? AND deleted_at IS NULL',
    whereArgs: [shopId],
  );
  final values = {
    for (final row in rows) row['key'] as String: row['value']?.toString(),
  };
  return GlobalPricingSettings(
    defaultGstPercent:
        double.tryParse(values['default_gst_percent'] ?? '') ?? 18,
    defaultOverheadCost:
        double.tryParse(values['default_overhead_cost'] ?? '') ?? 0,
    defaultProfitMarginPercent:
        double.tryParse(values['default_profit_margin_percent'] ?? '') ?? 0,
    gstRegistered: values['gst_registered'] == '1',
    showPurchasePriceGlobally: values['show_purchase_price_globally'] == '1',
  );
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
  final shopId = await _activeShopId(executor);
  return executor.insert(table, {
    'uuid': _newUuid(),
    'shop_id': shopId,
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
