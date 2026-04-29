import 'package:flutter/material.dart';
import '../main.dart';
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
  String _attentionSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadData();
    }
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
      _lowStockProducts = products
          .where((p) => p.quantity <= lowStockThreshold)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _HomeHeaderDelegate(
                shopName: _shopName ?? 'Storely',
                topPadding: MediaQuery.paddingOf(context).top,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── TODAY'S OVERVIEW ──
                    Text(
                      "TODAY'S OVERVIEW",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Sales card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Sales Today',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹ ${_todaySales.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _todayBillCount == 0
                                ? 'Start scanning to create bills!'
                                : '$_todayBillCount bill${_todayBillCount != 1 ? 's' : ''} created today',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Stats row
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Products',
                            value: '$_productCount',
                            subtitle: 'in catalog',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _StatCard(
                            label: 'Bills Today',
                            value: '$_todayBillCount',
                            subtitle: 'transactions',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),
                    // ── QUICK ACTIONS ──
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _QuickAction(
                          icon: Icons.qr_code_scanner_rounded,
                          label: 'Scan & Bill',
                          color: AppColors.navy,
                          onTap: widget.onScan,
                        ),
                        _QuickAction(
                          icon: Icons.add_rounded,
                          label: 'Add Product',
                          color: AppColors.amber,
                          onTap: () => widget.onNavigate(1),
                        ),
                        _QuickAction(
                          icon: Icons.grid_view_rounded,
                          label: 'QR Sheet',
                          color: AppColors.navy,
                          filled: false,
                          onTap: () async {
                            final products = await DatabaseHelper.instance
                                .getAllProducts();
                            if (!context.mounted) return;
                            if (products.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Add products first!'),
                                ),
                              );
                              return;
                            }
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    QrSheetScreen(products: products),
                              ),
                            );
                          },
                        ),
                        _QuickAction(
                          icon: Icons.bar_chart_rounded,
                          label: 'Reports',
                          color: AppColors.navy,
                          filled: false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AnalyticsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),
                    Row(
                      children: [
                        const Text(
                          'Unpaid Bills',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => widget.onNavigate(2),
                          child: Text(
                            'View All →',
                            style: TextStyle(
                              color: AppColors.amber,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_unpaidBills.isNotEmpty) ...[
                      ..._unpaidBills.map(
                        (bill) => _UnpaidBillItem(bill: bill),
                      ),
                    ] else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.task_alt_rounded,
                              size: 40,
                              color: AppColors.amber.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'All bills are paid!',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    const SizedBox(height: 8),
                    // ── NEEDS ATTENTION ──
                    Row(
                      children: [
                        const Text(
                          'Needs Attention',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => widget.onNavigate(1),
                          child: Text(
                            'View All →',
                            style: TextStyle(
                              color: AppColors.amber,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Search bar for Needs Attention
                    if (_lowStockProducts.isNotEmpty || _attentionSearchQuery.isNotEmpty) ...[
                      TextField(
                        onChanged: (value) {
                          setState(() {
                            _attentionSearchQuery = value.toLowerCase();
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search items...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_lowStockProducts.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 40,
                              color: AppColors.amber.withValues(alpha: 0.7),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'All stocked up!',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_attentionSearchQuery.isNotEmpty && !_lowStockProducts.any((p) => p.name.toLowerCase().contains(_attentionSearchQuery)))
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('No items found matching your search')),
                      )
                    else
                      ...(_lowStockProducts.where((p) => p.name.toLowerCase().contains(_attentionSearchQuery)).map(
                        (p) => _LowStockItem(
                          product: p,
                          onUpdate: _loadData,
                        ),
                      )),
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
}

class _StatCard extends StatelessWidget {
  final String label, value, subtitle;
  const _StatCard({
    required this.label,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navyLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: filled ? color : null,
              border: filled
                  ? null
                  : Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: filled ? Colors.white : color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LowStockItem extends StatelessWidget {
  final Product product;
  final VoidCallback onUpdate;
  const _LowStockItem({required this.product, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final isOut = product.quantity == 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showQuantityDialog(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOut ? AppColors.error : AppColors.amber,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        isOut ? 'Out of stock' : 'Only ${product.quantityLabel} left',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isOut
                        ? AppColors.error.withValues(alpha: 0.1)
                        : AppColors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isOut ? 'Out' : 'Low',
                    style: TextStyle(
                      color: isOut ? AppColors.error : AppColors.amber,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      builder: (ctx) {
        return AlertDialog(
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
            ElevatedButton(
              onPressed: () async {
                final newQty = double.tryParse(qtyCtrl.text) ?? 0;
                final updatedProduct = product.copyWith(quantity: newQty);
                await DatabaseHelper.instance.updateProduct(updatedProduct);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).then((updated) {
      if (updated == true) {
        onUpdate();
      }
    });
  }
}

class _UnpaidBillItem extends StatelessWidget {
  final Bill bill;
  const _UnpaidBillItem({required this.bill});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.pending_actions_outlined,
              color: AppColors.error,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.customerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '${_cleanBillNumber(bill)} • ${bill.itemCount} item${bill.itemCount != 1 ? 's' : ''} pending',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '₹${bill.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

String _cleanBillNumber(Bill bill) {
  if (bill.billNumber.isEmpty) return 'Bill #${bill.id}';
  return bill.billNumber.replaceFirst(
    RegExp(r'^SHOP-LOCAL-local-'),
    'INV-',
  );
}

class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String shopName;
  final double topPadding;

  const _HomeHeaderDelegate({required this.shopName, required this.topPadding});

  @override
  double get minExtent => topPadding + 44;

  @override
  double get maxExtent => topPadding + 74;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final expanded = range == 0
        ? 0.0
        : (1 - (shrinkOffset / range)).clamp(0.0, 1.0);
    final collapsed = 1 - expanded;
    final titleTop = _lerp(topPadding + 12, topPadding + 40, expanded);

    return Container(
      color: AppColors.navy,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 20,
            top: topPadding + 4,
            child: IgnorePointer(
              ignoring: expanded < 0.1,
              child: Opacity(
                opacity: expanded,
                child: RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    children: [
                      TextSpan(
                        text: 'Store',
                        style: TextStyle(color: Colors.white),
                      ),
                      TextSpan(
                        text: 'ly',
                        style: TextStyle(color: AppColors.amber),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 20,
            top: topPadding + 12,
            child: IgnorePointer(
              ignoring: expanded < 0.1,
              child: Opacity(
                opacity: expanded,
                child: IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    );
                  },
                  icon: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            top: titleTop,
            child: Text(
              shopName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: _lerp(1, 0.62, expanded)),
                fontSize: _lerp(16, 13, expanded),
                fontWeight: collapsed > 0.5 ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _lerp(double start, double end, double t) {
    return start + (end - start) * t;
  }

  @override
  bool shouldRebuild(covariant _HomeHeaderDelegate oldDelegate) {
    return oldDelegate.shopName != shopName ||
        oldDelegate.topPadding != topPadding;
  }
}
