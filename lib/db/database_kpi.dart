part of 'database_helper.dart';

// ── KPI Query Mixin ──
// All queries run against local SQLite (offline-first).
// Date strings stored as ISO-8601 TEXT (e.g. "2024-03-15T10:30:00.000").
// SQLite date functions use substr() on that prefix.

mixin DatabaseKpi {
  Future<Database> get database;

  // ──────────────────────────────────────────
  // 💰 SALES & REVENUE
  // ──────────────────────────────────────────

  Future<double> kpiTotalRevenue({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('b.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) AS v
      FROM bills b
      WHERE b.deleted_at IS NULL AND b.is_paid = 1 $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> kpiDailyRevenueTrend({
    String? from,
    String? to,
  }) async {
    final db = await database;
    final where = _dateWhere('b.created_at', from, to);
    return db.rawQuery('''
      SELECT substr(b.created_at, 1, 10) AS day,
             COALESCE(SUM(b.total_amount), 0) AS revenue
      FROM bills b
      WHERE b.deleted_at IS NULL AND b.is_paid = 1 $where
      GROUP BY day ORDER BY day ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> kpiRevenueByPaymentMethod({
    String? from,
    String? to,
  }) async {
    final db = await database;
    final where = _dateWhere('b.created_at', from, to);
    return db.rawQuery('''
      SELECT COALESCE(b.payment_method, 'cash') AS method,
             COALESCE(SUM(b.total_amount), 0) AS total
      FROM bills b
      WHERE b.deleted_at IS NULL $where
      GROUP BY method ORDER BY total DESC
    ''');
  }

  Future<double> kpiAverageOrderValue({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('b.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) * 1.0
           / NULLIF(COUNT(*), 0) AS v
      FROM bills b
      WHERE b.deleted_at IS NULL AND b.is_paid = 1 $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<double> kpiDiscountRate({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('b.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT ROUND(COALESCE(SUM(discount_amount), 0) * 100.0
           / NULLIF(SUM(subtotal_amount), 0), 2) AS v
      FROM bills b
      WHERE b.deleted_at IS NULL $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<Map<String, dynamic>> kpiUnpaidBillsValue() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS cnt,
             COALESCE(SUM(total_amount), 0) AS total
      FROM bills
      WHERE deleted_at IS NULL AND is_paid = 0
    ''');
    return {
      'count': (r.first['cnt'] as num?)?.toInt() ?? 0,
      'total': (r.first['total'] as num?)?.toDouble() ?? 0.0,
    };
  }

  Future<List<Map<String, dynamic>>> kpiRevenueByCategory({
    String? from,
    String? to,
  }) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    return db.rawQuery('''
      SELECT COALESCE(c.name, 'Uncategorised') AS category,
             COALESCE(SUM(bi.subtotal), 0) AS revenue
      FROM bill_items bi
      LEFT JOIN products p ON bi.product_id = p.id
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE bi.deleted_at IS NULL $where
      GROUP BY category ORDER BY revenue DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> kpiBusyDayOfWeek({
    String? from,
    String? to,
  }) async {
    final db = await database;
    final where = _dateWhere('b.created_at', from, to);
    // SQLite: strftime('%w', date) => 0=Sunday, 1=Monday ... 6=Saturday
    return db.rawQuery('''
      SELECT CAST(strftime('%w', substr(b.created_at, 1, 10)) AS INTEGER) AS dow,
             COUNT(*) AS bills,
             COALESCE(SUM(b.total_amount), 0) AS revenue
      FROM bills b
      WHERE b.deleted_at IS NULL $where
      GROUP BY dow ORDER BY dow ASC
    ''');
  }

  // ──────────────────────────────────────────
  // 📈 PROFITABILITY
  // ──────────────────────────────────────────

  Future<double> kpiGrossProfit({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT ROUND(COALESCE(SUM(bi.profit_snapshot * bi.quantity), 0), 2) AS v
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> kpiMonthlyProfitTrend({
    String? from,
    String? to,
  }) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    return db.rawQuery('''
      SELECT substr(bi.created_at, 1, 7) AS month,
             ROUND(COALESCE(SUM(bi.profit_snapshot * bi.quantity), 0), 2) AS profit,
             ROUND(COALESCE(SUM(bi.commission_snapshot * bi.quantity), 0), 2) AS commission
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
      GROUP BY month ORDER BY month ASC
    ''');
  }

  Future<double> kpiGrossMarginPercent({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT ROUND(
        COALESCE(SUM(bi.profit_snapshot * bi.quantity), 0) * 100.0
        / NULLIF(SUM(bi.subtotal), 0), 2) AS v
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<double> kpiTotalCommissionPaid({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT ROUND(COALESCE(SUM(bi.commission_snapshot * bi.quantity), 0), 2) AS v
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<double> kpiNetProfitAfterCommission({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT ROUND(
        COALESCE(SUM(bi.profit_snapshot * bi.quantity), 0)
        - COALESCE(SUM(bi.commission_snapshot * bi.quantity), 0), 2) AS v
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> kpiTopProfitItems({
    String? from,
    String? to,
    int limit = 10,
  }) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    return db.rawQuery('''
      SELECT bi.product_name AS name,
             ROUND(COALESCE(SUM(bi.profit_snapshot * bi.quantity), 0), 2) AS profit
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
      GROUP BY bi.product_id, bi.product_name
      ORDER BY profit DESC LIMIT $limit
    ''');
  }

  Future<List<Map<String, dynamic>>> kpiTopNonProfitItems({
    String? from,
    String? to,
    int limit = 10,
  }) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    return db.rawQuery('''
      SELECT bi.product_name AS name,
             ROUND(COALESCE(SUM(bi.profit_snapshot * bi.quantity), 0), 2) AS profit,
             ROUND(COALESCE(SUM(bi.profit_snapshot * bi.quantity), 0) * 100.0
                   / NULLIF(SUM(bi.subtotal), 0), 2) AS margin_pct
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
      GROUP BY bi.product_id, bi.product_name
      HAVING SUM(bi.quantity) > 0
      ORDER BY margin_pct ASC LIMIT $limit
    ''');
  }

  Future<List<Map<String, dynamic>>> kpiProfitByCategory({
    String? from,
    String? to,
  }) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    return db.rawQuery('''
      SELECT COALESCE(c.name, 'Uncategorised') AS category,
             ROUND(COALESCE(SUM(bi.profit_snapshot * bi.quantity), 0), 2) AS profit
      FROM bill_items bi
      LEFT JOIN products p ON bi.product_id = p.id
      LEFT JOIN categories c ON p.category_id = c.id
      WHERE bi.deleted_at IS NULL $where
      GROUP BY category ORDER BY profit DESC
    ''');
  }

  Future<double> kpiGstCollected({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT ROUND(COALESCE(SUM(bi.gst_snapshot * bi.quantity), 0), 2) AS v
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  // ──────────────────────────────────────────
  // 📦 INVENTORY
  // ──────────────────────────────────────────

  Future<double> kpiTotalInventoryValue() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT ROUND(COALESCE(SUM(quantity_cache * purchase_price), 0), 2) AS v
      FROM products
      WHERE deleted_at IS NULL
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<int> kpiOutOfStockCount() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM products
      WHERE deleted_at IS NULL AND quantity_cache <= 0
    ''');
    return (r.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, dynamic>>> kpiLowStockProducts({
    double threshold = 5,
  }) async {
    final db = await database;
    return db.rawQuery('''
      SELECT name, quantity_cache AS quantity
      FROM products
      WHERE deleted_at IS NULL
        AND quantity_cache > 0
        AND quantity_cache <= ?
      ORDER BY quantity_cache ASC
    ''', [threshold]);
  }

  Future<double> kpiInventoryTurnoverRate({String? from, String? to}) async {
    // Units sold / avg quantity on hand
    final db = await database;
    final where = _dateWhere('sm.created_at', from, to);
    final soldR = await db.rawQuery('''
      SELECT COALESCE(SUM(ABS(sm.quantity_delta)), 0) AS sold
      FROM stock_movements sm
      WHERE sm.deleted_at IS NULL AND sm.movement_type = 'sale' $where
    ''');
    final avgR = await db.rawQuery('''
      SELECT COALESCE(AVG(quantity_cache), 0) AS avg_qty
      FROM products WHERE deleted_at IS NULL
    ''');
    final sold = (soldR.first['sold'] as num?)?.toDouble() ?? 0;
    final avg = (avgR.first['avg_qty'] as num?)?.toDouble() ?? 0;
    if (avg == 0) return 0;
    return sold / avg;
  }

  Future<List<Map<String, dynamic>>> kpiDeadStock({int days = 30}) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    return db.rawQuery('''
      SELECT p.name, p.quantity_cache AS quantity
      FROM products p
      WHERE p.deleted_at IS NULL
        AND p.quantity_cache > 0
        AND p.id NOT IN (
          SELECT DISTINCT product_id FROM bill_items
          WHERE deleted_at IS NULL
            AND product_id IS NOT NULL
            AND substr(created_at, 1, 10) >= ?
        )
      ORDER BY p.quantity_cache DESC
    ''', [cutoff]);
  }

  Future<List<Map<String, dynamic>>> kpiTopSuppliers({
    String? from,
    String? to,
    int limit = 10,
  }) async {
    final db = await database;
    final where = _dateWhere('sm.created_at', from, to);
    return db.rawQuery('''
      SELECT COALESCE(s.name, 'Unknown') AS name,
             ROUND(COALESCE(SUM(ABS(sm.quantity_delta)), 0), 2) AS units_received,
             ROUND(COALESCE(SUM(ABS(sm.quantity_delta) * COALESCE(sm.unit_cost, 0)), 0), 2) AS value_received
      FROM stock_movements sm
      LEFT JOIN suppliers s ON sm.source_id = s.id
      WHERE sm.deleted_at IS NULL AND sm.movement_type = 'purchase' $where
        AND sm.source_id IS NOT NULL
      GROUP BY sm.source_id, s.name
      ORDER BY value_received DESC LIMIT $limit
    ''');
  }

  Future<int> kpiStockAdjustmentFrequency({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('sm.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM stock_movements sm
      WHERE sm.deleted_at IS NULL AND sm.movement_type = 'adjustment' $where
    ''');
    return (r.first['cnt'] as num?)?.toInt() ?? 0;
  }

  // ──────────────────────────────────────────
  // 👥 CUSTOMERS
  // ──────────────────────────────────────────

  Future<int> kpiTotalActiveCustomers() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM customers
      WHERE deleted_at IS NULL AND bill_count > 0
    ''');
    return (r.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<int> kpiNewCustomersAcquired({String? from, String? to}) async {
    final db = await database;
    String clause = 'WHERE deleted_at IS NULL';
    if (from != null) clause += " AND substr(created_at,1,10) >= '$from'";
    if (to != null) clause += " AND substr(created_at,1,10) <= '$to'";
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM customers $clause',
    );
    return (r.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<double> kpiRepeatCustomerRate() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT
        ROUND(
          CAST(SUM(CASE WHEN bill_count > 1 THEN 1 ELSE 0 END) AS REAL)
          / NULLIF(SUM(CASE WHEN bill_count > 0 THEN 1 ELSE 0 END), 0) * 100, 2
        ) AS v
      FROM customers
      WHERE deleted_at IS NULL
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<double> kpiAvgCustomerLifetimeValue() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT ROUND(COALESCE(AVG(total_purchase_amount), 0), 2) AS v
      FROM customers
      WHERE deleted_at IS NULL AND bill_count > 0
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, dynamic>>> kpiTop10CustomersByRevenue() async {
    final db = await database;
    return db.rawQuery('''
      SELECT name, phone, total_purchase_amount, bill_count
      FROM customers
      WHERE deleted_at IS NULL
      ORDER BY total_purchase_amount DESC LIMIT 10
    ''');
  }

  Future<int> kpiLapsedCustomers({int days = 60}) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    final r = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM customers
      WHERE deleted_at IS NULL
        AND bill_count > 0
        AND last_purchase_at IS NOT NULL
        AND substr(last_purchase_at, 1, 10) < ?
    ''', [cutoff]);
    return (r.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<double> kpiAvgBillsPerCustomer() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT ROUND(COALESCE(AVG(CAST(bill_count AS REAL)), 0), 2) AS v
      FROM customers
      WHERE deleted_at IS NULL AND bill_count > 0
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  // ──────────────────────────────────────────
  // 🛍 PRODUCTS
  // ──────────────────────────────────────────

  Future<List<Map<String, dynamic>>> kpiTop10ProductsByRevenue({
    String? from,
    String? to,
  }) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    return db.rawQuery('''
      SELECT bi.product_name AS name,
             ROUND(COALESCE(SUM(bi.subtotal), 0), 2) AS revenue,
             ROUND(COALESCE(SUM(bi.quantity), 0), 2) AS units
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
      GROUP BY bi.product_id, bi.product_name
      ORDER BY revenue DESC LIMIT 10
    ''');
  }

  Future<List<Map<String, dynamic>>> kpiTop10ProductsByQuantity({
    String? from,
    String? to,
  }) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    return db.rawQuery('''
      SELECT bi.product_name AS name,
             ROUND(COALESCE(SUM(bi.quantity), 0), 2) AS units_sold
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
      GROUP BY bi.product_id, bi.product_name
      ORDER BY units_sold DESC LIMIT 10
    ''');
  }

  Future<List<Map<String, dynamic>>> kpiSlowMovingProducts({
    String? from,
    String? to,
    int days = 30,
    double threshold = 3,
  }) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    return db.rawQuery('''
      SELECT bi.product_name AS name,
             ROUND(COALESCE(SUM(bi.quantity), 0), 2) AS qty_sold
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL
        AND substr(bi.created_at, 1, 10) >= ?
      GROUP BY bi.product_id, bi.product_name
      HAVING qty_sold < ?
      ORDER BY qty_sold ASC
    ''', [cutoff, threshold]);
  }

  Future<int> kpiNewProductsAdded({String? from, String? to}) async {
    final db = await database;
    String clause = 'WHERE deleted_at IS NULL';
    if (from != null) clause += " AND substr(created_at,1,10) >= '$from'";
    if (to != null) clause += " AND substr(created_at,1,10) <= '$to'";
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM products $clause',
    );
    return (r.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<double> kpiProductPriceCompliance({
    String? from,
    String? to,
  }) async {
    final db = await database;
    final where = _dateWhere('bi.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT ROUND(
        CAST(SUM(CASE WHEN bi.was_direct_price = 1 THEN 1 ELSE 0 END) AS REAL)
        / NULLIF(COUNT(*), 0) * 100, 2) AS v
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  // ──────────────────────────────────────────
  // ⚙ OPERATIONS
  // ──────────────────────────────────────────

  Future<double> kpiBillsPerDay({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('b.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT CAST(COUNT(*) AS REAL)
           / NULLIF(COUNT(DISTINCT substr(b.created_at, 1, 10)), 0) AS v
      FROM bills b
      WHERE b.deleted_at IS NULL $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<double> kpiAvgItemsPerBill({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('b.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT ROUND(COALESCE(AVG(CAST(b.item_count AS REAL)), 0), 2) AS v
      FROM bills b
      WHERE b.deleted_at IS NULL $where
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<double> kpiBillVoidRate() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT ROUND(
        CAST(SUM(CASE WHEN deleted_at IS NOT NULL THEN 1 ELSE 0 END) AS REAL)
        / NULLIF(COUNT(*), 0) * 100, 2) AS v
      FROM bills
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  Future<int> kpiMultiDeviceActivity({String? from, String? to}) async {
    final db = await database;
    final where = _dateWhere('b.created_at', from, to);
    final r = await db.rawQuery('''
      SELECT COUNT(DISTINCT b.device_id) AS cnt
      FROM bills b
      WHERE b.deleted_at IS NULL AND b.device_id IS NOT NULL $where
    ''');
    return (r.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<double> kpiCatalogCoverage() async {
    final db = await database;
    final r = await db.rawQuery('''
      SELECT ROUND(
        CAST(SUM(CASE WHEN category_id IS NOT NULL THEN 1 ELSE 0 END) AS REAL)
        / NULLIF(COUNT(*), 0) * 100, 2) AS v
      FROM products
      WHERE deleted_at IS NULL
    ''');
    return (r.first['v'] as num?)?.toDouble() ?? 0;
  }

  // ──────────────────────────────────────────
  // Helper
  // ──────────────────────────────────────────

  String _dateWhere(String col, String? from, String? to) {
    var clause = '';
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (from != null && dateRegex.hasMatch(from)) clause += " AND substr($col,1,10) >= '$from'";
    if (to != null && dateRegex.hasMatch(to)) clause += " AND substr($col,1,10) <= '$to'";
    return clause;
  }
}
