import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Top-level grouping for the analytics dashboard. Each KPI belongs to exactly
/// one category; the customize sheet and the screen render KPIs grouped by it.
enum KpiCategory {
  sales('Sales & Revenue', '💰'),
  products('Products & Inventory', '🛍'),
  operations('Operations & Customers', '⚙');

  final String label;
  final String emoji;
  const KpiCategory(this.label, this.emoji);
}

/// Cost hint shown in the customize sheet so users understand which KPIs are
/// heavy to compute on large datasets. Purely informational.
enum KpiCost { light, moderate, heavy }

/// Static descriptor for a single KPI tile on the analytics dashboard.
///
/// [id] is the stable storage key — never change it once shipped or users lose
/// their saved selection for that KPI.
class KpiDef {
  final String id;
  final String title;
  final KpiCategory category;
  final bool defaultOn;
  final KpiCost cost;

  const KpiDef({
    required this.id,
    required this.title,
    required this.category,
    required this.defaultOn,
    this.cost = KpiCost.moderate,
  });
}

/// The canonical catalogue of every analytics KPI. Order here is the display
/// order within each category. Adding a KPI = add an entry here and render it in
/// analytics_screen.dart keyed by the same [id].
const kpiCatalogue = <KpiDef>[
  // ── Sales & Revenue ───────────────────────────────────────────────────────
  KpiDef(
    id: 'total_revenue',
    title: 'Total Revenue',
    category: KpiCategory.sales,
    defaultOn: true,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'avg_order_value',
    title: 'Average Order Value & Discount Rate',
    category: KpiCategory.sales,
    defaultOn: true,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'revenue_trend',
    title: 'Daily Revenue Trend',
    category: KpiCategory.sales,
    defaultOn: true,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'payment_method',
    title: 'Collections by Payment Method',
    category: KpiCategory.sales,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'unpaid_bills',
    title: 'Unpaid Bills',
    category: KpiCategory.sales,
    defaultOn: true,
    cost: KpiCost.light,
  ),
  KpiDef(
    id: 'revenue_by_category',
    title: 'Revenue by Category',
    category: KpiCategory.sales,
    defaultOn: false,
    cost: KpiCost.heavy,
  ),
  KpiDef(
    id: 'busy_day',
    title: 'Busy Day of Week',
    category: KpiCategory.sales,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'gross_profit',
    title: 'Gross Profit & Margin',
    category: KpiCategory.sales,
    defaultOn: true,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'net_profit',
    title: 'Commission & Net Profit',
    category: KpiCategory.sales,
    defaultOn: true,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'profit_trend',
    title: 'Monthly Profit Trend',
    category: KpiCategory.sales,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'gst_collected',
    title: 'GST Collected',
    category: KpiCategory.sales,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'profit_by_category',
    title: 'Profit by Category',
    category: KpiCategory.sales,
    defaultOn: false,
    cost: KpiCost.heavy,
  ),

  // ── Products & Inventory ──────────────────────────────────────────────────
  KpiDef(
    id: 'top_products_revenue',
    title: 'Top Products by Revenue',
    category: KpiCategory.products,
    defaultOn: true,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'top_products_quantity',
    title: 'Top Products by Quantity',
    category: KpiCategory.products,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'top_profit_items',
    title: 'Top Profit Items',
    category: KpiCategory.products,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'low_margin_items',
    title: 'Low Margin Items',
    category: KpiCategory.products,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'inventory_value',
    title: 'Inventory Value & Out of Stock',
    category: KpiCategory.products,
    defaultOn: true,
    cost: KpiCost.light,
  ),
  KpiDef(
    id: 'low_stock',
    title: 'Low Stock Products',
    category: KpiCategory.products,
    defaultOn: true,
    cost: KpiCost.light,
  ),
  KpiDef(
    id: 'inventory_turnover',
    title: 'Inventory Turnover',
    category: KpiCategory.products,
    defaultOn: false,
    cost: KpiCost.heavy,
  ),
  KpiDef(
    id: 'dead_stock',
    title: 'Dead Stock',
    category: KpiCategory.products,
    defaultOn: false,
    cost: KpiCost.heavy,
  ),
  KpiDef(
    id: 'slow_moving',
    title: 'Slow Moving Products',
    category: KpiCategory.products,
    defaultOn: false,
    cost: KpiCost.heavy,
  ),
  KpiDef(
    id: 'top_suppliers',
    title: 'Top Suppliers',
    category: KpiCategory.products,
    defaultOn: false,
    cost: KpiCost.heavy,
  ),
  KpiDef(
    id: 'new_products',
    title: 'New Products & Direct Pricing',
    category: KpiCategory.products,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),

  // ── Operations & Customers ────────────────────────────────────────────────
  KpiDef(
    id: 'active_customers',
    title: 'Active & New Customers',
    category: KpiCategory.operations,
    defaultOn: true,
    cost: KpiCost.light,
  ),
  KpiDef(
    id: 'top_customers',
    title: 'Top Customers by Revenue',
    category: KpiCategory.operations,
    defaultOn: true,
    cost: KpiCost.light,
  ),
  KpiDef(
    id: 'repeat_rate',
    title: 'Repeat Customer Rate',
    category: KpiCategory.operations,
    defaultOn: false,
    cost: KpiCost.light,
  ),
  KpiDef(
    id: 'customer_value',
    title: 'Avg Lifetime Value & Bills',
    category: KpiCategory.operations,
    defaultOn: false,
    cost: KpiCost.light,
  ),
  KpiDef(
    id: 'lapsed_customers',
    title: 'Lapsed Customers',
    category: KpiCategory.operations,
    defaultOn: false,
    cost: KpiCost.light,
  ),
  KpiDef(
    id: 'bills_per_day',
    title: 'Bills Per Day & Avg Items',
    category: KpiCategory.operations,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'void_rate',
    title: 'Bill Void Rate',
    category: KpiCategory.operations,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'devices_coverage',
    title: 'Active Devices & Catalog Coverage',
    category: KpiCategory.operations,
    defaultOn: false,
    cost: KpiCost.moderate,
  ),
  KpiDef(
    id: 'stock_adjustments',
    title: 'Stock Adjustments',
    category: KpiCategory.operations,
    defaultOn: false,
    cost: KpiCost.light,
  ),
];

/// Persisted user choice of which analytics KPIs are visible.
///
/// Hidden KPIs are never mounted on the dashboard, so their (sometimes
/// expensive) SQL query never runs — that is the whole point: fewer queries on
/// open = faster screen. Mirrors [HomeSectionPrefs]: a SharedPreferences-backed
/// [ChangeNotifier] singleton loaded once at startup.
class KpiPrefs extends ChangeNotifier {
  static final KpiPrefs instance = KpiPrefs._();
  KpiPrefs._();

  static const _enabledKey = 'analytics_enabled_kpis';

  /// Set of enabled KPI ids. Null until [load] completes; callers should only
  /// read after load (the app awaits it in main()).
  Set<String> _enabled = _defaultEnabled();

  static Set<String> _defaultEnabled() => {
    for (final def in kpiCatalogue)
      if (def.defaultOn) def.id,
  };

  bool isEnabled(String id) => _enabled.contains(id);

  int get enabledCount => _enabled.length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_enabledKey);
    if (stored == null) {
      // First run: keep the default-on set.
      _enabled = _defaultEnabled();
      return;
    }
    // Only honour ids that still exist in the catalogue (drops stale ids from
    // removed KPIs). An empty stored list is respected as "user hid everything".
    final valid = {for (final def in kpiCatalogue) def.id};
    _enabled = stored.where(valid.contains).toSet();
  }

  Future<void> setEnabled(String id, bool value) async {
    final changed = value ? _enabled.add(id) : _enabled.remove(id);
    if (!changed) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_enabledKey, _enabled.toList());
  }

  Future<void> resetToDefaults() async {
    _enabled = _defaultEnabled();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_enabledKey, _enabled.toList());
  }
}
