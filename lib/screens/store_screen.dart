import 'package:flutter/material.dart';
import '../config/cloud_defaults.dart';
import '../db/database_helper.dart';
import '../theme/app_theme.dart';
import '../utils/test_keys.dart';
import '../models/bill_settings.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/pricing.dart';
import '../models/shop_profile.dart';
import '../models/supplier.dart';
import '../services/app_lock_service.dart';
import '../services/cloud_service.dart';
import '../services/app_settings_service.dart';
import 'analytics_screen.dart';
import 'about_app_screen.dart';
import 'privacy_policy_screen.dart';
import 'customers_screen.dart';
import 'suppliers_screen.dart';
import 'store/bill_settings_screen.dart';

part 'store/store_panels.dart';
part 'store/cloud_setup_sheet.dart';
part 'store/members_sheet.dart';
part 'store/store_action_widgets.dart';
part 'store/pricing_settings_sheets.dart';
part 'store/profile_sheets.dart';
part 'store/store_dialogs.dart';
part 'store/app_settings_sheet.dart';

class StoreScreen extends StatefulWidget {
  final int refreshToken;

  const StoreScreen({super.key, this.refreshToken = 0});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  String? _shopName;
  ShopProfile? _shopProfile;
  List<String> _categories = [];
  List<String> _suppliers = [];
  List<SupplierProfile> _supplierProfiles = [];
  List<String> _units = [];
  List<Customer> _customers = [];
  GlobalPricingSettings _pricingSettings = const GlobalPricingSettings();
  InvoiceSeriesSettings _invoiceSeriesSettings = const InvoiceSeriesSettings();
  int _lowStockThreshold = 5;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStoreData();
  }

  @override
  void didUpdateWidget(covariant StoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadStoreData();
    }
  }

  Future<void> _loadStoreData() async {
    final db = DatabaseHelper.instance;
    final shopProfile = await db.getShopProfile();
    final shopName = shopProfile?.name;
    final categories = await db.getCategories();
    final supplierProfiles = await db.getSupplierProfiles();
    final suppliers = supplierProfiles
        .map((supplier) => supplier.name)
        .toList();
    final units = await db.getUnits();
    final customers = await db.getAllCustomers();
    final pricingSettings = await db.getGlobalPricingSettings();
    final invoiceSeriesSettings = await db.getDefaultInvoiceSeriesSettings();
    final lowStockThreshold = await db.getLowStockThreshold();
    if (!mounted) return;
    setState(() {
      _shopName = shopName;
      _shopProfile = shopProfile;
      _categories = categories;
      _suppliers = suppliers;
      _supplierProfiles = supplierProfiles;
      _units = units;
      _customers = customers;
      _pricingSettings = pricingSettings;
      _invoiceSeriesSettings = invoiceSeriesSettings;
      _lowStockThreshold = lowStockThreshold;
      _isLoading = false;
    });
  }

  Future<void> _editShopProfile() async {
    final value = await showModalBottomSheet<ShopProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShopProfileSheet(
        profile:
            _shopProfile ??
            ShopProfile(
              name: _shopName ?? '',
              gstRegistered: _pricingSettings.gstRegistered,
            ),
      ),
    );
    if (value == null) return;
    await _runStoreAction(() async {
      await DatabaseHelper.instance.saveShopProfile(value);
      await DatabaseHelper.instance.refreshAllProductSellingPrices();
    });
  }

  Future<void> _addCategory() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) =>
          const _NameDialog(title: 'Add Category', label: 'Category Name'),
    );
    if (value == null) return;
    await _runStoreAction(
      () => DatabaseHelper.instance.addCategoryOption(value),
    );
  }

  Future<void> _editCategory(String currentName) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Update Category',
        label: 'Category Name',
        initialValue: currentName,
      ),
    );
    if (value == null) return;
    await _runStoreAction(
      () => DatabaseHelper.instance.updateCategoryOption(currentName, value),
    );
  }

  Future<void> _deleteCategory(String name) async {
    final confirmed = await _confirmDelete('Category', name);
    if (!confirmed) return;
    await _runStoreAction(
      () => DatabaseHelper.instance.deleteCategoryOption(name),
    );
  }

  Future<void> _editLowStockThreshold() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _NumberDialog(
        title: 'Needs Attention',
        label: 'Minimum Stock',
        initialValue: _lowStockThreshold,
      ),
    );
    if (value == null) return;
    await _runStoreAction(
      () => DatabaseHelper.instance.saveLowStockThreshold(value),
    );
  }

  void _openPrivacyPolicy() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
    );
  }

  void _openAboutApp() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AboutAppScreen()),
    );
  }

  void _openAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
    );
  }

  Future<void> _showAppSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AppSettingsSheet(),
    );
  }

  Future<void> _showCustomerTable() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CustomersScreen()),
    );
    if (mounted) await _loadStoreData();
  }

  Future<void> _showCategoryManager() {
    return _showOptionManager(
      title: 'Categories',
      emptyText: 'No categories yet',
      icon: Icons.category_outlined,
      loadOptions: DatabaseHelper.instance.getCategories,
      onAdd: _addCategory,
      onEdit: _editCategory,
      onDelete: _deleteCategory,
    );
  }

  Future<void> _showGlobalPricingSettings() async {
    final result = await showModalBottomSheet<GlobalPricingSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _GlobalPricingSheet(settings: _pricingSettings, units: _units),
    );
    if (result == null) return;
    await _runStoreAction(() async {
      await DatabaseHelper.instance.saveGlobalPricingSettings(result);
      await DatabaseHelper.instance.refreshAllProductSellingPrices();
    });
  }

  Future<void> _showBillSettings() async {
    // The full-page editor loads and saves its own data; it pops `true` when
    // changes were persisted so we just reload to reflect them here.
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const BillSettingsScreen()),
    );
    if (saved == true && mounted) await _loadStoreData();
  }

  Future<void> _showCategoryPricing(String name) async {
    final current =
        await DatabaseHelper.instance.getCategoryPricing(name) ??
        CategoryPricingSettings(name: name);
    if (!mounted) return;
    final result = await showModalBottomSheet<CategoryPricingSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CategoryPricingSheet(settings: current, global: _pricingSettings),
    );
    if (result == null) return;
    await _runStoreAction(() async {
      await DatabaseHelper.instance.saveCategoryPricing(result);
      await DatabaseHelper.instance.refreshAllProductSellingPrices();
    });
  }

  Future<void> _showSupplierManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SuppliersScreen()),
    );
    if (mounted) await _loadStoreData();
  }

  Future<void> _showOptionManager({
    required String title,
    required String emptyText,
    required IconData icon,
    required Future<List<String>> Function() loadOptions,
    required Future<void> Function() onAdd,
    required Future<void> Function(String value) onEdit,
    required Future<void> Function(String value) onDelete,
  }) async {
    var options = await loadOptions();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> refreshSheet() async {
            options = await loadOptions();
            if (ctx.mounted) setSheet(() {});
          }

          Future<void> runAndRefresh(Future<void> Function() action) async {
            await action();
            await refreshSheet();
          }

          final isDark = AppColors.isDark(ctx);
          return SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
              ),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(ctx),
                borderRadius: BorderRadius.circular(24),
                border: isDark
                    ? Border.all(color: AppColors.borderOf(ctx))
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrongOf(ctx),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _PanelIcon(icon: icon),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: AppColors.brandOf(ctx),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        onPressed: () => runAndRefresh(onAdd),
                        icon: const Icon(Icons.add_rounded),
                        tooltip: 'Add $title',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: options.isEmpty
                        ? Center(
                            child: Text(
                              emptyText,
                              style: TextStyle(
                                color: AppColors.inkMutedOf(ctx),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (_, index) {
                              final name = options[index];
                              return _OptionRow(
                                name: name,
                                onSettings: title == 'Categories'
                                    ? () => runAndRefresh(
                                        () => _showCategoryPricing(name),
                                      )
                                    : null,
                                onEdit: () => runAndRefresh(() => onEdit(name)),
                                onDelete: () =>
                                    runAndRefresh(() => onDelete(name)),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<bool> _confirmDelete(String label, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: AppColors.error),
        title: Text('Delete $label'),
        content: Text('Remove "$name"? Products using it will be cleared.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _runStoreAction(Future<void> Function() action) async {
    try {
      await action();
      await _loadStoreData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Invalid argument: ', '')),
        ),
      );
    }
  }

  Future<void> _openCloudSetup() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CloudSetupSheet(),
    );
    await _loadStoreData();
  }

  Future<void> _syncCloud() async {
    await CloudService.instance.syncNow(reason: 'Manual sync');
    await _loadStoreData();
  }

  Future<void> _openMembers() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MembersSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Store'),
        actions: const [
          AppInfoAction(
            title: 'Store Help',
            intro:
                'Store is where you set the business rules used by products, bills, and sync.',
            sections: [
              AppInfoSection(
                title: 'Before daily use',
                points: [
                  'Fill Shop Profile first so bills show the right business details.',
                  'Add suppliers before purchases if you want supplier-wise stock history.',
                  'Set Pricing Defaults before importing products that use automatic pricing.',
                ],
              ),
              AppInfoSection(
                title: 'Settings',
                points: [
                  'Bill Settings controls invoice numbering, logo, signature, footer, and visible bill fields.',
                  'Needs Attention controls the low-stock warning threshold.',
                  'Cloud Sync is optional and should be configured only by the shop owner or admin.',
                ],
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppColors.amber,
              onRefresh: _loadStoreData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  112,
                ),
                children: [
                  ValueListenableBuilder<CloudState>(
                    valueListenable: CloudService.instance.state,
                    builder: (context, cloudState, _) => _ShopPanel(
                      profile: _shopProfile,
                      gstRegistered: _pricingSettings.gstRegistered,
                      onEdit: cloudState.isAdmin ? _editShopProfile : null,
                      roleLabel:
                          cloudState.isConfigured && cloudState.isSignedIn
                          ? cloudState.shopRole
                          : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _SectionLabel(title: 'Settings Configuration'),
                  const SizedBox(height: AppSpacing.sm),
                  _StoreActionRow(
                    title: 'Categories',
                    subtitle: '${_categories.length} saved',
                    icon: Icons.category_outlined,
                    onTap: _showCategoryManager,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StoreActionRow(
                    title: 'Suppliers',
                    subtitle:
                        '${_suppliers.length} saved${_supplierProfiles.any((supplier) => supplier.phone != null || supplier.email != null || supplier.gstin != null) ? ' • profiles enabled' : ''}',
                    icon: Icons.local_shipping_outlined,
                    onTap: _showSupplierManager,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StoreActionRow(
                    title: 'Pricing Defaults',
                    subtitle:
                        'GST ${_pricingSettings.defaultGstPercent.toStringAsFixed(2)}% • Margin ${_pricingSettings.defaultProfitMarginPercent.toStringAsFixed(2)}%',
                    icon: Icons.calculate_outlined,
                    onTap: _showGlobalPricingSettings,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StoreActionRow(
                    title: 'Bill Settings',
                    subtitle: _invoiceSeriesSettings.formatTemplate,
                    icon: Icons.receipt_long_outlined,
                    onTap: _showBillSettings,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StoreActionRow(
                    title: 'Needs Attention',
                    subtitle: 'Show stock at $_lowStockThreshold or below',
                    icon: Icons.inventory_rounded,
                    onTap: _editLowStockThreshold,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StoreActionRow(
                    title: 'Customers',
                    subtitle: '${_customers.length} saved',
                    icon: Icons.people_outline_rounded,
                    onTap: _showCustomerTable,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StoreActionRow(
                    title: 'Analytics',
                    subtitle: 'Revenue, profit, GST and unit volume',
                    icon: Icons.analytics_outlined,
                    onTap: _openAnalytics,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AnimatedBuilder(
                    animation: AppSettingsService.instance,
                    builder: (context, _) => _StoreActionRow(
                      title: 'App Settings',
                      subtitle:
                          'Theme: ${AppSettingsService.instance.themePreference.label} • Lock: ${AppSettingsService.instance.appLockEnabled ? 'On' : 'Off'}',
                      icon: Icons.settings_outlined,
                      onTap: _showAppSettings,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _SectionLabel(title: 'Account'),
                  const SizedBox(height: AppSpacing.sm),
                  _AccountSection(
                    onSetup: _openCloudSetup,
                    onSync: _syncCloud,
                    onMembers: _openMembers,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _SectionLabel(title: 'Legal & App Information'),
                  const SizedBox(height: AppSpacing.sm),
                  _StoreActionRow(
                    title: 'Privacy policy',
                    subtitle: 'Privacy policy and data usage details',
                    icon: Icons.privacy_tip_outlined,
                    onTap: _openPrivacyPolicy,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StoreActionRow(
                    title: 'About',
                    subtitle: 'App information and version 1.0.4',
                    icon: Icons.info_outline_rounded,
                    onTap: _openAboutApp,
                  ),
                ],
              ),
            ),
    );
  }
}
