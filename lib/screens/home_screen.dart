import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/customer.dart';
import '../models/product.dart';
import 'analytics_screen.dart';
import 'qr_sheet_screen.dart';
import 'notifications_screen.dart';

class HomeScreen extends StatefulWidget {
  final int refreshToken;
  final ValueChanged<int> onNavigate;
  final VoidCallback onScan;
  final VoidCallback onAddProduct;

  const HomeScreen({
    super.key,
    this.refreshToken = 0,
    required this.onNavigate,
    required this.onScan,
    required this.onAddProduct,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> _lowStockProducts = [];
  List<Product> _products = [];
  List<Bill> _unpaidBills = [];
  List<Bill> _bills = [];
  List<Customer> _customers = [];
  Map<int, double> _pendingByCustomerId = {};
  Map<String, double> _pendingByPhone = {};
  int _productCount = 0;
  int _todayBillCount = 0;
  double _todaySales = 0;
  double _todayCollected = 0;
  String? _shopName;
  final _homeSearchCtrl = TextEditingController();
  String _homeSearchQuery = '';
  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _homeSearchCtrl.addListener(_onSearchChanged);
    _loadData();
  }

  void _onSearchChanged() {
    final q = _homeSearchCtrl.text.trim();
    if (q != _homeSearchQuery) {
      setState(() => _homeSearchQuery = q);
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _loadData();
  }

  @override
  void dispose() {
    _homeSearchCtrl.removeListener(_onSearchChanged);
    _homeSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper.instance;
    final products = await db.getAllProducts();
    final customers = await db.getAllCustomers();
    final bills = await db.getAllBills();
    final shopName = await db.getShopName();
    final lowStockThreshold = await db.getLowStockThreshold();
    final todaySales = await db.getTodaySales();
    final todayCollected = await db.getTodayCollected();
    final todayBillCount = await db.getTodayBillCount();
    final unpaidBills = bills.where((bill) => bill.balanceDue > 0).take(3);
    final pending = _buildCustomerPendingMaps(bills);
    if (!mounted) return;
    setState(() {
      _products = products;
      _productCount = products.length;
      _todaySales = todaySales;
      _todayCollected = todayCollected;
      _todayBillCount = todayBillCount;
      _unpaidBills = unpaidBills.toList();
      _bills = bills;
      _customers = customers;
      _pendingByCustomerId = pending.byCustomerId;
      _pendingByPhone = pending.byPhone;
      _shopName = shopName;
      _lowStockProducts = products
          .where((p) => p.quantity <= lowStockThreshold)
          .toList();
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _homeSearchCtrl.clear();
        _homeSearchQuery = '';
        FocusScope.of(context).unfocus();
      }
    });
  }

  void _closeSearch() {
    _homeSearchCtrl.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _searchOpen = false;
      _homeSearchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_searchOpen) _closeSearch();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                titleOverride: _searchOpen
                    ? _HomeSearchField(controller: _homeSearchCtrl)
                    : null,
                actions: [
                  IconButton(
                    onPressed: _toggleSearch,
                    icon: Icon(
                      _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
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
                    if (_searchOpen && _homeSearchQuery.isNotEmpty) ...[
                      _HomeSearchResults(results: _searchResults),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    _SalesHero(
                      sales: _todaySales,
                      collected: _todayCollected,
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
                      onAddProduct: widget.onAddProduct,
                      onQrSheet: _openQrSheet,
                      onReports: _openReports,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    _WorkspaceShortcutsSection(
                      customerCount: _customers.length,
                      onCustomers: _openCustomersSheet,
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
      ),
    );
  }

  List<_HomeSearchResult> get _searchResults {
    final query = _homeSearchQuery.toLowerCase();
    if (query.isEmpty) return [];
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    final results = <_HomeSearchResult>[];

    for (final product in _products) {
      if (results.length >= 8) break;
      final matches =
          product.name.toLowerCase().contains(query) ||
          (product.itemCode?.toLowerCase().contains(query) ?? false) ||
          (product.barcode?.toLowerCase().contains(query) ?? false) ||
          (product.category?.toLowerCase().contains(query) ?? false) ||
          (product.supplier?.toLowerCase().contains(query) ?? false);
      if (!matches) continue;
      results.add(
        _HomeSearchResult(
          icon: Icons.inventory_2_outlined,
          color: AppColors.navy,
          title: product.name,
          subtitle: 'Product · ${product.quantityLabel} in stock',
          trailing: '₹${product.sellingPrice.toStringAsFixed(0)}',
          onTap: () => widget.onNavigate(1),
        ),
      );
    }

    for (final bill in _bills) {
      if (results.length >= 8) break;
      final number = _cleanBillNumber(bill).toLowerCase();
      final phone = bill.customerPhone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
      final matches =
          number.contains(query) ||
          bill.customerName.toLowerCase().contains(query) ||
          (digits.isNotEmpty && phone.contains(digits));
      if (!matches) continue;
      results.add(
        _HomeSearchResult(
          icon: Icons.receipt_long_outlined,
          color: AppColors.amber,
          title: _cleanBillNumber(bill),
          subtitle: 'Bill · ${bill.customerName}',
          trailing: '₹${bill.totalAmount.toStringAsFixed(0)}',
          onTap: () => widget.onNavigate(2),
        ),
      );
    }

    for (final customer in _customers) {
      if (results.length >= 8) break;
      final matches =
          customer.name.toLowerCase().contains(query) ||
          customer.phone.contains(digits.isEmpty ? query : digits) ||
          (customer.gstin?.toLowerCase().contains(query) ?? false) ||
          (customer.address?.toLowerCase().contains(query) ?? false);
      if (!matches) continue;
      final pending = _pendingAmount(customer);
      results.add(
        _HomeSearchResult(
          icon: Icons.people_outline_rounded,
          color: AppColors.success,
          title: customer.name,
          subtitle:
              'Customer · ${customer.billCount} purchase${customer.billCount != 1 ? 's' : ''}',
          trailing: pending > 0 ? 'Due ₹${pending.toStringAsFixed(0)}' : 'Paid',
          onTap: _openCustomersSheet,
        ),
      );
    }

    return results;
  }

  Future<void> _openQrSheet() async {
    final products = await DatabaseHelper.instance.getAllProducts();
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add products first!')));
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

  Future<void> _openCustomersSheet() async {
    final customers = await DatabaseHelper.instance.getAllCustomers();
    final bills = await DatabaseHelper.instance.getAllBills();
    if (!mounted) return;
    final pending = _buildCustomerPendingMaps(bills);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HomeCustomersSheet(
        customers: customers,
        pendingByCustomerId: pending.byCustomerId,
        pendingByPhone: pending.byPhone,
      ),
    );
    await _loadData();
  }

  double _pendingAmount(Customer customer) {
    final byId = customer.id == null ? null : _pendingByCustomerId[customer.id];
    if (byId != null) return byId;
    return _pendingByPhone[customer.phone] ?? 0;
  }
}

// ── Home Search ───────────────────────────────────────────────────────────────

/// Inline, borderless search field shown in the header after tapping search.
class _HomeSearchField extends StatelessWidget {
  final TextEditingController controller;

  const _HomeSearchField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        cursorColor: AppColors.amber,
        decoration: InputDecoration(
          isCollapsed: true,
          filled: false,
          hintText: 'Search products, bills, customers...',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 16,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

/// Search results list shown in the body when a query is active.
class _HomeSearchResults extends StatelessWidget {
  final List<_HomeSearchResult> results;

  const _HomeSearchResults({required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off_rounded,
        message: 'No matching products, bills, or customers',
      );
    }
    return CompactListCard(
      rows: results
          .map(
            (result) => CompactListRow(
              leading: LeadingIconChip(
                icon: result.icon,
                color: result.color,
              ),
              title: result.title,
              subtitle: result.subtitle,
              trailing: Text(
                result.trailing,
                style: AppText.caption.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkOf(context),
                ),
              ),
              onTap: result.onTap,
            ),
          )
          .toList(),
    );
  }
}

class _HomeSearchResult {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback onTap;

  const _HomeSearchResult({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });
}

// ── Workspace Shortcuts ───────────────────────────────────────────────────────

class _WorkspaceShortcutsSection extends StatelessWidget {
  final int customerCount;
  final VoidCallback onCustomers;

  const _WorkspaceShortcutsSection({
    required this.customerCount,
    required this.onCustomers,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Workspace'),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            _WorkspaceTile(
              icon: Icons.people_outline_rounded,
              label: 'Customers',
              subtitle: '$customerCount saved',
              color: AppColors.inkMutedOf(context),
              onTap: onCustomers,
            ),
            const SizedBox(width: AppSpacing.sm),
            _WorkspaceTile(
              icon: Icons.handshake_outlined,
              label: 'Suppliers',
              subtitle: 'Soon',
              color: AppColors.inkMutedOf(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            _WorkspaceTile(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Expenses',
              subtitle: 'Soon',
              color: AppColors.inkMutedOf(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            _WorkspaceTile(
              icon: Icons.group_work_outlined,
              label: 'Staff',
              subtitle: 'Soon',
              color: AppColors.inkMutedOf(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _WorkspaceTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.55,
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: enabled
                      ? color.withValues(alpha: 0.12)
                      : AppColors.surfaceOf(context),
                  borderRadius: AppRadius.mdRadius,
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: AppText.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkOf(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: AppText.caption.copyWith(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Customers Sheet ───────────────────────────────────────────────────────────

class _HomeCustomersSheet extends StatefulWidget {
  final List<Customer> customers;
  final Map<int, double> pendingByCustomerId;
  final Map<String, double> pendingByPhone;

  const _HomeCustomersSheet({
    required this.customers,
    required this.pendingByCustomerId,
    required this.pendingByPhone,
  });

  @override
  State<_HomeCustomersSheet> createState() => _HomeCustomersSheetState();
}

class _HomeCustomersSheetState extends State<_HomeCustomersSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Customer> get _filtered {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return widget.customers;
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    return widget.customers.where((customer) {
      return customer.name.toLowerCase().contains(query) ||
          customer.phone.contains(digits.isEmpty ? query : digits) ||
          (customer.gstin?.toLowerCase().contains(query) ?? false) ||
          (customer.address?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final customers = _filtered;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.84,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrongOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const LeadingIconChip(
                  icon: Icons.people_outline_rounded,
                  color: AppColors.success,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Customers',
                    style: AppText.title.copyWith(color: AppColors.inkOf(context)),
                  ),
                ),
                Text(
                  '${widget.customers.length}',
                  style: AppText.subtitle.copyWith(color: AppColors.inkMuted),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Search customers',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: customers.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching customers',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: customers.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (_, index) {
                        final customer = customers[index];
                        return _CustomerSummaryRow(
                          customer: customer,
                          pendingAmount: _pendingAmount(customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  double _pendingAmount(Customer customer) {
    final byId = customer.id == null
        ? null
        : widget.pendingByCustomerId[customer.id];
    if (byId != null) return byId;
    return widget.pendingByPhone[customer.phone] ?? 0;
  }
}

class _CustomerSummaryRow extends StatelessWidget {
  final Customer customer;
  final double pendingAmount;

  const _CustomerSummaryRow({
    required this.customer,
    required this.pendingAmount,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const LeadingIconChip(
            icon: Icons.person_outline_rounded,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: AppText.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (customer.phone.isNotEmpty)
                      _displayPhone(customer.phone),
                    '${customer.billCount} purchase${customer.billCount != 1 ? 's' : ''}',
                  ].join(' · '),
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${customer.totalPurchaseAmount.toStringAsFixed(0)}',
                style: AppText.subtitle.copyWith(fontSize: 14),
              ),
              Text(
                pendingAmount > 0
                    ? 'Due ₹${pendingAmount.toStringAsFixed(0)}'
                    : 'No due',
                style: AppText.caption.copyWith(
                  color: pendingAmount > 0
                      ? AppColors.error
                      : AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Sales Hero ──────────────────────────────────────────────────────────────

class _SalesHero extends StatelessWidget {
  final double sales;
  final double collected;
  final int billCount;

  const _SalesHero({
    required this.sales,
    required this.collected,
    required this.billCount,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.isDark(context) ? AppColors.darkSurfaceRaised : AppColors.navy,
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
                  "TODAY'S BOOKED SALES",
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
                      : '₹${collected.toStringAsFixed(2)} collected, $billCount bill${billCount != 1 ? 's' : ''} created',
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
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkOf(context),
                  height: 1.1,
                ),
              ),
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
              filled: false,
              onTap: onScan,
            ),
            const SizedBox(width: AppSpacing.sm),
            _QuickActionTile(
              icon: Icons.add_rounded,
              label: 'Add Product',
              color: AppColors.amber,
              filled: false,
              onTap: onAddProduct,
            ),
            const SizedBox(width: AppSpacing.sm),
            _QuickActionTile(
              icon: Icons.grid_view_rounded,
              label: 'Labels',
              color: AppColors.amber,
              filled: false,
              onTap: onQrSheet,
            ),
            const SizedBox(width: AppSpacing.sm),
            _QuickActionTile(
              icon: Icons.bar_chart_rounded,
              label: 'Reports',
              color: AppColors.amber,
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
                color: filled ? color : AppColors.surfaceOf(context),
                borderRadius: AppRadius.mdRadius,
                border: Border.all(
                  color: filled ? Colors.transparent : AppColors.borderOf(context),
                ),
              ),
              child: Icon(icon, color: filled ? Colors.white : color, size: 24),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.inkOf(context),
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
          .map(
            (bill) => CompactListRow(
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
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.inkOf(context),
                    ),
                  ),
                  bill.paymentStatus == Bill.statusPartial
                      ? StatusPill.partial()
                      : StatusPill.unpaid(),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ── Needs Attention Section ──────────────────────────────────────────────────

class _NeedsAttentionSection extends StatefulWidget {
  final List<Product> products;
  final VoidCallback onUpdate;

  const _NeedsAttentionSection({
    required this.products,
    required this.onUpdate,
  });

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
            child: Text(
              'No items match your search',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
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
      leading: StatusDot(color: isOut ? AppColors.error : AppColors.amber),
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
              final newQty = double.tryParse(qtyCtrl.text);
              if (newQty == null || newQty < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Quantity must be zero or more'),
                  ),
                );
                return;
              }
              await DatabaseHelper.instance.updateProduct(
                product.copyWith(quantity: newQty),
              );
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
          Text(
            message,
            style: AppText.caption.copyWith(color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

String _cleanBillNumber(Bill bill) {
  if (bill.billNumber.isEmpty) return 'Bill #${bill.id}';
  return bill.billNumber.replaceFirst(RegExp(r'^SHOP-LOCAL-local-'), 'INV-');
}

_CustomerPendingMaps _buildCustomerPendingMaps(List<Bill> bills) {
  final byCustomerId = <int, double>{};
  final byPhone = <String, double>{};
  for (final bill in bills) {
    if (bill.balanceDue <= 0) continue;
    final customerId = bill.customerId;
    if (customerId != null) {
      byCustomerId[customerId] =
          (byCustomerId[customerId] ?? 0) + bill.balanceDue;
    }
    final phone = _normaliseHomePhone(bill.customerPhone);
    if (phone != null) {
      byPhone[phone] = (byPhone[phone] ?? 0) + bill.balanceDue;
    }
  }
  return _CustomerPendingMaps(byCustomerId: byCustomerId, byPhone: byPhone);
}

String? _normaliseHomePhone(String? value) {
  final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits == null || digits.isEmpty || digits == '91') return null;
  if (digits.length == 10) return '91$digits';
  return digits;
}

String _displayPhone(String phone) {
  if (phone.length == 12 && phone.startsWith('91')) {
    return '+91 ${phone.substring(2, 7)} ${phone.substring(7)}';
  }
  return phone;
}

class _CustomerPendingMaps {
  final Map<int, double> byCustomerId;
  final Map<String, double> byPhone;

  const _CustomerPendingMaps({
    required this.byCustomerId,
    required this.byPhone,
  });
}
