import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/test_keys.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/customer.dart';
import '../models/product.dart';
import 'analytics_screen.dart';
import 'qr_sheet_screen.dart';
import 'notifications_screen.dart';
import 'suppliers_screen.dart';
import 'expenses_screen.dart';
import 'shared/sync_status_widgets.dart';
import 'shared/bill_quick_sheet.dart';
import '../services/needs_action.dart';
import '../services/home_search.dart';
import '../services/cloud_service.dart';
import 'products_screen.dart';
import 'customers_screen.dart';
import 'pricing_screen.dart';
import 'home/home_section_settings.dart';
import '../services/home_section_prefs.dart';
import '../utils/money.dart';

class HomeScreen extends StatefulWidget {
  final int refreshToken;
  final ValueChanged<int> onNavigate;
  final VoidCallback onScan;
  final VoidCallback? onFirstInvoice;
  final VoidCallback onAddProduct;

  const HomeScreen({
    super.key,
    this.refreshToken = 0,
    required this.onNavigate,
    required this.onScan,
    this.onFirstInvoice,
    required this.onAddProduct,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Product> _lowStockProducts = [];

  /// False until the first load finishes, so zeros never flash as if the
  /// shop had no data.
  bool _loaded = false;
  bool _searchLoaded = false;
  int _needsActionCount = 0;
  List<Product> _searchProducts = [];
  List<Bill> _unpaidBills = [];
  List<Bill> _bills = [];
  List<Customer> _customers = [];
  int _productCount = 0;
  bool _hasFirstProduct = false;
  bool _hasSavedOriginalInvoice = false;
  (String?, CloudMembership, String?, String?)? _cloudSearchIdentity;
  int _loadGeneration = 0;
  CheckoutScope? _loadedSearchScope;
  int _supplierCount = 0;
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
    HomeSectionPrefs.instance.addListener(_onPrefsChanged);
    _cloudSearchIdentity = _searchIdentity(CloudService.instance.state.value);
    CloudService.instance.state.addListener(_onCloudSearchScopeChanged);
    _loadData();
  }

  (String?, CloudMembership, String?, String?) _searchIdentity(
    CloudState state,
  ) => (state.user?.id, state.membership, state.shopRole, state.config?.url);

  void _onCloudSearchScopeChanged() {
    final identity = _searchIdentity(CloudService.instance.state.value);
    if (identity == _cloudSearchIdentity || !mounted) return;
    _cloudSearchIdentity = identity;
    _homeSearchCtrl.clear();
    _loadData();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
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
    HomeSectionPrefs.instance.removeListener(_onPrefsChanged);
    CloudService.instance.state.removeListener(_onCloudSearchScopeChanged);
    _homeSearchCtrl.dispose();
    super.dispose();
  }

  List<Bill> get _displayedUnpaidBills {
    final prefs = HomeSectionPrefs.instance;
    final list = [..._unpaidBills];
    switch (prefs.unpaidSort) {
      case UnpaidBillsSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case UnpaidBillsSort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case UnpaidBillsSort.highest:
        list.sort((a, b) => b.balanceDue.compareTo(a.balanceDue));
    }
    return list.take(prefs.unpaidCount).toList();
  }

  List<Product> get _displayedLowStock =>
      _lowStockProducts.take(HomeSectionPrefs.instance.attentionCount).toList();

  Future<void> _editLowStockThreshold() async {
    final db = DatabaseHelper.instance;
    var baseline = await db.captureSettingsEditBaseline();
    final threshold = await db.getLowStockThreshold();
    if (!mounted) return;
    await showNeedsAttentionSettings(
      context,
      threshold: threshold,
      onThreshold: (value) async {
        baseline = await db.saveLowStockThresholdWithBaseline(
          value,
          baseline: baseline,
        );
        await _loadData();
      },
    );
  }

  Future<void> _loadData() async {
    final generation = ++_loadGeneration;
    if (mounted) setState(() => _searchLoaded = false);
    final db = DatabaseHelper.instance;
    final scope = await db.captureCheckoutScope();
    final progress = await db.getFirstInvoiceProgress();
    final products = await db.getAllProducts();
    final searchProducts = await db.getProductsForHomeSearch(scope.shopId);
    final customers = await db.getCustomersForHomeSearch(scope.shopId);
    final suppliers = await db.getSupplierProfiles();
    final bills = await db.getAllBills();
    final shopName = await db.getShopName();
    final lowStockThreshold = await db.getLowStockThreshold();
    final todaySales = await db.getTodaySales();
    final todayCollected = await db.getTodayCollected();
    final todayBillCount = await db.getTodayBillCount();
    final needsAction = await NeedsAction.load();
    final unpaidBills = bills.where((bill) => bill.balanceDue > 0).toList();
    if (!mounted || generation != _loadGeneration) return;
    if (!await isCurrentHomeSearchScope(scope)) return;
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _loaded = true;
      _searchLoaded = true;
      _loadedSearchScope = scope;
      _needsActionCount = needsAction.length;
      _searchProducts = searchProducts;
      _productCount = products.length;
      _hasFirstProduct = progress.hasProducts;
      _hasSavedOriginalInvoice = progress.hasInvoice;
      _supplierCount = suppliers.length;
      _todaySales = todaySales;
      _todayCollected = todayCollected;
      _todayBillCount = todayBillCount;
      _unpaidBills = unpaidBills;
      _bills = bills;
      _customers = customers;
      _shopName = shopName;
      _lowStockProducts = products
          .where((p) => p.isLowStock(lowStockThreshold))
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
    final showSearchResults = _searchOpen && _homeSearchQuery.isNotEmpty;

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
                    if (!_searchOpen) const SyncStatusIcon(color: Colors.white),
                    IconButton(
                      onPressed: _toggleSearch,
                      icon: Icon(
                        _searchOpen
                            ? Icons.close_rounded
                            : Icons.search_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    TestKeys.tag(
                      TestKeys.homeNotificationsBtn,
                      IconButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const NotificationsScreen(),
                            ),
                          );
                          if (mounted) _loadData();
                        },
                        icon: Badge(
                          isLabelVisible: _needsActionCount > 0,
                          label: Text('$_needsActionCount'),
                          child: const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      label: context.l10n.notifications,
                      button: true,
                    ),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: showSearchResults
                        ? [
                            if (!_searchLoaded)
                              const SizedBox(
                                height: 240,
                                child: AppSkeletonList(rows: 3, rowHeight: 80),
                              )
                            else
                              _HomeSearchResults(results: _searchResults),
                          ]
                        : !_loaded
                        ? [
                            const SizedBox(
                              height: 480,
                              child: AppSkeletonList(rows: 5, rowHeight: 80),
                            ),
                          ]
                        : [
                            if (!_hasSavedOriginalInvoice &&
                                (DatabaseHelper.instance.isAdminMutationAllowed
                                        ?.call() ??
                                    true)) ...[
                              _FirstInvoiceGuide(
                                hasProduct: _hasFirstProduct,
                                onAddProduct: widget.onAddProduct,
                                onInvoice:
                                    widget.onFirstInvoice ?? widget.onScan,
                              ),
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
                              onProducts: () => widget.onNavigate(1),
                              onBills: () => widget.onNavigate(2),
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
                              onCustomers: _openCustomers,
                              supplierCount: _supplierCount,
                              onSuppliers: _openSuppliers,
                              onPricing: _openPricing,
                              onExpenses: _openExpenses,
                            ),
                            if (!HomeSectionPrefs.instance.unpaidHidden) ...[
                              const SizedBox(height: AppSpacing.xxl),
                              SectionHeader(
                                title: context.l10n.unpaidBills,
                                actionLabel: context.l10n.viewAll,
                                onAction: () => widget.onNavigate(2),
                                onMenu: () => showUnpaidBillsSettings(context),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _UnpaidBillsSection(
                                bills: _displayedUnpaidBills,
                                onTap: (bill) async {
                                  if (await showBillQuickSheet(context, bill) &&
                                      mounted) {
                                    _loadData();
                                  }
                                },
                              ),
                            ] else ...[
                              const SizedBox(height: AppSpacing.xxl),
                              _HiddenSectionStrip(
                                title: context.l10n.unpaidBills,
                                onShow: () => HomeSectionPrefs.instance
                                    .setUnpaidHidden(false),
                              ),
                            ],
                            if (!HomeSectionPrefs.instance.attentionHidden) ...[
                              const SizedBox(height: AppSpacing.xxl),
                              SectionHeader(
                                title: context.l10n.needsAttention,
                                actionLabel: context.l10n.viewAll,
                                onAction: () => widget.onNavigate(1),
                                onMenu: _editLowStockThreshold,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _NeedsAttentionSection(
                                products: _displayedLowStock,
                                onUpdate: _loadData,
                              ),
                            ] else ...[
                              const SizedBox(height: AppSpacing.xxl),
                              _HiddenSectionStrip(
                                title: context.l10n.needsAttention,
                                onShow: () => HomeSectionPrefs.instance
                                    .setAttentionHidden(false),
                              ),
                            ],
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
    final query = HomeSearchQuery(_homeSearchQuery);
    final scope = _loadedSearchScope;
    if (!_searchLoaded || query.text.isEmpty || scope == null) return [];
    final shop = scope.shopId;
    final results = <_HomeSearchResult>[];

    final products =
        _searchProducts
            .where(
              (p) =>
                  p.shopId == shop &&
                  query.product(
                    p,
                    allowSupplier:
                        DatabaseHelper.instance.isAdminMutationAllowed
                            ?.call() ??
                        true,
                  ),
            )
            .toList()
          ..sort((a, b) {
            final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return name != 0 ? name : a.uuid.compareTo(b.uuid);
          });
    final bills =
        _bills.where((b) => b.shopId == shop && query.bill(b)).toList()
          ..sort((a, b) {
            final date = b.createdAt.compareTo(a.createdAt);
            if (date != 0) return date;
            final number = b.billNumber.compareTo(a.billNumber);
            return number != 0 ? number : a.uuid.compareTo(b.uuid);
          });
    final customers =
        _customers.where((c) => c.shopId == shop && query.customer(c)).toList()
          ..sort((a, b) {
            final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            return name != 0 ? name : a.uuid.compareTo(b.uuid);
          });
    for (final product in products.take(5)) {
      results.add(
        _HomeSearchResult(
          icon: Icons.inventory_2_outlined,
          color: AppColors.navy,
          title: product.name,
          subtitle: 'Product · ${product.quantityLabel} in stock',
          trailing: rupees(product.sellingPrice, decimals: 0),
          onTap: () => _openSearchProduct(product, scope),
        ),
      );
    }

    for (final bill in bills.take(5)) {
      results.add(
        _HomeSearchResult(
          icon: Icons.receipt_long_outlined,
          color: AppColors.amber,
          title: _cleanBillNumber(bill),
          subtitle: 'Bill · ${bill.customerName}',
          trailing: rupees(bill.totalAmount, decimals: 0),
          onTap: () => _openSearchBill(bill, scope),
        ),
      );
    }

    final searchPending = _buildCustomerPendingMaps(
      _bills.where((bill) => bill.shopId == shop).toList(),
    );
    for (final customer in customers.take(5)) {
      final pending =
          searchPending.byCustomerId[customer.id] ??
          searchPending.byPhone[customer.phone] ??
          0;
      results.add(
        _HomeSearchResult(
          icon: Icons.people_outline_rounded,
          color: AppColors.success,
          title: customer.name,
          subtitle:
              'Customer · ${customer.billCount} purchase${customer.billCount != 1 ? 's' : ''}',
          trailing: pending > 0
              ? 'Due ${rupees(pending, decimals: 0)}'
              : 'Paid',
          onTap: () => _openSearchCustomer(customer, scope),
        ),
      );
    }

    return results;
  }

  Future<bool> _searchScopeIsCurrent(CheckoutScope scope) async {
    if (!await isCurrentHomeSearchScope(scope)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shop changed. Search again.')),
        );
        _loadData();
      }
      return false;
    }
    return mounted;
  }

  Future<void> _openSearchProduct(Product product, CheckoutScope scope) async {
    final matches = (await DatabaseHelper.instance.getProductsForHomeSearch(
      scope.shopId,
    )).where((p) => p.uuid == product.uuid);
    if (!await _searchScopeIsCurrent(scope) || !mounted) return;
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This product is no longer available.')),
      );
      _loadData();
      return;
    }
    final fresh = matches.single;
    if (!(DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true)) {
      await showModalBottomSheet<void>(
        context: context,
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(fresh.name, style: AppText.title),
                if (fresh.itemCode != null)
                  Text('Code: ${fresh.itemCode}', style: AppText.body),
                if (fresh.barcode != null)
                  Text('Barcode: ${fresh.barcode}', style: AppText.body),
                if (fresh.category != null)
                  Text('Category: ${fresh.category}', style: AppText.body),
                Text(
                  'Selling price: ${rupees(fresh.sellingPrice)}',
                  style: AppText.body,
                ),
                Text('In stock: ${fresh.quantityLabel}', style: AppText.body),
              ],
            ),
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductsScreen(
          initialProductUuid: product.uuid,
          searchScope: scope,
        ),
      ),
    );
    if (mounted) _loadData();
  }

  Future<void> _openSearchBill(Bill bill, CheckoutScope scope) async {
    final db = DatabaseHelper.instance;
    final fresh = bill.id == null ? null : await db.getBillById(bill.id!);
    if (!await _searchScopeIsCurrent(scope) || !mounted) return;
    if (fresh == null ||
        fresh.uuid != bill.uuid ||
        fresh.shopId != scope.shopId ||
        fresh.deletedAt != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This invoice is no longer available.')),
      );
      _loadData();
      return;
    }
    if (await showBillQuickSheet(context, fresh) && mounted) _loadData();
  }

  Future<void> _openSearchCustomer(
    Customer customer,
    CheckoutScope scope,
  ) async {
    if (!await _searchScopeIsCurrent(scope) || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomersScreen(
          initialCustomerUuid: customer.uuid,
          searchScope: scope,
        ),
      ),
    );
    if (mounted) _loadData();
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

  void _openExpenses() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ExpensesScreen()),
    );
  }

  Future<void> _openSuppliers() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SuppliersScreen()));
    // Refresh the supplier count after returning (a supplier may be added).
    if (mounted) _loadData();
  }

  Future<void> _openCustomers() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const CustomersScreen()));
    if (mounted) _loadData();
  }

  Future<void> _openPricing() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PricingScreen()));
    if (mounted) _loadData();
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
        key: const ValueKey('home-global-search'),
        controller: controller,
        maxLength: 60,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        cursorColor: AppColors.amber,
        decoration: InputDecoration(
          counterText: '',
          isCollapsed: true,
          filled: false,
          hintText: context.l10n.searchEverything,
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
              leading: LeadingIconChip(icon: result.icon, color: result.color),
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

// ── Hidden section strip ──────────────────────────────────────────────────────

/// Slim placeholder shown in place of a hidden home section so the user always
/// has a way to bring it back. Replaces the previous behaviour where hiding a
/// section also removed its only "unhide" control.
class _HiddenSectionStrip extends StatelessWidget {
  final String title;
  final VoidCallback onShow;

  const _HiddenSectionStrip({required this.title, required this.onShow});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 18,
            color: AppColors.inkMutedOf(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$title hidden',
              style: AppText.body.copyWith(
                color: AppColors.inkMutedOf(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onShow,
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Show'),
          ),
        ],
      ),
    );
  }
}

// ── Workspace Shortcuts ───────────────────────────────────────────────────────

class _WorkspaceShortcutsSection extends StatelessWidget {
  final int customerCount;
  final VoidCallback onCustomers;
  final int supplierCount;
  final VoidCallback onSuppliers;
  final VoidCallback onPricing;
  final VoidCallback onExpenses;

  const _WorkspaceShortcutsSection({
    required this.customerCount,
    required this.onCustomers,
    required this.supplierCount,
    required this.onSuppliers,
    required this.onPricing,
    required this.onExpenses,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: context.l10n.workspace),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            _WorkspaceTile(
              icon: Icons.people_outline_rounded,
              label: context.l10n.customers,
              subtitle: context.l10n.savedCount(customerCount),
              color: AppColors.inkMutedOf(context),
              onTap: onCustomers,
            ),
            const SizedBox(width: AppSpacing.sm),
            _WorkspaceTile(
              icon: Icons.handshake_outlined,
              label: context.l10n.suppliers,
              subtitle: context.l10n.savedCount(supplierCount),
              color: AppColors.inkMutedOf(context),
              onTap: onSuppliers,
            ),
            const SizedBox(width: AppSpacing.sm),
            _WorkspaceTile(
              icon: Icons.sell_outlined,
              label: context.l10n.pricing,
              subtitle: context.l10n.gstAndRates,
              color: AppColors.inkMutedOf(context),
              onTap: onPricing,
            ),
            const SizedBox(width: AppSpacing.sm),
            _WorkspaceTile(
              icon: Icons.account_balance_wallet_outlined,
              label: context.l10n.expenses,
              subtitle: context.l10n.rentSalary,
              color: AppColors.inkMutedOf(context),
              onTap: onExpenses,
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
      color: AppColors.isDark(context)
          ? AppColors.darkSurfaceRaised
          : AppColors.navy,
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
                  context.l10n.todaysBookedSales,
                  style: AppText.label.copyWith(
                    color: Colors.white60,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  rupees(sales),
                  style: AppText.display.copyWith(
                    color: Colors.white,
                    fontSize: 30,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  billCount == 0
                      ? context.l10n.noBillsToday
                      : context.l10n.collectedBills(
                          rupees(collected),
                          billCount,
                        ),
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
  final VoidCallback onProducts;
  final VoidCallback onBills;

  const _StatsRow({
    required this.productCount,
    required this.billCount,
    required this.onProducts,
    required this.onBills,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: context.l10n.navProducts,
            value: '$productCount',
            subtitle: 'in catalog',
            icon: Icons.inventory_2_outlined,
            onTap: onProducts,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatTile(
            label: context.l10n.billsToday,
            value: '$billCount',
            subtitle: 'transactions',
            icon: Icons.receipt_long_outlined,
            onTap: onBills,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value, subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const _StatTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.bgOf(context),
              borderRadius: AppRadius.smRadius,
            ),
            child: Icon(icon, size: 16, color: AppColors.inkMutedOf(context)),
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

class _FirstInvoiceGuide extends StatelessWidget {
  final bool hasProduct;
  final VoidCallback onAddProduct;
  final VoidCallback onInvoice;
  const _FirstInvoiceGuide({
    required this.hasProduct,
    required this.onAddProduct,
    required this.onInvoice,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    key: const ValueKey('onboarding-guidance'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Get your shop ready', style: AppText.subtitle),
        const SizedBox(height: AppSpacing.sm),
        Text(
          hasProduct
              ? 'Pick products, choose payment and review the invoice before saving.'
              : 'Start with a name, selling price and opening stock. You can bill offline.',
          style: AppText.caption,
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: ValueKey(
            hasProduct ? 'onboarding-first-invoice' : 'onboarding-add-product',
          ),
          onPressed: hasProduct ? onInvoice : onAddProduct,
          icon: Icon(
            hasProduct ? Icons.receipt_long_outlined : Icons.add_rounded,
          ),
          label: Text(
            hasProduct ? 'Create your first invoice' : 'Add your first product',
          ),
        ),
      ],
    ),
  );
}

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
        SectionHeader(title: context.l10n.quickActions),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            _QuickActionTile(
              testId: TestKeys.homeScanBillBtn,
              icon: Icons.qr_code_scanner_rounded,
              label: context.l10n.scanAndBill,
              color: AppColors.amber,
              filled: false,
              onTap: onScan,
            ),
            const SizedBox(width: AppSpacing.sm),
            _QuickActionTile(
              testId: TestKeys.homeAddProductBtn,
              icon: Icons.add_rounded,
              label: context.l10n.addProduct,
              color: AppColors.amber,
              filled: false,
              onTap: onAddProduct,
            ),
            const SizedBox(width: AppSpacing.sm),
            _QuickActionTile(
              icon: Icons.grid_view_rounded,
              label: context.l10n.labels,
              color: AppColors.amber,
              filled: false,
              onTap: onQrSheet,
            ),
            const SizedBox(width: AppSpacing.sm),
            _QuickActionTile(
              icon: Icons.bar_chart_rounded,
              label: context.l10n.reports,
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
  final String? testId;

  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.filled,
    required this.onTap,
    this.testId,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TestKeys.tag(
        testId ?? 'btn_quick_${label.toLowerCase().replaceAll(' ', '_')}',
        GestureDetector(
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
                    color: filled
                        ? Colors.transparent
                        : AppColors.borderOf(context),
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
                  color: AppColors.inkOf(context),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        button: true,
      ),
    );
  }
}

// ── Unpaid Bills Section ─────────────────────────────────────────────────────

class _UnpaidBillsSection extends StatelessWidget {
  final List<Bill> bills;
  final ValueChanged<Bill> onTap;
  const _UnpaidBillsSection({required this.bills, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (bills.isEmpty) {
      return _EmptyState(
        icon: Icons.task_alt_rounded,
        message: context.l10n.allBillsPaid,
      );
    }
    return CompactListCard(
      rows: bills
          .map(
            (bill) => CompactListRow(
              onTap: () => onTap(bill),
              leading: const LeadingIconChip(
                icon: Icons.pending_actions_outlined,
                color: AppColors.error,
              ),
              title: bill.customerName.isEmpty
                  ? context.l10n.walkIn
                  : bill.customerName,
              subtitle:
                  '${_cleanBillNumber(bill)} · '
                  '${context.l10n.itemCount(bill.itemCount)}',
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rupees(bill.balanceDue, decimals: 0),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.inkOf(context),
                    ),
                  ),
                  bill.paymentStatus == Bill.statusPartial
                      ? StatusPill(
                          label: context.l10n.partial,
                          variant: PillVariant.warning,
                        )
                      : StatusPill(
                          label: context.l10n.unpaid,
                          variant: PillVariant.unpaid,
                        ),
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
        message: context.l10n.allStockedUp,
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
            hintText: context.l10n.searchItems,
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
            child: Text(context.l10n.cancel),
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
            child: Text(context.l10n.save),
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
          Icon(icon, size: 20, color: AppColors.inkFaintOf(context)),
          const SizedBox(width: AppSpacing.sm),
          Text(
            message,
            style: AppText.caption.copyWith(
              color: AppColors.inkMutedOf(context),
            ),
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

class _CustomerPendingMaps {
  final Map<int, double> byCustomerId;
  final Map<String, double> byPhone;

  const _CustomerPendingMaps({
    required this.byCustomerId,
    required this.byPhone,
  });
}
