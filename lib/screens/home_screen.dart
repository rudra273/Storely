import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/product.dart';
import 'analytics_screen.dart';
import 'qr_sheet_screen.dart';
import 'notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  final int refreshToken;
  final ValueChanged<int> onNavigate;
  final VoidCallback onScan;

  const HomeScreen({
    super.key,
    this.refreshToken = 0,
    required this.onNavigate,
    required this.onScan,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> _lowStockProducts = [];
  List<Bill> _unpaidBills = [];
  int _productCount = 0;
  int _todayBillCount = 0;
  double _todaySales = 0;
  String? _shopName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper.instance;
    final products = await db.getAllProducts();
    final shopName = await db.getShopName();
    final lowStockThreshold = await db.getLowStockThreshold();
    final todaySales = await db.getTodaySales();
    final todayBillCount = await db.getTodayBillCount();
    final unpaidBills = await db.getUnpaidBills(limit: 3);
    if (!mounted) return;
    setState(() {
      _productCount = products.length;
      _todaySales = todaySales;
      _todayBillCount = todayBillCount;
      _unpaidBills = unpaidBills;
      _shopName = shopName;
      _lowStockProducts =
          products.where((p) => p.quantity <= lowStockThreshold).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.amber,
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: AppScreenHeaderDelegate(
                title: 'Storely',
                subtitle: _shopName,
                topPadding: MediaQuery.paddingOf(context).top,
                actions: [
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    ),
                    icon: const Icon(
                      Icons.notifications_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SalesHero(
                      sales: _todaySales,
                      billCount: _todayBillCount,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _StatsRow(
                      productCount: _productCount,
                      billCount: _todayBillCount,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    _QuickActionsSection(
                      onScan: widget.onScan,
                      onAddProduct: () => widget.onNavigate(1),
                      onQrSheet: _openQrSheet,
                      onReports: _openReports,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    SectionHeader(
                      title: 'Unpaid Bills',
                      actionLabel: 'View All →',
                      onAction: () => widget.onNavigate(2),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _UnpaidBillsSection(bills: _unpaidBills),
                    const SizedBox(height: AppSpacing.xxl),
                    SectionHeader(
                      title: 'Needs Attention',
                      actionLabel: 'View All →',
                      onAction: () => widget.onNavigate(1),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _NeedsAttentionSection(
                      products: _lowStockProducts,
                      onUpdate: _loadData,
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openQrSheet() async {
    final products = await DatabaseHelper.instance.getAllProducts();
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add products first!')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QrSheetScreen(products: products)),
    );
  }

  void _openReports() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
    );
  }
}

// ── Sales Hero ──────────────────────────────────────────────────────────────

class _SalesHero extends StatelessWidget {
  final double sales;
  final int billCount;

  const _SalesHero({required this.sales, required this.billCount});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.navy,
      borderRadius: AppRadius.lgRadius,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "TODAY'S SALES",
                  style: AppText.label.copyWith(
                    color: Colors.white60,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '₹${sales.toStringAsFixed(2)}',
                  style: AppText.display.copyWith(
                    color: Colors.white,
                    fontSize: 30,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  billCount == 0
                      ? 'No bills yet today'
                      : '$billCount bill${billCount != 1 ? 's' : ''} created',
                  style: AppText.caption.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.15),
              borderRadius: AppRadius.mdRadius,
            ),
            child: const Icon(
              Icons.trending_up_rounded,
              color: AppColors.amber,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats Row ────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int productCount;
  final int billCount;

  const _StatsRow({required this.productCount, required this.billCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Products',
            value: '$productCount',
            subtitle: 'in catalog',
            icon: Icons.inventory_2_outlined,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatTile(
            label: 'Bills Today',
            value: '$billCount',
            subtitle: 'transactions',
            icon: Icons.receipt_long_outlined,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value, subtitle;
  final IconData icon;

  const _StatTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: AppRadius.smRadius,
            ),
            child: Icon(icon, size: 16, color: AppColors.inkMuted),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.1,
                  )),
              Text(label, style: AppText.caption),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Quick Actions ────────────────────────────────────────────────────────────

class _QuickActionsSection extends StatelessWidget {
  final VoidCallback onScan;
  final VoidCallback onAddProduct;
  final VoidCallback onQrSheet;
  final VoidCallback onReports;

  const _QuickActionsSection({
    required this.onScan,
    required this.onAddProduct,
    required this.onQrSheet,
    required this.onReports,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Quick Actions'),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            _QuickActionTile(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Scan & Bill',
              color: AppColors.amber,
              filled: true,
              onTap: onScan,
            ),
            const SizedBox(width: AppSpacing.sm),
            _QuickActionTile(
              icon: Icons.add_rounded,
              label: 'Add Product',
              color: AppColors.navy,
              filled: true,
              onTap: onAddProduct,
            ),
            const SizedBox(width: AppSpacing.sm),
            _QuickActionTile(
              icon: Icons.grid_view_rounded,
              label: 'QR Sheet',
              color: AppColors.navy,
              filled: false,
              onTap: onQrSheet,
            ),
            const SizedBox(width: AppSpacing.sm),
            _QuickActionTile(
              icon: Icons.bar_chart_rounded,
              label: 'Reports',
              color: AppColors.navy,
              filled: false,
              onTap: onReports,
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: filled ? color : AppColors.surface,
                borderRadius: AppRadius.mdRadius,
                border: Border.all(
                  color: filled ? Colors.transparent : AppColors.border,
                ),
              ),
              child: Icon(
                icon,
                color: filled ? Colors.white : color,
                size: 24,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Unpaid Bills Section ─────────────────────────────────────────────────────

class _UnpaidBillsSection extends StatelessWidget {
  final List<Bill> bills;
  const _UnpaidBillsSection({required this.bills});

  @override
  Widget build(BuildContext context) {
    if (bills.isEmpty) {
      return _EmptyState(
        icon: Icons.task_alt_rounded,
        message: 'All bills are paid!',
      );
    }
    return CompactListCard(
      rows: bills
          .map((bill) => CompactListRow(
                leading: const LeadingIconChip(
                  icon: Icons.pending_actions_outlined,
                  color: AppColors.error,
                ),
                title: bill.customerName.isEmpty ? 'Walk-in' : bill.customerName,
                subtitle:
                    '${_cleanBillNumber(bill)} · ${bill.itemCount} item${bill.itemCount != 1 ? 's' : ''}',
                trailing: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '₹${bill.balanceDue.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                    bill.paymentStatus == Bill.statusPartial
                        ? StatusPill.partial()
                        : StatusPill.unpaid(),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

// ── Needs Attention Section ──────────────────────────────────────────────────

class _NeedsAttentionSection extends StatefulWidget {
  final List<Product> products;
  final VoidCallback onUpdate;

  const _NeedsAttentionSection({required this.products, required this.onUpdate});

  @override
  State<_NeedsAttentionSection> createState() => _NeedsAttentionSectionState();
}

class _NeedsAttentionSectionState extends State<_NeedsAttentionSection> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    if (widget.products.isEmpty) {
      return _EmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'All stocked up!',
      );
    }

    final filtered = _query.isEmpty
        ? widget.products
        : widget.products
            .where((p) => p.name.toLowerCase().contains(_query))
            .toList();

    return Column(
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v.toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Search items...',
            prefixIcon: const Icon(Icons.search, size: 20),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('No items match your search',
                style: AppText.caption, textAlign: TextAlign.center),
          )
        else
          CompactListCard(
            rows: filtered
                .map((p) => _LowStockRow(product: p, onUpdate: widget.onUpdate))
                .toList(),
          ),
      ],
    );
  }
}

class _LowStockRow extends StatelessWidget {
  final Product product;
  final VoidCallback onUpdate;

  const _LowStockRow({required this.product, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final isOut = product.quantity == 0;
    return CompactListRow(
      leading: StatusDot(
        color: isOut ? AppColors.error : AppColors.amber,
      ),
      title: product.name,
      subtitle: isOut ? 'Out of stock' : 'Only ${product.quantityLabel} left',
      trailing: StatusPill(
        label: isOut ? 'Out' : 'Low',
        variant: isOut ? PillVariant.out : PillVariant.low,
      ),
      onTap: () => _showQuantityDialog(context),
    );
  }

  void _showQuantityDialog(BuildContext context) {
    final qtyCtrl = TextEditingController(
      text: product.quantity == product.quantity.toInt()
          ? product.quantity.toInt().toString()
          : product.quantity.toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Quantity'),
        content: TextField(
          controller: qtyCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'New Quantity',
            hintText: 'Enter new quantity',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newQty = double.tryParse(qtyCtrl.text) ?? 0;
              await DatabaseHelper.instance
                  .updateProduct(product.copyWith(quantity: newQty));
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((updated) {
      if (updated == true) onUpdate();
    });
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.lg,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: AppColors.inkFaint),
          const SizedBox(width: AppSpacing.sm),
          Text(message,
              style: AppText.caption.copyWith(color: AppColors.inkMuted)),
        ],
      ),
    );
  }
}

String _cleanBillNumber(Bill bill) {
  if (bill.billNumber.isEmpty) return 'Bill #${bill.id}';
  return bill.billNumber.replaceFirst(RegExp(r'^SHOP-LOCAL-local-'), 'INV-');
}
