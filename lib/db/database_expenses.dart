part of 'database_helper.dart';

Future<void> _createExpenseTables(DatabaseExecutor executor) async {
  await executor.execute('''
    CREATE TABLE IF NOT EXISTS expenses(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      shop_id TEXT NOT NULL,
      expense_date TEXT NOT NULL,
      amount REAL NOT NULL,
      category TEXT NOT NULL DEFAULT 'Other',
      payment_method TEXT NOT NULL DEFAULT 'cash',
      notes TEXT,
      device_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
  await executor.execute('''
    CREATE INDEX IF NOT EXISTS idx_expenses_shop_date
    ON expenses(shop_id, expense_date)
  ''');
}

mixin DatabaseExpenses {
  Future<Database> get database;

  /// Adds or (with [Expense.id]) edits an expense. Owner/admin only.
  Future<void> saveExpense(Expense expense) async {
    await _requireAdminMutation();
    if (expense.amount <= 0) throw ArgumentError('Amount must be above zero');
    final db = await database;
    final now = _nowIso();
    final values = {
      'expense_date': _localIso(expense.date),
      'amount': roundMoney(expense.amount),
      'category': expense.category.trim().isEmpty
          ? 'Other'
          : expense.category.trim(),
      'payment_method': expense.paymentMethod,
      'notes': _normaliseName(expense.notes),
      'updated_at': now,
    };
    if (expense.id == null) {
      await db.insert('expenses', {
        ...values,
        'uuid': _newUuid(),
        'shop_id': await _activeShopId(db),
        'created_at': now,
      });
    } else {
      await db.update(
        'expenses',
        values,
        where: 'id = ?',
        whereArgs: [expense.id],
      );
    }
    notifyDatabaseChanged();
  }

  Future<void> deleteExpense(int id) async {
    await _requireAdminMutation();
    final db = await database;
    final now = _nowIso();
    await db.update(
      'expenses',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyDatabaseChanged();
  }

  /// Expenses dated [from]..[to] inclusive (yyyy-MM-dd), newest first.
  Future<List<Expense>> getExpenses({String? from, String? to}) async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final where = ['shop_id = ?', 'deleted_at IS NULL'];
    final args = <Object>[shopId];
    if (from != null) {
      where.add('substr(expense_date, 1, 10) >= ?');
      args.add(from);
    }
    if (to != null) {
      where.add('substr(expense_date, 1, 10) <= ?');
      args.add(to);
    }
    final rows = await db.query(
      'expenses',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'expense_date DESC, id DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }
}
