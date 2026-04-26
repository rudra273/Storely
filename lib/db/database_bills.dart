part of 'database_helper.dart';

mixin DatabaseBills {
  Future<Database> get database;
  Future<void> syncCustomersFromBills(DatabaseExecutor executor);

  Future<int> insertBill(Bill bill, List<BillItem> items) async {
    final db = await database;
    return db.transaction((txn) async {
      final billUuid = bill.uuid.isEmpty ? _newUuid() : bill.uuid;
      final billNumber = bill.billNumber.isEmpty
          ? await _nextBillNumber(txn, bill.createdAt)
          : bill.billNumber;
      final customerInfo = await _upsertCustomerForBill(txn, bill);
      final billMap = {
        ...bill.toMap(),
        'uuid': billUuid,
        'shop_id': bill.shopId.isEmpty ? _defaultShopId : bill.shopId,
        'bill_number': billNumber,
        'customer_id': customerInfo?.id,
        'customer_uuid': customerInfo?.uuid,
        'updated_at': _nowIso(),
      };
      final billId = await txn.insert('bills', billMap..remove('id'));
      for (final item in items) {
        final itemMap = {
          ...item.toMap(billId, billUuid: billUuid),
          'uuid': item.uuid.isEmpty ? _newUuid() : item.uuid,
          'shop_id': item.shopId.isEmpty ? _defaultShopId : item.shopId,
          'bill_uuid': billUuid,
          'created_at': bill.createdAt.toIso8601String(),
          'updated_at': _nowIso(),
        };
        await txn.insert('bill_items', itemMap..remove('id'));
        await _applySaleStockMovement(
          txn,
          item: item,
          billId: billId,
          billUuid: billUuid,
          createdAt: bill.createdAt,
        );
      }
      return billId;
    });
  }

  Future<List<Bill>> getAllBills() async {
    final db = await database;
    final billMaps = await db.query(
      'bills',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    final bills = <Bill>[];
    for (final map in billMaps) {
      final itemMaps = await db.query(
        'bill_items',
        where: 'deleted_at IS NULL AND bill_id = ?',
        whereArgs: [map['id']],
      );
      final items = itemMaps.map((m) => BillItem.fromMap(m)).toList();
      bills.add(Bill.fromMap(map, items));
    }
    return bills;
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    await syncCustomersFromBills(db);
    final maps = await db.query(
      'customers',
      where: 'deleted_at IS NULL',
      orderBy: 'total_purchase_amount DESC, updated_at DESC',
    );
    return maps.map((map) => Customer.fromMap(map)).toList();
  }

  Future<void> saveCustomerProfile(Customer customer) async {
    final db = await database;
    final name = _normaliseName(customer.name) ?? 'Walk-in Customer';
    final phone = _normaliseCustomerPhone(customer.phone);
    final now = _nowIso();

    await db.transaction((txn) async {
      if (phone != null) {
        final duplicate = await txn.query(
          'customers',
          columns: ['id'],
          where: customer.id == null
              ? 'deleted_at IS NULL AND shop_id = ? AND phone = ?'
              : 'deleted_at IS NULL AND shop_id = ? AND phone = ? AND id != ?',
          whereArgs: customer.id == null
              ? [_defaultShopId, phone]
              : [_defaultShopId, phone, customer.id],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          throw ArgumentError('Phone number already exists');
        }
      }

      final map =
          customer
              .copyWith(
                uuid: customer.uuid.isEmpty ? _newUuid() : customer.uuid,
                shopId: customer.shopId.isEmpty
                    ? _defaultShopId
                    : customer.shopId,
                name: name,
                phone: phone ?? '',
                updatedAt: DateTime.parse(now),
              )
              .toMap()
            ..remove('id');

      if (customer.id == null) {
        map['created_at'] = now;
        map['updated_at'] = now;
        await txn.insert('customers', map);
        return;
      }

      await txn.update(
        'customers',
        map,
        where: 'id = ?',
        whereArgs: [customer.id],
      );
      await txn.update(
        'bills',
        {'customer_name': name, 'customer_phone': phone, 'updated_at': now},
        where: 'deleted_at IS NULL AND customer_id = ?',
        whereArgs: [customer.id],
      );
      await syncCustomersFromBills(txn);
    });
  }

  Future<int> deleteBill(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'bills',
        columns: ['uuid', 'customer_id', 'total_amount', 'deleted_at'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['deleted_at'] != null) return 0;
      final now = _nowIso();
      final billUuid = rows.single['uuid'] as String;
      final customerId = rows.single['customer_id'] as int?;
      final totalAmount =
          (rows.single['total_amount'] as num?)?.toDouble() ?? 0;
      final itemRows = await txn.query(
        'bill_items',
        where: 'deleted_at IS NULL AND bill_id = ?',
        whereArgs: [id],
      );
      for (final row in itemRows) {
        final item = BillItem.fromMap(row);
        if (item.productId != null && item.productUuid != null) {
          await _insertBillStockMovement(
            txn,
            productId: item.productId!,
            productUuid: item.productUuid!,
            movementType: StockMovementType.voidSale,
            quantityDelta: item.quantity,
            sourceType: 'bill_void',
            sourceId: id,
            sourceUuid: billUuid,
          );
          await _adjustProductQuantity(txn, item.productId!, item.quantity);
        }
      }
      await txn.update(
        'bill_items',
        {'deleted_at': now, 'updated_at': now},
        where: 'bill_id = ?',
        whereArgs: [id],
      );
      final count = await txn.update(
        'bills',
        {'deleted_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (customerId != null) {
        await _adjustCustomerLedger(
          txn,
          customerId: customerId,
          amountDelta: -totalAmount,
          billCountDelta: -1,
        );
      }
      return count;
    });
  }

  Future<int> updateBillPaidStatus(int id, bool isPaid) async {
    final db = await database;
    return db.update(
      'bills',
      {'is_paid': isPaid ? 1 : 0, 'updated_at': _nowIso()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateBillProfitCommissionPercent(int id, double percent) async {
    final db = await database;
    return db.update(
      'bills',
      {
        'profit_commission_percent': percent.clamp(0, 100).toDouble(),
        'updated_at': _nowIso(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getBillCount() async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM bills WHERE deleted_at IS NULL',
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<double> getTodaySales() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount),0) as s FROM bills WHERE deleted_at IS NULL AND created_at LIKE ?',
      ['$today%'],
    );
    return (r.first['s'] as num).toDouble();
  }

  Future<int> getTodayBillCount() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM bills WHERE deleted_at IS NULL AND created_at LIKE ?',
      ['$today%'],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<Bill>> getUnpaidBills({int? limit}) async {
    final db = await database;
    final billMaps = await db.query(
      'bills',
      where: 'deleted_at IS NULL AND is_paid = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    final bills = <Bill>[];
    for (final map in billMaps) {
      final itemMaps = await db.query(
        'bill_items',
        where: 'deleted_at IS NULL AND bill_id = ?',
        whereArgs: [map['id']],
      );
      final items = itemMaps.map((m) => BillItem.fromMap(m)).toList();
      bills.add(Bill.fromMap(map, items));
    }
    return bills;
  }

  Future<String> _nextBillNumber(
    DatabaseExecutor executor,
    DateTime createdAt,
  ) async {
    final date =
        '${createdAt.year.toString().padLeft(4, '0')}'
        '${createdAt.month.toString().padLeft(2, '0')}'
        '${createdAt.day.toString().padLeft(2, '0')}';
    const deviceId = 'local';
    final prefix = 'SHOP-LOCAL-$deviceId-$date';
    final rows = await executor.rawQuery(
      'SELECT COUNT(*) + 1 AS next_seq FROM bills WHERE device_id IS NULL AND bill_number LIKE ?',
      ['$prefix-%'],
    );
    final seq = (rows.first['next_seq'] as num?)?.toInt() ?? 1;
    return '$prefix-${seq.toString().padLeft(4, '0')}';
  }

  Future<void> _applySaleStockMovement(
    DatabaseExecutor executor, {
    required BillItem item,
    required int billId,
    required String billUuid,
    required DateTime createdAt,
  }) async {
    if (item.quantity <= 0 || item.productId == null) return;
    final productRows = await executor.query(
      'products',
      columns: ['uuid'],
      where: 'id = ?',
      whereArgs: [item.productId],
      limit: 1,
    );
    if (productRows.isEmpty) return;
    final productUuid =
        item.productUuid ?? productRows.single['uuid'] as String;
    await _insertBillStockMovement(
      executor,
      productId: item.productId!,
      productUuid: productUuid,
      movementType: StockMovementType.sale,
      quantityDelta: -item.quantity,
      sourceType: 'bill',
      sourceId: billId,
      sourceUuid: billUuid,
      createdAt: createdAt,
    );
    await _adjustProductQuantity(executor, item.productId!, -item.quantity);
  }

  Future<void> _insertBillStockMovement(
    DatabaseExecutor executor, {
    required int productId,
    required String productUuid,
    required String movementType,
    required double quantityDelta,
    String? sourceType,
    int? sourceId,
    String? sourceUuid,
    DateTime? createdAt,
  }) async {
    final now = DateTime.now();
    await executor.insert('stock_movements', {
      'uuid': _newUuid(),
      'shop_id': _defaultShopId,
      'product_id': productId,
      'product_uuid': productUuid,
      'movement_type': movementType,
      'quantity_delta': quantityDelta,
      'source_type': sourceType,
      'source_id': sourceId,
      'source_uuid': sourceUuid,
      'created_at': (createdAt ?? now).toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  Future<void> _adjustProductQuantity(
    DatabaseExecutor executor,
    int productId,
    double delta,
  ) async {
    await executor.rawUpdate(
      '''
      UPDATE products
      SET quantity_cache = MAX(quantity_cache + ?, 0),
          updated_at = ?
      WHERE id = ?
      ''',
      [delta, _nowIso(), productId],
    );
  }

  Future<_CustomerRef?> _upsertCustomerForBill(
    DatabaseExecutor executor,
    Bill bill,
  ) async {
    final phone = _normaliseCustomerPhone(bill.customerPhone);
    if (phone == null) return null;
    final name = _normaliseName(bill.customerName) ?? 'Walk-in Customer';
    return _upsertCustomerLedger(
      executor,
      name: name,
      phone: phone,
      amountDelta: bill.totalAmount,
      billCountDelta: 1,
      purchaseAt: bill.createdAt.toIso8601String(),
    );
  }
}

class _CustomerRef {
  final int id;
  final String uuid;

  const _CustomerRef({required this.id, required this.uuid});
}

Future<_CustomerRef> _upsertCustomerLedger(
  DatabaseExecutor executor, {
  required String name,
  required String phone,
  required double amountDelta,
  required int billCountDelta,
  required String purchaseAt,
}) async {
  final existing = await executor.query(
    'customers',
    columns: ['id', 'uuid', 'name'],
    where: 'shop_id = ? AND phone = ? AND deleted_at IS NULL',
    whereArgs: [_defaultShopId, phone],
    limit: 1,
  );
  final now = _nowIso();
  if (existing.isEmpty) {
    final uuid = _newUuid();
    final id = await executor.insert('customers', {
      'uuid': uuid,
      'shop_id': _defaultShopId,
      'name': name,
      'phone': phone,
      'total_purchase_amount': amountDelta,
      'bill_count': billCountDelta,
      'last_purchase_at': purchaseAt,
      'created_at': now,
      'updated_at': now,
    });
    return _CustomerRef(id: id, uuid: uuid);
  }

  final id = existing.single['id'] as int;
  final uuid = existing.single['uuid'] as String;
  final updateName = name.trim().isNotEmpty && name != 'Walk-in Customer';
  await executor.rawUpdate(
    '''
    UPDATE customers
    SET
      name = CASE WHEN ? THEN ? ELSE name END,
      total_purchase_amount = MAX(total_purchase_amount + ?, 0),
      bill_count = MAX(bill_count + ?, 0),
      last_purchase_at = ?,
      updated_at = ?
    WHERE id = ?
    ''',
    [
      updateName ? 1 : 0,
      name,
      amountDelta,
      billCountDelta,
      purchaseAt,
      now,
      id,
    ],
  );
  return _CustomerRef(id: id, uuid: uuid);
}

Future<void> _adjustCustomerLedger(
  DatabaseExecutor executor, {
  required int customerId,
  required double amountDelta,
  required int billCountDelta,
}) async {
  final now = _nowIso();
  await executor.rawUpdate(
    '''
    UPDATE customers
    SET
      total_purchase_amount = MAX(total_purchase_amount + ?, 0),
      bill_count = MAX(bill_count + ?, 0),
      updated_at = ?
    WHERE id = ?
    ''',
    [amountDelta, billCountDelta, now, customerId],
  );
}

String? _normaliseCustomerPhone(Object? value) {
  final digits = value?.toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits == null || digits.isEmpty || digits == '91') return null;
  if (digits.length == 10) return '91$digits';
  return digits;
}
