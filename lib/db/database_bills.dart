part of 'database_helper.dart';

mixin DatabaseBills {
  Future<Database> get database;

  Future<int> insertBill(Bill bill, List<BillItem> items) async {
    final db = await database;
    return db.transaction((txn) async {
      final billId = await txn.insert('bills', bill.toMap());
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

  Future<int> deleteBill(int id) async {
    final db = await database;
    await db.delete('bill_items', where: 'bill_id = ?', whereArgs: [id]);
    return db.delete('bills', where: 'id = ?', whereArgs: [id]);
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
}
