import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../main.dart';
import '../services/kpi_prefs.dart';
import 'kpi_widgets.dart';

const _donutColors = [
  Color(0xFF1B2838),
  Color(0xFFF5A623),
  Color(0xFF0D9488),
  Color(0xFF6366F1),
  Color(0xFFEC4899),
  Color(0xFF14B8A6),
];

const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  // date range: null = all time
  String? _from;
  String? _to;
  int _periodIdx = 3; // 0=7d 1=30d 2=90d 3=All

  @override
  void initState() {
    super.initState();
    // Re-render when the user toggles which KPIs are visible.
    KpiPrefs.instance.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    KpiPrefs.instance.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  void _setPeriod(int idx) {
    final now = DateTime.now();
    setState(() {
      _periodIdx = idx;
      _to = null;
      switch (idx) {
        case 0:
          _from = now
              .subtract(const Duration(days: 7))
              .toIso8601String()
              .substring(0, 10);
        case 1:
          _from = now
              .subtract(const Duration(days: 30))
              .toIso8601String()
              .substring(0, 10);
        case 2:
          _from = now
              .subtract(const Duration(days: 90))
              .toIso8601String()
              .substring(0, 10);
        default:
          _from = null;
      }
    });
  }

  Future<void> _openCustomize() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _KpiCustomizeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A key derived from the period so every tile rebuilds its Future when the
    // date range changes (each tile is otherwise lazy and caches its Future).
    final periodKey = '${_from ?? ''}_${_to ?? ''}';
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'KPI Dashboard',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Customize dashboard',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _openCustomize,
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _PeriodFilter(selected: _periodIdx, onSelect: _setPeriod),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              child: _DashboardBody(from: _from, to: _to, periodKey: periodKey),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders each category that has at least one enabled KPI, then the enabled
/// tiles within it. Hidden KPIs are never built, so their query never runs.
class _DashboardBody extends StatelessWidget {
  final String? from, to;
  final String periodKey;
  const _DashboardBody({
    required this.from,
    required this.to,
    required this.periodKey,
  });

  @override
  Widget build(BuildContext context) {
    final prefs = KpiPrefs.instance;
    final db = DatabaseHelper.instance;
    final children = <Widget>[];

    for (final category in KpiCategory.values) {
      final enabledDefs = kpiCatalogue
          .where((d) => d.category == category && prefs.isEnabled(d.id))
          .toList();
      if (enabledDefs.isEmpty) continue;
      children.add(
        KpiSectionHeader(emoji: category.emoji, title: category.label),
      );
      for (final def in enabledDefs) {
        final builder = _kpiBuilders[def.id];
        if (builder == null) continue;
        children.add(
          // Key by id + period so toggling/period changes remount cleanly.
          KeyedSubtree(
            key: ValueKey('${def.id}_$periodKey'),
            child: builder(context, db, from, to),
          ),
        );
      }
    }

    if (children.isEmpty) {
      return const _EmptyDashboard();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _EmptyDashboard extends StatelessWidget {
  const _EmptyDashboard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.dashboard_customize_rounded,
              size: 48,
              color: AppColors.inkMutedOf(context),
            ),
            const SizedBox(height: 16),
            Text(
              'No KPIs selected',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.inkOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the tune icon to choose which KPIs to show.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.inkMutedOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lazy KPI tile ────────────────────────────────────────────────────────────
//
// Owns its Future so it is created exactly once per (KPI, period) — never
// recreated inside build() — and only when the tile is actually mounted (i.e.
// the KPI is enabled). This is the core of the performance win: hidden KPIs run
// no SQL at all.
class _KpiTile<T> extends StatefulWidget {
  final String title;
  final Future<T> Function() load;
  final Widget Function(T data) builder;
  const _KpiTile({
    required this.title,
    required this.load,
    required this.builder,
  });

  @override
  State<_KpiTile<T>> createState() => _KpiTileState<T>();
}

class _KpiTileState<T> extends State<_KpiTile<T>> {
  late final Future<T> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return KpiLoadingCard(title: widget.title);
        }
        if (snap.hasError) return KpiEmpty(title: widget.title);
        return widget.builder(snap.data as T);
      },
    );
  }
}

// ── Builder registry ─────────────────────────────────────────────────────────
//
// Maps each KPI id (matching kpiCatalogue) to a widget builder. Kept in sync
// with kpi_prefs.dart by id.
typedef _KpiBuilder =
    Widget Function(BuildContext context, DatabaseHelper db, String? from,
        String? to);

final Map<String, _KpiBuilder> _kpiBuilders = {
  // ── Sales & Revenue ─────────────────────────────────────────────────────
  'total_revenue': (ctx, db, from, to) => _KpiTile<double>(
    title: 'Total Revenue',
    load: () => db.kpiTotalRevenue(from: from, to: to),
    builder: (v) => KpiCard(
      title: 'TOTAL REVENUE',
      value: fmtRupee(v),
      subtitle: 'All paid bills',
      icon: Icons.currency_rupee_rounded,
    ),
  ),
  'avg_order_value': (ctx, db, from, to) => _KpiTile<double>(
    title: 'Average Order Value',
    load: () => db.kpiAverageOrderValue(from: from, to: to),
    builder: (v) => KpiCardRow(
      left: KpiCard(
        title: 'AVG ORDER VALUE',
        value: fmtRupee(v),
        icon: Icons.receipt_rounded,
      ),
      right: _KpiTile<double>(
        title: 'Discount Rate',
        load: () => db.kpiDiscountRate(from: from, to: to),
        builder: (d) => KpiCard(
          title: 'DISCOUNT RATE',
          value: fmtPct(d),
          subtitle: 'Target < 5%',
          valueColor: d > 5 ? AppColors.error : AppColors.success,
          icon: Icons.discount_rounded,
        ),
      ),
    ),
  ),
  'revenue_trend': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Revenue Trend',
        load: () => db.kpiDailyRevenueTrend(from: from, to: to),
        builder: (rows) {
          final data = rows
              .map(
                (r) => (
                  label: r['day'] as String,
                  value: (r['revenue'] as num).toDouble(),
                ),
              )
              .toList();
          return KpiLineChart(title: 'Daily Revenue Trend', data: data);
        },
      ),
  'payment_method': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Collections by Payment Method',
        load: () => db.kpiRevenueByPaymentMethod(from: from, to: to),
        builder: (rows) {
          final segs = rows
              .asMap()
              .entries
              .map(
                (e) => (
                  label: _fmtMethod(e.value['method'] as String),
                  value: (e.value['total'] as num).toDouble(),
                  color: _donutColors[e.key % _donutColors.length],
                ),
              )
              .toList();
          return KpiDonut(
            title: 'Collections by Payment Method',
            segments: segs,
          );
        },
      ),
  'unpaid_bills': (ctx, db, from, to) =>
      _KpiTile<Map<String, dynamic>>(
        title: 'Unpaid Bills',
        load: () => db.kpiUnpaidBillsValue(),
        builder: (m) {
          final count = m['count'] as int;
          final total = m['total'] as double;
          return KpiCard(
            title: 'UNPAID BILLS',
            value: fmtRupee(total),
            subtitle: '$count unpaid bill${count == 1 ? '' : 's'} outstanding',
            valueColor: count > 0 ? AppColors.error : AppColors.success,
            icon: Icons.pending_actions_rounded,
          );
        },
      ),
  'revenue_by_category': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Revenue by Category',
        load: () => db.kpiRevenueByCategory(from: from, to: to),
        builder: (rows) {
          final items = rows
              .map(
                (r) => (
                  label: r['category'] as String,
                  value: (r['revenue'] as num).toDouble(),
                ),
              )
              .toList();
          return KpiHorizBarList(title: 'Revenue by Category', items: items);
        },
      ),
  'busy_day': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Busy Day of Week',
        load: () => db.kpiBusyDayOfWeek(from: from, to: to),
        builder: (rows) {
          final data = List.generate(7, (i) {
            final row = rows.firstWhere(
              (r) => (r['dow'] as int) == i,
              orElse: () => {'dow': i, 'bills': 0, 'revenue': 0.0},
            );
            return (
              label: _days[i],
              value: (row['revenue'] as num).toDouble(),
            );
          });
          return KpiBarChart(
            title: 'Busy Day of Week (Revenue)',
            data: data,
            isRupee: true,
            barColor: AppColors.amber,
          );
        },
      ),
  'gross_profit': (ctx, db, from, to) => _KpiTile<double>(
    title: 'Gross Profit',
    load: () => db.kpiGrossProfit(from: from, to: to),
    builder: (gp) => _KpiTile<double>(
      title: 'Gross Margin',
      load: () => db.kpiGrossMarginPercent(from: from, to: to),
      builder: (margin) => KpiCardRow(
        left: KpiCard(
          title: 'GROSS PROFIT',
          value: fmtRupee(gp),
          valueColor: gp >= 0 ? AppColors.success : AppColors.error,
          icon: Icons.trending_up_rounded,
        ),
        right: KpiCard(
          title: 'GROSS MARGIN',
          value: fmtPct(margin),
          subtitle: 'Target > 20%',
          valueColor: margin >= 20 ? AppColors.success : AppColors.amber,
        ),
      ),
    ),
  ),
  'net_profit': (ctx, db, from, to) => _KpiTile<double>(
    title: 'Commission & Net Profit',
    load: () => db.kpiTotalCommissionPaid(from: from, to: to),
    builder: (comm) => _KpiTile<double>(
      title: 'Net Profit',
      load: () => db.kpiNetProfitAfterCommission(from: from, to: to),
      builder: (net) => KpiCardRow(
        left: KpiCard(
          title: 'COMMISSION PAID',
          value: fmtRupee(comm),
          icon: Icons.payments_rounded,
        ),
        right: KpiCard(
          title: 'NET PROFIT',
          value: fmtRupee(net),
          valueColor: net >= 0 ? AppColors.success : AppColors.error,
        ),
      ),
    ),
  ),
  'profit_trend': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Profit Trend',
        load: () => db.kpiMonthlyProfitTrend(from: from, to: to),
        builder: (rows) {
          final data = rows
              .map(
                (r) => (
                  label: r['month'] as String,
                  value: (r['profit'] as num).toDouble(),
                ),
              )
              .toList();
          return KpiLineChart(title: 'Monthly Profit Trend', data: data);
        },
      ),
  'gst_collected': (ctx, db, from, to) => _KpiTile<double>(
    title: 'GST Collected',
    load: () => db.kpiGstCollected(from: from, to: to),
    builder: (v) => KpiCard(
      title: 'GST COLLECTED',
      value: fmtRupee(v),
      subtitle: 'Matches GST returns',
      icon: Icons.account_balance_rounded,
    ),
  ),
  'profit_by_category': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Profit by Category',
        load: () => db.kpiProfitByCategory(from: from, to: to),
        builder: (rows) {
          final items = rows
              .map(
                (r) => (
                  label: r['category'] as String,
                  value: (r['profit'] as num).toDouble(),
                ),
              )
              .toList();
          return KpiHorizBarList(
            title: 'Profit by Category',
            items: items,
            barColor: AppColors.success,
          );
        },
      ),

  // ── Products & Inventory ────────────────────────────────────────────────
  'top_products_revenue': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Top Products by Revenue',
        load: () => db.kpiTop10ProductsByRevenue(from: from, to: to),
        builder: (rows) {
          final items = rows
              .map(
                (r) => (
                  label: r['name'] as String,
                  value: (r['revenue'] as num).toDouble(),
                ),
              )
              .toList();
          return KpiHorizBarList(
            title: 'Top 10 Products by Revenue',
            items: items,
          );
        },
      ),
  'top_products_quantity': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Top Products by Quantity',
        load: () => db.kpiTop10ProductsByQuantity(from: from, to: to),
        builder: (rows) {
          final items = rows
              .map(
                (r) => (
                  label: r['name'] as String,
                  value: (r['units_sold'] as num).toDouble(),
                ),
              )
              .toList();
          return KpiHorizBarList(
            title: 'Top 10 by Units Sold',
            items: items,
            isRupee: false,
            barColor: AppColors.brandOf(ctx),
          );
        },
      ),
  'top_profit_items': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Top Profit Items',
        load: () => db.kpiTopProfitItems(from: from, to: to),
        builder: (rows) {
          final items = rows
              .map(
                (r) => (
                  label: r['name'] as String,
                  value: (r['profit'] as num).toDouble(),
                ),
              )
              .toList();
          return KpiHorizBarList(
            title: 'Top 10 — Highest Profit Items',
            items: items,
          );
        },
      ),
  'low_margin_items': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Low Margin Items',
        load: () => db.kpiTopNonProfitItems(from: from, to: to),
        builder: (rows) {
          final items = rows
              .map(
                (r) => (
                  label: r['name'] as String,
                  value: (r['profit'] as num).toDouble(),
                ),
              )
              .toList();
          return KpiHorizBarList(
            title: 'Bottom 10 — Lowest Margin Items',
            items: items,
            barColor: AppColors.error,
          );
        },
      ),
  'inventory_value': (ctx, db, from, to) => _KpiTile<double>(
    title: 'Inventory Value',
    load: () => db.kpiTotalInventoryValue(),
    builder: (inv) => _KpiTile<int>(
      title: 'Out of Stock',
      load: () => db.kpiOutOfStockCount(),
      builder: (oos) => KpiCardRow(
        left: KpiCard(
          title: 'INVENTORY VALUE',
          value: fmtRupee(inv),
          icon: Icons.inventory_2_rounded,
        ),
        right: KpiCard(
          title: 'OUT OF STOCK',
          value: '$oos',
          subtitle: 'products',
          valueColor: oos > 0 ? AppColors.error : AppColors.success,
          icon: Icons.warning_rounded,
        ),
      ),
    ),
  ),
  'low_stock': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Low Stock',
        load: () => db.kpiLowStockProducts(),
        builder: (rows) => KpiDataTableCard(
          title: 'Low Stock Products (< 5 units)',
          columns: const ['Product', 'Qty'],
          rows: rows
              .map(
                (r) => [
                  r['name'] as String,
                  fmtNum((r['quantity'] as num).toDouble()),
                ],
              )
              .toList(),
          badgeCount: rows.length,
          badgeColor: AppColors.amber,
        ),
      ),
  'inventory_turnover': (ctx, db, from, to) => _KpiTile<double>(
    title: 'Inventory Turnover',
    load: () => db.kpiInventoryTurnoverRate(),
    builder: (v) => KpiCard(
      title: 'INVENTORY TURNOVER RATE',
      value: '${v.toStringAsFixed(2)}×',
      subtitle: 'Target > 4× per year',
      valueColor: v >= 4 ? AppColors.success : AppColors.amber,
      icon: Icons.loop_rounded,
    ),
  ),
  'dead_stock': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Dead Stock',
        load: () => db.kpiDeadStock(),
        builder: (rows) => KpiDataTableCard(
          title: 'Dead Stock (No sales in 30 days)',
          columns: const ['Product', 'Qty'],
          rows: rows
              .map(
                (r) => [
                  r['name'] as String,
                  fmtNum((r['quantity'] as num).toDouble()),
                ],
              )
              .toList(),
          badgeCount: rows.length,
        ),
      ),
  'slow_moving': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Slow Moving Products',
        load: () => db.kpiSlowMovingProducts(),
        builder: (rows) => KpiDataTableCard(
          title: 'Slow Moving Products (< 3 units / 30 days)',
          columns: const ['Product', 'Qty Sold'],
          rows: rows
              .map(
                (r) => [
                  r['name'] as String,
                  fmtNum((r['qty_sold'] as num).toDouble()),
                ],
              )
              .toList(),
          badgeCount: rows.length,
        ),
      ),
  'top_suppliers': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Top Suppliers',
        load: () => db.kpiTopSuppliers(),
        builder: (rows) {
          final items = rows
              .map(
                (r) => (
                  label: r['name'] as String,
                  value: (r['value_received'] as num).toDouble(),
                ),
              )
              .toList();
          return KpiHorizBarList(
            title: 'Top Suppliers by Value Received',
            items: items,
          );
        },
      ),
  'new_products': (ctx, db, from, to) => _KpiTile<int>(
    title: 'New Products',
    load: () => db.kpiNewProductsAdded(),
    builder: (v) => _KpiTile<double>(
      title: 'Price Compliance',
      load: () => db.kpiProductPriceCompliance(from: from, to: to),
      builder: (pct) => KpiCardRow(
        left: KpiCard(
          title: 'NEW PRODUCTS ADDED',
          value: '$v',
          icon: Icons.add_box_rounded,
        ),
        right: KpiGaugeCard(
          title: 'Direct Pricing Rate',
          value: pct,
          target: '< 15%',
          higherIsBetter: false,
        ),
      ),
    ),
  ),

  // ── Operations & Customers ──────────────────────────────────────────────
  'active_customers': (ctx, db, from, to) => _KpiTile<int>(
    title: 'Active Customers',
    load: () => db.kpiTotalActiveCustomers(),
    builder: (active) => _KpiTile<int>(
      title: 'New Customers',
      load: () => db.kpiNewCustomersAcquired(),
      builder: (newC) => KpiCardRow(
        left: KpiCard(
          title: 'ACTIVE CUSTOMERS',
          value: '$active',
          icon: Icons.people_rounded,
        ),
        right: KpiCard(
          title: 'NEW CUSTOMERS',
          value: '$newC',
          subtitle: 'All time',
          icon: Icons.person_add_rounded,
        ),
      ),
    ),
  ),
  'top_customers': (ctx, db, from, to) =>
      _KpiTile<List<Map<String, dynamic>>>(
        title: 'Top Customers',
        load: () => db.kpiTop10CustomersByRevenue(),
        builder: (rows) {
          final items = rows
              .map(
                (r) => (
                  label: r['name'] as String,
                  value: (r['total_purchase_amount'] as num).toDouble(),
                ),
              )
              .toList();
          return KpiHorizBarList(
            title: 'Top 10 Customers by Revenue',
            items: items,
          );
        },
      ),
  'repeat_rate': (ctx, db, from, to) => _KpiTile<double>(
    title: 'Repeat Rate',
    load: () => db.kpiRepeatCustomerRate(),
    builder: (v) => KpiGaugeCard(
      title: 'Repeat Customer Rate',
      value: v,
      target: '> 30%',
    ),
  ),
  'customer_value': (ctx, db, from, to) => _KpiTile<double>(
    title: 'Avg Lifetime Value',
    load: () => db.kpiAvgCustomerLifetimeValue(),
    builder: (clv) => _KpiTile<double>(
      title: 'Avg Bills',
      load: () => db.kpiAvgBillsPerCustomer(),
      builder: (avgB) => KpiCardRow(
        left: KpiCard(
          title: 'AVG CUSTOMER VALUE',
          value: fmtRupee(clv),
          icon: Icons.star_rounded,
        ),
        right: KpiCard(
          title: 'AVG BILLS / CUSTOMER',
          value: fmtNum(avgB),
          subtitle: 'Target > 2',
          valueColor: avgB >= 2 ? AppColors.success : AppColors.amber,
        ),
      ),
    ),
  ),
  'lapsed_customers': (ctx, db, from, to) => _KpiTile<int>(
    title: 'Lapsed Customers',
    load: () => db.kpiLapsedCustomers(),
    builder: (v) => KpiCard(
      title: 'LAPSED CUSTOMERS',
      value: '$v',
      subtitle: 'No purchase in 60+ days',
      valueColor: v > 0 ? AppColors.error : AppColors.success,
      icon: Icons.person_off_rounded,
    ),
  ),
  'bills_per_day': (ctx, db, from, to) => _KpiTile<double>(
    title: 'Bills Per Day',
    load: () => db.kpiBillsPerDay(from: from, to: to),
    builder: (bpd) => _KpiTile<double>(
      title: 'Avg Items',
      load: () => db.kpiAvgItemsPerBill(from: from, to: to),
      builder: (avg) => KpiCardRow(
        left: KpiCard(
          title: 'BILLS PER DAY',
          value: fmtNum(bpd),
          icon: Icons.receipt_long_rounded,
        ),
        right: KpiCard(
          title: 'AVG ITEMS / BILL',
          value: fmtNum(avg),
          subtitle: 'Target > 3',
          valueColor: avg >= 3 ? AppColors.success : AppColors.amber,
        ),
      ),
    ),
  ),
  'void_rate': (ctx, db, from, to) => _KpiTile<double>(
    title: 'Bill Void Rate',
    load: () => db.kpiBillVoidRate(),
    builder: (v) => KpiGaugeCard(
      title: 'Bill Void Rate',
      value: v,
      target: '< 1%',
      higherIsBetter: false,
    ),
  ),
  'devices_coverage': (ctx, db, from, to) => _KpiTile<int>(
    title: 'Devices',
    load: () => db.kpiMultiDeviceActivity(from: from, to: to),
    builder: (devices) => _KpiTile<double>(
      title: 'Catalog Coverage',
      load: () => db.kpiCatalogCoverage(),
      builder: (cov) => KpiCardRow(
        left: KpiCard(
          title: 'ACTIVE DEVICES',
          value: '$devices',
          icon: Icons.devices_rounded,
        ),
        right: KpiGaugeCard(
          title: 'Catalog Coverage',
          value: cov,
          target: '> 95%',
        ),
      ),
    ),
  ),
  'stock_adjustments': (ctx, db, from, to) => _KpiTile<int>(
    title: 'Stock Adjustments',
    load: () => db.kpiStockAdjustmentFrequency(),
    builder: (v) => KpiCard(
      title: 'STOCK ADJUSTMENTS',
      value: '$v',
      subtitle: 'Manual corrections (all time)',
      icon: Icons.tune_rounded,
    ),
  ),
};

// ── Period Filter ────────────────────────────────────────────────────────────
class _PeriodFilter extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  const _PeriodFilter({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    const labels = ['7 Days', '30 Days', '90 Days', 'All Time'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.brandOf(context)
                      : AppColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                        ? AppColors.brandOf(context)
                        : AppColors.borderOf(context),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? (AppColors.isDark(context)
                              ? Colors.black
                              : Colors.white)
                        : AppColors.inkMutedOf(context),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Customize sheet ──────────────────────────────────────────────────────────
class _KpiCustomizeSheet extends StatefulWidget {
  const _KpiCustomizeSheet();

  @override
  State<_KpiCustomizeSheet> createState() => _KpiCustomizeSheetState();
}

class _KpiCustomizeSheetState extends State<_KpiCustomizeSheet> {
  @override
  Widget build(BuildContext context) {
    final prefs = KpiPrefs.instance;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Customize Dashboard',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.inkOf(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Fewer KPIs = faster dashboard. '
                            'Hidden KPIs are not calculated.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.inkMutedOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await prefs.resetToDefaults();
                        if (mounted) setState(() {});
                      },
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    for (final category in KpiCategory.values)
                      ..._categorySection(context, prefs, category),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _categorySection(
    BuildContext context,
    KpiPrefs prefs,
    KpiCategory category,
  ) {
    final defs = kpiCatalogue.where((d) => d.category == category).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Row(
          children: [
            Text(category.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.inkOf(context),
              ),
            ),
          ],
        ),
      ),
      for (final def in defs)
        CheckboxListTile(
          dense: true,
          value: prefs.isEnabled(def.id),
          onChanged: (v) async {
            await prefs.setEnabled(def.id, v ?? false);
            if (mounted) setState(() {});
          },
          activeColor: AppColors.brandOf(context),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            def.title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.inkOf(context),
            ),
          ),
          subtitle: def.cost == KpiCost.heavy
              ? Text(
                  'Heavier to calculate on large data',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.amber,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : null,
        ),
    ];
  }
}

String _fmtMethod(String m) {
  switch (m.toLowerCase()) {
    case 'cash':
      return 'Cash';
    case 'upi':
      return 'UPI';
    case 'card':
      return 'Card';
    case 'online':
      return 'Online';
    default:
      return m[0].toUpperCase() + m.substring(1);
  }
}
