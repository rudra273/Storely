part of 'database_helper.dart';

mixin DatabaseBills {
  Future<Database> get database;
  Future<void> _syncCustomersFromBills(DatabaseExecutor executor);

  Future<int> insertBill(Bill bill, List<BillItem> items) async {
    final db = await database;
    return db.transaction((txn) async {
      final customerId = await _upsertCustomerForBill(txn, bill);
      final billMap = bill.toMap()..['customer_id'] = customerId;
      final billId = await txn.insert('bills', billMap);
      for (final item in items) {
        await txn.insert('bill_items', item.toMap(billId));
        await _deductProductStock(txn, item);
      }
      return billId;
    });
  }

  Future<List<Bill>> getAllBills() async {
    final db = await database;
    final billMaps = await db.query('bills', orderBy: 'created_at DESC');
    final bills = <Bill>[];
    for (final map in billMaps) {
      final itemMaps = await db.query(
        'bill_items',
        where: 'bill_id = ?',
        whereArgs: [map['id']],
      );
      final items = itemMaps.map((m) => BillItem.fromMap(m)).toList();
      bills.add(Bill.fromMap(map, items));
    }
    return bills;
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    await _syncCustomersFromBills(db);
    final maps = await db.query(
      'customers',
      orderBy: 'total_purchase_amount DESC, updated_at DESC',
    );
    return maps.map((map) => Customer.fromMap(map)).toList();
  }

  Future<int> deleteBill(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'bills',
        columns: ['customer_id', 'total_amount'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final customerId = rows.single['customer_id'] as int?;
        final totalAmount =
            (rows.single['total_amount'] as num?)?.toDouble() ?? 0;
        if (customerId != null) {
          await _adjustCustomerLedger(
            txn,
            customerId: customerId,
            amountDelta: -totalAmount,
            billCountDelta: -1,
          );
        }
      }
      await txn.delete('bill_items', where: 'bill_id = ?', whereArgs: [id]);
      return txn.delete('bills', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> updateBillPaidStatus(int id, bool isPaid) async {
    final db = await database;
    return db.update(
      'bills',
      {'is_paid': isPaid ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateBillProfitCommissionPercent(int id, double percent) async {
    final db = await database;
    return db.update(
      'bills',
      {'profit_commission_percent': percent.clamp(0, 100).toDouble()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getBillCount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM bills');
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<double> getTodaySales() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount),0) as s FROM bills WHERE created_at LIKE ?',
      ['$today%'],
    );
    return (r.first['s'] as num).toDouble();
  }

  Future<int> getTodayBillCount() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM bills WHERE created_at LIKE ?',
      ['$today%'],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<Bill>> getUnpaidBills({int? limit}) async {
    final db = await database;
    final billMaps = await db.query(
      'bills',
      where: 'is_paid = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    final bills = <Bill>[];
    for (final map in billMaps) {
      final itemMaps = await db.query(
        'bill_items',
        where: 'bill_id = ?',
        whereArgs: [map['id']],
      );
      final items = itemMaps.map((m) => BillItem.fromMap(m)).toList();
      bills.add(Bill.fromMap(map, items));
    }
    return bills;
  }

  Future<void> _deductProductStock(
    DatabaseExecutor executor,
    BillItem item,
  ) async {
    if (item.quantity <= 0) return;

    await executor.rawUpdate(
      '''
      UPDATE products
      SET quantity = MAX(quantity - ?, 0)
      WHERE ${item.productId == null ? 'LOWER(name) = LOWER(?)' : 'id = ?'}
      ''',
      [item.quantity, item.productId ?? item.productName],
    );
  }

  Future<int?> _upsertCustomerForBill(DatabaseExecutor executor, Bill bill) {
    final phone = _normaliseCustomerPhone(bill.customerPhone);
    if (phone == null) return Future.value(null);
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

Future<int> _upsertCustomerLedger(
  DatabaseExecutor executor, {
  required String name,
  required String phone,
  required double amountDelta,
  required int billCountDelta,
  required String purchaseAt,
}) async {
  final existing = await executor.query(
    'customers',
    columns: ['id', 'name'],
    where: 'phone = ?',
    whereArgs: [phone],
    limit: 1,
  );
  final now = DateTime.now().toIso8601String();
  if (existing.isEmpty) {
    return executor.insert('customers', {
      'name': name,
      'phone': phone,
      'total_purchase_amount': amountDelta,
      'bill_count': billCountDelta,
      'last_purchase_at': purchaseAt,
      'created_at': now,
      'updated_at': now,
    });
  }

  final id = existing.single['id'] as int;
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
  return id;
}

Future<void> _adjustCustomerLedger(
  DatabaseExecutor executor, {
  required int customerId,
  required double amountDelta,
  required int billCountDelta,
}) async {
  final now = DateTime.now().toIso8601String();
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
