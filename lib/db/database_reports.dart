part of 'database_helper.dart';

/// One day's bills, payments and expenses, with the cash movement.
class DayBook {
  final String day;

  /// Invoices and credit notes created that day (credit notes negative).
  final List<Map<String, dynamic>> bills;

  /// Money received (positive) or refunded (negative) that day, by method.
  /// Credit-note adjustments move no money and are left out.
  final Map<String, double> paymentsByMethod;
  final List<Expense> expenses;

  const DayBook({
    required this.day,
    required this.bills,
    required this.paymentsByMethod,
    required this.expenses,
  });

  double get sales =>
      bills.fold(0.0, (sum, b) => sum + (b['total_amount'] as num).toDouble());
  double get collected =>
      paymentsByMethod.values.fold(0.0, (sum, v) => sum + v);
  double get cashReceived => paymentsByMethod['cash'] ?? 0;
  double get cashExpenses => expenses
      .where((e) => e.paymentMethod == 'cash')
      .fold(0.0, (sum, e) => sum + e.amount);
  double get totalExpenses => expenses.fold(0.0, (sum, e) => sum + e.amount);

  /// How much the cash drawer changed: cash in less cash refunds and cash
  /// expenses.
  double get netCash => roundMoney(cashReceived - cashExpenses);
}

/// Profit and loss for a period, net of returns. Sales and cost exclude GST.
class ProfitAndLoss {
  final double sales;
  final double costOfGoods;
  final double gstCollected;
  final Map<String, double> expensesByCategory;

  const ProfitAndLoss({
    required this.sales,
    required this.costOfGoods,
    required this.gstCollected,
    required this.expensesByCategory,
  });

  double get grossProfit => roundMoney(sales - costOfGoods);
  double get expenses =>
      roundMoney(expensesByCategory.values.fold(0.0, (s, v) => s + v));
  double get netProfit => roundMoney(grossProfit - expenses);
}

/// What one customer owes, split by how old the bills are.
class AgeingRow {
  final String customerName;
  final String? customerPhone;
  final List<double> buckets;

  const AgeingRow({
    required this.customerName,
    required this.customerPhone,
    required this.buckets,
  });

  double get total => roundMoney(buckets.fold(0.0, (s, v) => s + v));
}

/// Stock on hand at cost and at selling price.
class StockValueRow {
  final String name;
  final String? category;
  final String? unit;
  final double quantity;
  final double costValue;
  final double saleValue;

  const StockValueRow({
    required this.name,
    required this.category,
    required this.unit,
    required this.quantity,
    required this.costValue,
    required this.saleValue,
  });
}

/// Stock from one purchase batch that expires soon (or already has).
class ExpiringBatch {
  final int productId;
  final String productName;
  final String? unit;
  final String? batchNo;
  final DateTime expiry;

  /// Estimated units of this batch still on the shelf (older stock is
  /// assumed to sell first).
  final double quantity;

  const ExpiringBatch({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.batchNo,
    required this.expiry,
    required this.quantity,
  });

  bool isExpired(DateTime today) =>
      expiry.isBefore(DateTime(today.year, today.month, today.day));
}

mixin DatabaseReports {
  Future<Database> get database;
  Future<List<Expense>> getExpenses({String? from, String? to});

  /// Bucket labels for [receivablesAgeing], oldest last.
  static const ageingBuckets = [
    '0-7 days',
    '8-30 days',
    '31-60 days',
    '60+ days',
  ];

  Future<DayBook> dayBook(String day) async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final bills = await db.rawQuery(
      '''
      SELECT id, bill_number, customer_name, total_amount, paid_amount,
             balance_due, document_type, created_at
      FROM bills
      WHERE shop_id = ? AND deleted_at IS NULL
        AND substr(created_at, 1, 10) = ?
      ORDER BY created_at ASC, id ASC
    ''',
      [shopId, day],
    );
    final payments = await db.rawQuery(
      '''
      SELECT p.payment_method AS method, ROUND(SUM(p.amount), 2) AS amount
      FROM bill_payments p
      JOIN bills b ON b.uuid = p.bill_uuid
      WHERE p.shop_id = ? AND p.deleted_at IS NULL AND b.deleted_at IS NULL
        AND p.payment_method <> 'credit_note'
        AND substr(p.received_at, 1, 10) = ?
      GROUP BY p.payment_method
    ''',
      [shopId, day],
    );
    final expenses = await getExpenses(from: day, to: day);
    return DayBook(
      day: day,
      bills: bills,
      paymentsByMethod: {
        for (final row in payments)
          row['method'] as String: (row['amount'] as num).toDouble(),
      },
      expenses: expenses,
    );
  }

  Future<ProfitAndLoss> profitAndLoss({String? from, String? to}) async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final itemDates = _rangeWhere('b.created_at', from, to);
    final totals = await db.rawQuery(
      '''
      SELECT ROUND(COALESCE(SUM(bi.taxable_value_snapshot * bi.quantity), 0), 2)
               AS sales,
             ROUND(COALESCE(SUM(bi.cost_snapshot * bi.quantity), 0), 2) AS cost
      FROM bill_items bi
      JOIN bills b ON b.id = bi.bill_id
      WHERE b.shop_id = ? AND b.deleted_at IS NULL AND bi.deleted_at IS NULL
        ${itemDates.sql}
    ''',
      [shopId, ...itemDates.args],
    );
    final billDates = _rangeWhere('created_at', from, to);
    final gst = await db.rawQuery(
      '''
      SELECT ROUND(COALESCE(SUM(cgst_amount + sgst_amount + igst_amount), 0), 2)
               AS gst
      FROM bills
      WHERE shop_id = ? AND deleted_at IS NULL ${billDates.sql}
    ''',
      [shopId, ...billDates.args],
    );
    final expenseDates = _rangeWhere('expense_date', from, to);
    final expenses = await db.rawQuery(
      '''
      SELECT category, ROUND(SUM(amount), 2) AS amount
      FROM expenses
      WHERE shop_id = ? AND deleted_at IS NULL ${expenseDates.sql}
      GROUP BY category
      ORDER BY amount DESC
    ''',
      [shopId, ...expenseDates.args],
    );
    return ProfitAndLoss(
      sales: (totals.first['sales'] as num).toDouble(),
      costOfGoods: (totals.first['cost'] as num).toDouble(),
      gstCollected: (gst.first['gst'] as num).toDouble(),
      expensesByCategory: {
        for (final row in expenses)
          row['category'] as String: (row['amount'] as num).toDouble(),
      },
    );
  }

  /// Unpaid balances per customer, by bill age on [asOf] (default today).
  Future<List<AgeingRow>> receivablesAgeing({DateTime? asOf}) async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final today = asOf ?? DateTime.now();
    final rows = await db.rawQuery(
      '''
      SELECT customer_name, customer_phone, balance_due, created_at
      FROM bills
      WHERE shop_id = ? AND deleted_at IS NULL AND balance_due > 0.005
        AND document_type <> 'credit_note'
    ''',
      [shopId],
    );
    final byCustomer = <String, AgeingRow>{};
    for (final row in rows) {
      final name = (row['customer_name'] as String?)?.trim();
      final phone = (row['customer_phone'] as String?)?.trim();
      final key = (phone != null && phone.isNotEmpty)
          ? phone
          : (name ?? '').toLowerCase();
      final created = DateTime.parse(row['created_at'] as String);
      final age = DateTime(
        today.year,
        today.month,
        today.day,
      ).difference(DateTime(created.year, created.month, created.day)).inDays;
      final bucket = age <= 7
          ? 0
          : age <= 30
          ? 1
          : age <= 60
          ? 2
          : 3;
      final entry = byCustomer.putIfAbsent(
        key,
        () => AgeingRow(
          customerName: name == null || name.isEmpty ? 'Walk-in' : name,
          customerPhone: phone,
          buckets: [0, 0, 0, 0],
        ),
      );
      entry.buckets[bucket] = roundMoney(
        entry.buckets[bucket] + (row['balance_due'] as num).toDouble(),
      );
    }
    return byCustomer.values.toList()
      ..sort((a, b) => b.total.compareTo(a.total));
  }

  /// Batches expiring within [days] (and expired ones still in stock),
  /// soonest first. Stock on hand is matched to the newest purchases, as
  /// older stock normally sells first.
  Future<List<ExpiringBatch>> expiringStock({int days = 30}) async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final cutoff = DateTime.now().add(Duration(days: days));
    final products = await db.rawQuery(
      '''
      SELECT p.id, p.name, p.quantity_cache AS qty, u.name AS unit
      FROM products p
      LEFT JOIN units u ON u.id = p.unit_id
      WHERE p.shop_id = ? AND p.deleted_at IS NULL AND p.track_stock = 1
        AND p.quantity_cache > 0
        AND EXISTS (
          SELECT 1 FROM stock_movements m
          WHERE m.product_id = p.id AND m.expiry_date IS NOT NULL
            AND m.deleted_at IS NULL
        )
    ''',
      [shopId],
    );
    final result = <ExpiringBatch>[];
    for (final p in products) {
      var remaining = (p['qty'] as num).toDouble();
      final purchases = await db.query(
        'stock_movements',
        columns: ['quantity_delta', 'batch_no', 'expiry_date'],
        where:
            "product_id = ? AND deleted_at IS NULL AND movement_type = 'purchase'",
        whereArgs: [p['id']],
        orderBy: 'created_at DESC, id DESC',
      );
      for (final m in purchases) {
        if (remaining <= stockQuantityEpsilon) break;
        final qty = (m['quantity_delta'] as num).toDouble();
        final inStock = qty < remaining ? qty : remaining;
        remaining -= inStock;
        final expiry = DateTime.tryParse(m['expiry_date']?.toString() ?? '');
        if (expiry == null || expiry.isAfter(cutoff)) continue;
        result.add(
          ExpiringBatch(
            productId: p['id'] as int,
            productName: p['name'] as String,
            unit: p['unit'] as String?,
            batchNo: m['batch_no'] as String?,
            expiry: expiry,
            quantity: inStock,
          ),
        );
      }
    }
    return result..sort((a, b) => a.expiry.compareTo(b.expiry));
  }

  /// Tracked products with stock, highest cost value first.
  Future<List<StockValueRow>> stockValuation() async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final rows = await db.rawQuery(
      '''
      SELECT p.name, c.name AS category, u.name AS unit, p.quantity_cache AS qty,
             p.purchase_price, p.selling_price
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id
      LEFT JOIN units u ON u.id = p.unit_id
      WHERE p.shop_id = ? AND p.deleted_at IS NULL AND p.track_stock = 1
        AND p.quantity_cache > 0
    ''',
      [shopId],
    );
    return [
      for (final r in rows)
        StockValueRow(
          name: r['name'] as String,
          category: r['category'] as String?,
          unit: r['unit'] as String?,
          quantity: (r['qty'] as num).toDouble(),
          costValue: roundMoney(
            ((r['qty'] as num) * (r['purchase_price'] as num)).toDouble(),
          ),
          saleValue: roundMoney(
            ((r['qty'] as num) * (r['selling_price'] as num)).toDouble(),
          ),
        ),
    ]..sort((a, b) => b.costValue.compareTo(a.costValue));
  }
}

/// Inclusive yyyy-MM-dd range on a local-time text column.
({String sql, List<Object> args}) _rangeWhere(
  String column,
  String? from,
  String? to,
) {
  final parts = <String>[];
  final args = <Object>[];
  if (from != null) {
    parts.add('AND substr($column, 1, 10) >= ?');
    args.add(from);
  }
  if (to != null) {
    parts.add('AND substr($column, 1, 10) <= ?');
    args.add(to);
  }
  return (sql: parts.join(' '), args: args);
}
