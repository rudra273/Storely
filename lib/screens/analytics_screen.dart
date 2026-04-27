import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../main.dart';
import 'kpi_widgets.dart';

const _donutColors = [
  Color(0xFF1B2838), Color(0xFFF5A623), Color(0xFF0D9488),
  Color(0xFF6366F1), Color(0xFFEC4899), Color(0xFF14B8A6),
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

  void _setPeriod(int idx) {
    final now = DateTime.now();
    setState(() {
      _periodIdx = idx;
      _to = null;
      switch (idx) {
        case 0:
          _from = now.subtract(const Duration(days: 7)).toIso8601String().substring(0, 10);
        case 1:
          _from = now.subtract(const Duration(days: 30)).toIso8601String().substring(0, 10);
        case 2:
          _from = now.subtract(const Duration(days: 90)).toIso8601String().substring(0, 10);
        default:
          _from = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text('KPI Dashboard', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _PeriodFilter(selected: _periodIdx, onSelect: _setPeriod)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const KpiSectionHeader(emoji: '💰', title: 'Sales & Revenue'),
                  _SalesSection(from: _from, to: _to),
                  const KpiSectionHeader(emoji: '📈', title: 'Profitability'),
                  _ProfitSection(from: _from, to: _to),
                  const KpiSectionHeader(emoji: '📦', title: 'Inventory'),
                  const _InventorySection(),
                  const KpiSectionHeader(emoji: '👥', title: 'Customers'),
                  const _CustomersSection(),
                  const KpiSectionHeader(emoji: '🛍', title: 'Products'),
                  _ProductsSection(from: _from, to: _to),
                  const KpiSectionHeader(emoji: '⚙', title: 'Operations'),
                  _OperationsSection(from: _from, to: _to),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: active ? AppColors.navy : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? AppColors.navy : AppColors.creamDark,
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppColors.textMuted,
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

// ── Helper: FutureBuilder wrapper ────────────────────────────────────────────
Widget _futureKpi<T>(String title, Future<T> future, Widget Function(T) builder) {
  return FutureBuilder<T>(
    future: future,
    builder: (_, snap) {
      if (snap.connectionState != ConnectionState.done) return KpiLoadingCard(title: title);
      if (snap.hasError) return KpiEmpty(title: title);
      return builder(snap.data as T);
    },
  );
}

// ── 💰 Sales & Revenue ───────────────────────────────────────────────────────
class _SalesSection extends StatelessWidget {
  final String? from, to;
  const _SalesSection({this.from, this.to});

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Total Revenue + AOV
        _futureKpi('Total Revenue', db.kpiTotalRevenue(from: from, to: to), (v) {
          return KpiCard(
            title: 'TOTAL REVENUE',
            value: fmtRupee(v),
            subtitle: 'All paid bills',
            icon: Icons.currency_rupee_rounded,
          );
        }),
        _futureKpi('Average Order Value', db.kpiAverageOrderValue(from: from, to: to), (v) {
          return KpiCardRow(
            left: KpiCard(title: 'AVG ORDER VALUE', value: fmtRupee(v), icon: Icons.receipt_rounded),
            right: _futureAovRight(db, from, to),
          );
        }),
        // Revenue trend line
        _futureKpi('Revenue Trend', db.kpiDailyRevenueTrend(from: from, to: to), (rows) {
          final data = rows.map((r) => (label: r['day'] as String, value: (r['revenue'] as num).toDouble())).toList();
          return KpiLineChart(title: 'Daily Revenue Trend', data: data);
        }),
        // Payment method donut
        _futureKpi('Revenue by Payment Method', db.kpiRevenueByPaymentMethod(from: from, to: to), (rows) {
          final segs = rows.asMap().entries.map((e) => (
            label: _fmtMethod(e.value['method'] as String),
            value: (e.value['total'] as num).toDouble(),
            color: _donutColors[e.key % _donutColors.length],
          )).toList();
          return KpiDonut(title: 'Revenue by Payment Method', segments: segs);
        }),
        // Discount rate
        _futureKpi('Discount Rate', db.kpiDiscountRate(from: from, to: to), (v) {
          return KpiGaugeCard(
            title: 'Discount Rate',
            value: v,
            target: '< 5%',
            higherIsBetter: false,
          );
        }),
        // Unpaid bills
        _futureKpi('Unpaid Bills', db.kpiUnpaidBillsValue(), (m) {
          final count = m['count'] as int;
          final total = m['total'] as double;
          return KpiCard(
            title: 'UNPAID BILLS',
            value: fmtRupee(total),
            subtitle: '$count unpaid bill${count == 1 ? '' : 's'} outstanding',
            valueColor: count > 0 ? AppColors.error : AppColors.success,
            icon: Icons.pending_actions_rounded,
          );
        }),
        // Revenue by category
        _futureKpi('Revenue by Category', db.kpiRevenueByCategory(from: from, to: to), (rows) {
          final items = rows.map((r) => (
            label: r['category'] as String,
            value: (r['revenue'] as num).toDouble(),
          )).toList();
          return KpiHorizBarList(title: 'Revenue by Category', items: items);
        }),
        // Busy day of week
        _futureKpi('Busy Day of Week', db.kpiBusyDayOfWeek(from: from, to: to), (rows) {
          final data = List.generate(7, (i) {
            final row = rows.firstWhere(
              (r) => (r['dow'] as int) == i,
              orElse: () => {'dow': i, 'bills': 0, 'revenue': 0.0},
            );
            return (label: _days[i], value: (row['revenue'] as num).toDouble());
          });
          return KpiBarChart(title: 'Busy Day of Week (Revenue)', data: data, isRupee: true, barColor: AppColors.amber);
        }),
      ],
    );
  }

  Widget _futureAovRight(DatabaseHelper db, String? from, String? to) {
    return _futureKpi('Discount Rate', db.kpiDiscountRate(from: from, to: to), (v) {
      return KpiCard(
        title: 'DISCOUNT RATE',
        value: fmtPct(v),
        subtitle: 'Target < 5%',
        valueColor: v > 5 ? AppColors.error : AppColors.success,
        icon: Icons.discount_rounded,
      );
    });
  }
}

String _fmtMethod(String m) {
  switch (m.toLowerCase()) {
    case 'cash': return 'Cash';
    case 'upi': return 'UPI';
    case 'card': return 'Card';
    case 'online': return 'Online';
    default: return m[0].toUpperCase() + m.substring(1);
  }
}

// ── 📈 Profitability ─────────────────────────────────────────────────────────
class _ProfitSection extends StatelessWidget {
  final String? from, to;
  const _ProfitSection({this.from, this.to});

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gross profit + margin
        _futureKpi('Gross Profit', db.kpiGrossProfit(from: from, to: to), (gp) {
          return _futureKpi('Gross Margin', db.kpiGrossMarginPercent(from: from, to: to), (margin) {
            return KpiCardRow(
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
            );
          });
        }),
        // Commission + net profit
        _futureKpi('Commission & Net Profit', db.kpiTotalCommissionPaid(from: from, to: to), (comm) {
          return _futureKpi('Net Profit', db.kpiNetProfitAfterCommission(from: from, to: to), (net) {
            return KpiCardRow(
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
            );
          });
        }),
        // Monthly profit trend
        _futureKpi('Profit Trend', db.kpiMonthlyProfitTrend(from: from, to: to), (rows) {
          final data = rows.map((r) => (
            label: r['month'] as String,
            value: (r['profit'] as num).toDouble(),
          )).toList();
          return KpiLineChart(title: 'Monthly Profit Trend', data: data);
        }),
        // GST collected
        _futureKpi('GST Collected', db.kpiGstCollected(from: from, to: to), (v) {
          return KpiCard(
            title: 'GST COLLECTED',
            value: fmtRupee(v),
            subtitle: 'Matches GST returns',
            icon: Icons.account_balance_rounded,
          );
        }),
        // Top profit items
        _futureKpi('Top Profit Items', db.kpiTopProfitItems(from: from, to: to), (rows) {
          final items = rows.map((r) => (
            label: r['name'] as String,
            value: (r['profit'] as num).toDouble(),
          )).toList();
          return KpiHorizBarList(title: 'Top 10 — Highest Profit Items', items: items);
        }),
        // Lowest margin items
        _futureKpi('Low Margin Items', db.kpiTopNonProfitItems(from: from, to: to), (rows) {
          final items = rows.map((r) => (
            label: r['name'] as String,
            value: (r['profit'] as num).toDouble(),
          )).toList();
          return KpiHorizBarList(
            title: 'Bottom 10 — Lowest Margin Items',
            items: items,
            barColor: AppColors.error,
          );
        }),
        // Profit by category
        _futureKpi('Profit by Category', db.kpiProfitByCategory(from: from, to: to), (rows) {
          final items = rows.map((r) => (
            label: r['category'] as String,
            value: (r['profit'] as num).toDouble(),
          )).toList();
          return KpiHorizBarList(
            title: 'Profit by Category',
            items: items,
            barColor: AppColors.success,
          );
        }),
      ],
    );
  }
}

// ── 📦 Inventory ─────────────────────────────────────────────────────────────
class _InventorySection extends StatelessWidget {
  const _InventorySection();

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Inventory value + OOS count
        _futureKpi('Inventory Value', db.kpiTotalInventoryValue(), (inv) {
          return _futureKpi('Out of Stock', db.kpiOutOfStockCount(), (oos) {
            return KpiCardRow(
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
            );
          });
        }),
        // Low stock table
        _futureKpi('Low Stock', db.kpiLowStockProducts(), (rows) {
          return KpiDataTableCard(
            title: 'Low Stock Products (< 5 units)',
            columns: const ['Product', 'Qty'],
            rows: rows.map((r) => [r['name'] as String, fmtNum((r['quantity'] as num).toDouble())]).toList(),
            badgeCount: rows.length,
            badgeColor: AppColors.amber,
          );
        }),
        // Turnover rate
        _futureKpi('Inventory Turnover', db.kpiInventoryTurnoverRate(), (v) {
          return KpiCard(
            title: 'INVENTORY TURNOVER RATE',
            value: '${v.toStringAsFixed(2)}×',
            subtitle: 'Target > 4× per year',
            valueColor: v >= 4 ? AppColors.success : AppColors.amber,
            icon: Icons.loop_rounded,
          );
        }),
        // Dead stock
        _futureKpi('Dead Stock', db.kpiDeadStock(), (rows) {
          return KpiDataTableCard(
            title: 'Dead Stock (No sales in 30 days)',
            columns: const ['Product', 'Qty'],
            rows: rows.map((r) => [r['name'] as String, fmtNum((r['quantity'] as num).toDouble())]).toList(),
            badgeCount: rows.length,
          );
        }),
        // Top suppliers
        _futureKpi('Top Suppliers', db.kpiTopSuppliers(), (rows) {
          final items = rows.map((r) => (
            label: r['name'] as String,
            value: (r['value_received'] as num).toDouble(),
          )).toList();
          return KpiHorizBarList(title: 'Top Suppliers by Value Received', items: items);
        }),
        // Stock adjustment frequency
        _futureKpi('Stock Adjustments', db.kpiStockAdjustmentFrequency(), (v) {
          return KpiCard(
            title: 'STOCK ADJUSTMENTS',
            value: '$v',
            subtitle: 'Manual corrections (all time)',
            icon: Icons.tune_rounded,
          );
        }),
      ],
    );
  }
}

// ── 👥 Customers ─────────────────────────────────────────────────────────────
class _CustomersSection extends StatelessWidget {
  const _CustomersSection();

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Active + new customers
        _futureKpi('Active Customers', db.kpiTotalActiveCustomers(), (active) {
          return _futureKpi('New Customers', db.kpiNewCustomersAcquired(), (newC) {
            return KpiCardRow(
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
            );
          });
        }),
        // Repeat customer rate
        _futureKpi('Repeat Rate', db.kpiRepeatCustomerRate(), (v) {
          return KpiGaugeCard(
            title: 'Repeat Customer Rate',
            value: v,
            target: '> 30%',
          );
        }),
        // Avg CLV + Avg bills
        _futureKpi('Avg Lifetime Value', db.kpiAvgCustomerLifetimeValue(), (clv) {
          return _futureKpi('Avg Bills', db.kpiAvgBillsPerCustomer(), (avgB) {
            return KpiCardRow(
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
            );
          });
        }),
        // Top 10 customers
        _futureKpi('Top Customers', db.kpiTop10CustomersByRevenue(), (rows) {
          final items = rows.map((r) => (
            label: r['name'] as String,
            value: (r['total_purchase_amount'] as num).toDouble(),
          )).toList();
          return KpiHorizBarList(title: 'Top 10 Customers by Revenue', items: items);
        }),
        // Lapsed customers
        _futureKpi('Lapsed Customers', db.kpiLapsedCustomers(), (v) {
          return KpiCard(
            title: 'LAPSED CUSTOMERS',
            value: '$v',
            subtitle: 'No purchase in 60+ days',
            valueColor: v > 0 ? AppColors.error : AppColors.success,
            icon: Icons.person_off_rounded,
          );
        }),
      ],
    );
  }
}

// ── 🛍 Products ──────────────────────────────────────────────────────────────
class _ProductsSection extends StatelessWidget {
  final String? from, to;
  const _ProductsSection({this.from, this.to});

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top 10 by revenue
        _futureKpi('Top Products by Revenue', db.kpiTop10ProductsByRevenue(from: from, to: to), (rows) {
          final items = rows.map((r) => (
            label: r['name'] as String,
            value: (r['revenue'] as num).toDouble(),
          )).toList();
          return KpiHorizBarList(title: 'Top 10 Products by Revenue', items: items);
        }),
        // Top 10 by quantity
        _futureKpi('Top Products by Quantity', db.kpiTop10ProductsByQuantity(from: from, to: to), (rows) {
          final items = rows.map((r) => (
            label: r['name'] as String,
            value: (r['units_sold'] as num).toDouble(),
          )).toList();
          return KpiHorizBarList(title: 'Top 10 by Units Sold', items: items, isRupee: false, barColor: AppColors.navy);
        }),
        // Slow moving
        _futureKpi('Slow Moving Products', db.kpiSlowMovingProducts(), (rows) {
          return KpiDataTableCard(
            title: 'Slow Moving Products (< 3 units / 30 days)',
            columns: const ['Product', 'Qty Sold'],
            rows: rows.map((r) => [r['name'] as String, fmtNum((r['qty_sold'] as num).toDouble())]).toList(),
            badgeCount: rows.length,
          );
        }),
        // New products + price compliance
        _futureKpi('New Products', db.kpiNewProductsAdded(), (v) {
          return _futureKpi('Price Compliance', db.kpiProductPriceCompliance(from: from, to: to), (pct) {
            return KpiCardRow(
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
            );
          });
        }),
      ],
    );
  }
}

// ── ⚙ Operations ─────────────────────────────────────────────────────────────
class _OperationsSection extends StatelessWidget {
  final String? from, to;
  const _OperationsSection({this.from, this.to});

  @override
  Widget build(BuildContext context) {
    final db = DatabaseHelper.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bills/day + avg items/bill
        _futureKpi('Bills Per Day', db.kpiBillsPerDay(from: from, to: to), (bpd) {
          return _futureKpi('Avg Items', db.kpiAvgItemsPerBill(from: from, to: to), (avg) {
            return KpiCardRow(
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
            );
          });
        }),
        // Void rate
        _futureKpi('Bill Void Rate', db.kpiBillVoidRate(), (v) {
          return KpiGaugeCard(
            title: 'Bill Void Rate',
            value: v,
            target: '< 1%',
            higherIsBetter: false,
          );
        }),
        // Multi-device + catalog coverage
        _futureKpi('Devices', db.kpiMultiDeviceActivity(from: from, to: to), (devices) {
          return _futureKpi('Catalog Coverage', db.kpiCatalogCoverage(), (cov) {
            return KpiCardRow(
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
            );
          });
        }),
      ],
    );
  }
}
