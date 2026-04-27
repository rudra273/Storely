import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../main.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/pricing.dart';
import '../models/shop_profile.dart';
import '../models/supplier.dart';
import '../services/cloud_service.dart';
import 'analytics_screen.dart';
import 'about_app_screen.dart';
import 'privacy_policy_screen.dart';

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

  Future<void> _addSupplier() async {
    final value = await showModalBottomSheet<SupplierProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SupplierProfileSheet(),
    );
    if (value == null) return;
    await _runStoreAction(
      () => DatabaseHelper.instance.saveSupplierProfile(value),
    );
  }

  Future<void> _editSupplier(String currentName) async {
    final current =
        await DatabaseHelper.instance.getSupplierProfile(currentName) ??
        SupplierProfile(name: currentName);
    if (!mounted) return;
    final value = await showModalBottomSheet<SupplierProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplierProfileSheet(supplier: current),
    );
    if (value == null) return;
    await _runStoreAction(
      () => DatabaseHelper.instance.saveSupplierProfile(
        value,
        oldName: currentName,
      ),
    );
  }

  Future<void> _deleteSupplier(String name) async {
    final confirmed = await _confirmDelete('Supplier', name);
    if (!confirmed) return;
    await _runStoreAction(
      () => DatabaseHelper.instance.deleteSupplierOption(name),
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

  Future<void> _showCustomerTable() async {
    var customers = await DatabaseHelper.instance.getAllCustomers();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> refreshSheet() async {
            customers = await DatabaseHelper.instance.getAllCustomers();
            if (ctx.mounted) setSheet(() {});
          }

          Future<void> saveCustomer(Customer? current) async {
            final result = await showModalBottomSheet<Customer>(
              context: ctx,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => _CustomerProfileSheet(customer: current),
            );
            if (result == null) return;
            await DatabaseHelper.instance.saveCustomerProfile(result);
            await refreshSheet();
            await _loadStoreData();
          }

          return _CustomerTableSheet(
            customers: customers,
            onAdd: () => saveCustomer(null),
            onEdit: saveCustomer,
          );
        },
      ),
    );
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
    var suppliers = await DatabaseHelper.instance.getSupplierProfiles();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> refreshSheet() async {
            suppliers = await DatabaseHelper.instance.getSupplierProfiles();
            if (ctx.mounted) setSheet(() {});
          }

          Future<void> runAndRefresh(Future<void> Function() action) async {
            await action();
            await refreshSheet();
          }

          return _SupplierManagerSheet(
            suppliers: suppliers,
            onAdd: () => runAndRefresh(_addSupplier),
            onEdit: (supplier) =>
                runAndRefresh(() => _editSupplier(supplier.name)),
            onDelete: (supplier) =>
                runAndRefresh(() => _deleteSupplier(supplier.name)),
          );
        },
      ),
    );
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

          return SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
              ),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.creamDark,
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
                          style: const TextStyle(
                            color: AppColors.navy,
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
                              style: const TextStyle(
                                color: AppColors.textMuted,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text(
          'Store',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStoreData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  ValueListenableBuilder<CloudState>(
                    valueListenable: CloudService.instance.state,
                    builder: (context, cloudState, _) => _ShopPanel(
                      profile: _shopProfile,
                      gstRegistered: _pricingSettings.gstRegistered,
                      onEdit: cloudState.isAdmin ? _editShopProfile : null,
                      roleLabel: cloudState.isConfigured && cloudState.isSignedIn
                          ? cloudState.shopRole
                          : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _CloudSyncPanel(onSetup: _openCloudSetup, onSync: _syncCloud),
                  const SizedBox(height: 10),
                  _StoreActionRow(
                    title: 'Categories',
                    subtitle: '${_categories.length} saved',
                    icon: Icons.category_outlined,
                    onTap: _showCategoryManager,
                  ),
                  const SizedBox(height: 10),
                  _StoreActionRow(
                    title: 'Suppliers',
                    subtitle:
                        '${_suppliers.length} saved${_supplierProfiles.any((supplier) => supplier.phone != null || supplier.email != null || supplier.gstin != null) ? ' • profiles enabled' : ''}',
                    icon: Icons.local_shipping_outlined,
                    onTap: _showSupplierManager,
                  ),
                  const SizedBox(height: 10),
                  _StoreActionRow(
                    title: 'Pricing Defaults',
                    subtitle:
                        'GST ${_pricingSettings.defaultGstPercent.toStringAsFixed(2)}% • Margin ${_pricingSettings.defaultProfitMarginPercent.toStringAsFixed(2)}%',
                    icon: Icons.calculate_outlined,
                    onTap: _showGlobalPricingSettings,
                  ),
                  const SizedBox(height: 10),
                  _StoreActionRow(
                    title: 'Needs Attention',
                    subtitle: 'Show stock at $_lowStockThreshold or below',
                    icon: Icons.inventory_rounded,
                    onTap: _editLowStockThreshold,
                  ),
                  const SizedBox(height: 10),
                  _StoreActionRow(
                    title: 'Customers',
                    subtitle: '${_customers.length} saved',
                    icon: Icons.people_outline_rounded,
                    onTap: _showCustomerTable,
                  ),
                  const SizedBox(height: 10),
                  _StoreActionRow(
                    title: 'Analytics',
                    subtitle: 'Revenue, profit, GST and unit volume',
                    icon: Icons.analytics_outlined,
                    onTap: _openAnalytics,
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel(title: 'Legal & App Information'),
                  const SizedBox(height: 10),
                  _StoreActionRow(
                    title: 'Privacy policy',
                    subtitle: 'Privacy policy and data usage details',
                    icon: Icons.privacy_tip_outlined,
                    onTap: _openPrivacyPolicy,
                  ),
                  const SizedBox(height: 10),
                  _StoreActionRow(
                    title: 'About',
                    subtitle: 'App information and version 1.0.0',
                    icon: Icons.info_outline_rounded,
                    onTap: _openAboutApp,
                  ),
                ],
              ),
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: AppColors.textMuted,
        ),
      ),
    );
  }
}

class _CloudSyncPanel extends StatelessWidget {
  final VoidCallback onSetup;
  final Future<void> Function() onSync;

  const _CloudSyncPanel({required this.onSetup, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, state, _) {
        final email = state.user?.email;
        final role = state.shopRole;
        final roleStr = role != null ? ' (${role[0].toUpperCase()}${role.substring(1)})' : '';
        final subtitle = !state.isConfigured
            ? 'Local only'
            : email == null
            ? 'Configured • sign in to sync'
            : 'Signed in as $email$roleStr';
        final lastSync = state.lastSyncedAt == null
            ? null
            : _formatCloudTime(state.lastSyncedAt!.toLocal());
        return _StorePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _PanelIcon(icon: Icons.cloud_sync_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cloud Sync',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lastSync == null ? subtitle : '$subtitle • $lastSync',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cloud setup',
                    onPressed: onSetup,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  IconButton(
                    tooltip: 'Sync now',
                    onPressed:
                        state.isConfigured &&
                            state.isSignedIn &&
                            !state.isSyncing
                        ? onSync
                        : null,
                    icon: state.isSyncing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                  ),
                ],
              ),
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ] else if (state.message != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.message!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CloudSetupSheet extends StatefulWidget {
  const _CloudSetupSheet();

  @override
  State<_CloudSetupSheet> createState() => _CloudSetupSheetState();
}

class _CloudSetupSheetState extends State<_CloudSetupSheet> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _anonKeyCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;
  late bool _editingCloudSettings;
  bool _isBusy = false;
  String? _sheetError;
  String? _sheetMessage;

  @override
  void initState() {
    super.initState();
    final config = CloudService.instance.state.value.config;
    _editingCloudSettings = config == null;
    _urlCtrl = TextEditingController(text: config?.url ?? '');
    _anonKeyCtrl = TextEditingController(text: config?.anonKey ?? '');
    _emailCtrl = TextEditingController(
      text: CloudService.instance.state.value.user?.email ?? '',
    );
    _passwordCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _anonKeyCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? successMessage,
    VoidCallback? onSuccess,
  }) async {
    setState(() {
      _isBusy = true;
      _sheetError = null;
      _sheetMessage = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _sheetMessage = successMessage;
      });
      onSuccess?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _sheetError = _cleanCloudError(error);
      });
    }
  }

  Future<void> _saveConfig() {
    return _run(
      () => CloudService.instance.saveConfig(
        CloudConfig(url: _urlCtrl.text, anonKey: _anonKeyCtrl.text),
      ),
      successMessage: 'Cloud settings saved',
      onSuccess: () => setState(() => _editingCloudSettings = false),
    );
  }

  Future<void> _signIn() {
    return _run(
      () => CloudService.instance.signIn(_emailCtrl.text, _passwordCtrl.text),
      successMessage: 'Signed in. Sync will run automatically.',
    );
  }

  Future<void> _signUp() {
    return _run(
      () => CloudService.instance.signUp(_emailCtrl.text, _passwordCtrl.text),
      successMessage: 'Account created. Check email confirmation if required.',
    );
  }

  Future<void> _signOut() =>
      _run(CloudService.instance.signOut, successMessage: 'Signed out');

  Future<void> _disableCloud() => _run(
    CloudService.instance.clearConfig,
    successMessage: 'Cloud sync disabled',
    onSuccess: () {
      setState(() => _editingCloudSettings = true);
      _urlCtrl.clear();
      _anonKeyCtrl.clear();
    },
  );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, state, _) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        height: 4,
                        width: 42,
                        decoration: BoxDecoration(
                          color: AppColors.creamDark,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Cloud Sync',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (state.isConfigured && !_editingCloudSettings) ...[
                      _CloudConfiguredSummary(config: state.config!),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isBusy
                              ? null
                              : () => setState(
                                  () => _editingCloudSettings = true,
                                ),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Update Cloud Settings'),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: _urlCtrl,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(
                          labelText: 'Supabase URL',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _anonKeyCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Supabase anon key',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isBusy ? null : _saveConfig,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            state.isConfigured
                                ? 'Save Updated Settings'
                                : 'Save Cloud Settings',
                          ),
                        ),
                      ),
                    ],
                    if (_sheetError != null) ...[
                      const SizedBox(height: 10),
                      _CloudStatusMessage(text: _sheetError!, isError: true),
                    ] else if (_sheetMessage != null) ...[
                      const SizedBox(height: 10),
                      _CloudStatusMessage(text: _sheetMessage!),
                    ] else if (state.error != null) ...[
                      const SizedBox(height: 10),
                      _CloudStatusMessage(text: state.error!, isError: true),
                    ],
                    const SizedBox(height: 18),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isBusy || !state.isConfigured
                                ? null
                                : _signIn,
                            icon: const Icon(Icons.login_rounded),
                            label: const Text('Sign In'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isBusy || !state.isConfigured
                                ? null
                                : _signUp,
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Sign Up'),
                          ),
                        ),
                      ],
                    ),
                    if (state.isSignedIn) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isBusy ? null : _signOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign Out'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _isBusy || !state.isConfigured
                          ? null
                          : _disableCloud,
                      icon: const Icon(Icons.cloud_off_outlined),
                      label: const Text('Disable Cloud Sync'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CloudConfiguredSummary extends StatelessWidget {
  final CloudConfig config;

  const _CloudConfiguredSummary({required this.config});

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(config.url)?.host;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.creamDark),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              host == null || host.isEmpty ? 'Cloud settings saved' : host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudStatusMessage extends StatelessWidget {
  final String text;
  final bool isError;

  const _CloudStatusMessage({required this.text, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isError ? AppColors.error : AppColors.success,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _cleanCloudError(Object error) {
  final value = error.toString();
  return value
      .replaceFirst('AuthException(message: ', '')
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('StorageException(message: ', '')
      .replaceFirst('Exception: ', '')
      .replaceFirst('Invalid argument: ', '')
      .replaceAll(RegExp(r', statusCode:.*\)$'), '')
      .replaceAll(RegExp(r', code:.*\)$'), '')
      .trim();
}

String _formatCloudTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return 'last sync $hour:$minute';
}

String? _cleanOptional(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed.isEmpty ? null : trimmed;
}

class _ShopPanel extends StatelessWidget {
  final ShopProfile? profile;
  final bool gstRegistered;
  final VoidCallback? onEdit;
  final String? roleLabel;

  const _ShopPanel({
    required this.profile,
    required this.gstRegistered,
    required this.onEdit,
    this.roleLabel,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      if (profile?.phone != null) profile!.phone!,
      if (profile?.email != null) profile!.email!,
      if (profile?.gstin != null) 'GSTIN ${profile!.gstin}',
      gstRegistered ? 'GST registered' : 'GST not registered',
    ];
    return _StorePanel(
      child: Row(
        children: [
          const _PanelIcon(icon: Icons.storefront_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Shop',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                    if (roleLabel != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: roleLabel == 'owner' || roleLabel == 'admin'
                              ? AppColors.amber.withValues(alpha: 0.15)
                              : AppColors.navy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          roleLabel!.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: roleLabel == 'owner' || roleLabel == 'admin'
                                ? AppColors.amber
                                : AppColors.textMuted,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  profile?.name ?? 'No shop name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onEdit != null)
            IconButton.filledTonal(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded),
              tooltip: 'Edit shop profile',
            )
          else
            Tooltip(
              message: 'Only admin or owner can edit',
              child: Icon(
                Icons.lock_outline_rounded,
                color: AppColors.textMuted.withValues(alpha: 0.5),
                size: 22,
              ),
            ),
        ],
      ),
    );
  }
}

class _StoreActionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _StoreActionRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _StorePanel(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            _PanelIcon(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String name;
  final VoidCallback? onSettings;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _OptionRow({
    required this.name,
    this.onSettings,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (onSettings != null)
            IconButton(
              onPressed: onSettings,
              icon: const Icon(Icons.tune_rounded, size: 20),
              tooltip: 'Pricing',
            ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Edit',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.error,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}

class _SupplierManagerSheet extends StatelessWidget {
  final List<SupplierProfile> suppliers;
  final Future<void> Function() onAdd;
  final Future<void> Function(SupplierProfile supplier) onEdit;
  final Future<void> Function(SupplierProfile supplier) onDelete;

  const _SupplierManagerSheet({
    required this.suppliers,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.creamDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const _PanelIcon(icon: Icons.local_shipping_outlined),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Suppliers',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Add supplier',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: suppliers.isEmpty
                  ? const Center(
                      child: Text(
                        'No suppliers yet',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: suppliers.length,
                      itemBuilder: (_, index) {
                        final supplier = suppliers[index];
                        return _SupplierProfileRow(
                          supplier: supplier,
                          onEdit: () => onEdit(supplier),
                          onDelete: () => onDelete(supplier),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierProfileRow extends StatelessWidget {
  final SupplierProfile supplier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SupplierProfileRow({
    required this.supplier,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      if (supplier.phone != null) supplier.phone!,
      if (supplier.email != null) supplier.email!,
      if (supplier.gstin != null) 'GSTIN ${supplier.gstin}',
      if (supplier.address != null) supplier.address!,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplier.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Edit',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.error,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}

class _StorePanel extends StatelessWidget {
  final Widget child;

  const _StorePanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _PanelIcon extends StatelessWidget {
  final IconData icon;

  const _PanelIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      width: 38,
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: AppColors.amber),
    );
  }
}

class _GlobalPricingSheet extends StatefulWidget {
  final GlobalPricingSettings settings;
  final List<String> units;

  const _GlobalPricingSheet({required this.settings, required this.units});

  @override
  State<_GlobalPricingSheet> createState() => _GlobalPricingSheetState();
}

class _GlobalPricingSheetState extends State<_GlobalPricingSheet> {
  late final TextEditingController _gstCtrl;
  late final TextEditingController _overheadCtrl;
  late final TextEditingController _marginCtrl;
  late List<String> _units;

  @override
  void initState() {
    super.initState();
    _gstCtrl = TextEditingController(
      text: widget.settings.defaultGstPercent.toStringAsFixed(2),
    );
    _overheadCtrl = TextEditingController(
      text: widget.settings.defaultOverheadCost.toStringAsFixed(2),
    );
    _marginCtrl = TextEditingController(
      text: widget.settings.defaultProfitMarginPercent.toStringAsFixed(2),
    );
    _units = List.of(widget.units);
  }

  @override
  void dispose() {
    _gstCtrl.dispose();
    _overheadCtrl.dispose();
    _marginCtrl.dispose();
    super.dispose();
  }

  Future<void> _addUnit() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(title: 'Add Unit', label: 'Unit'),
    );
    if (value == null) return;
    await DatabaseHelper.instance.addUnitOption(value);
    final units = await DatabaseHelper.instance.getUnits();
    if (mounted) setState(() => _units = units);
  }

  Future<void> _deleteUnit(String unit) async {
    await DatabaseHelper.instance.deleteUnitOption(unit);
    final units = await DatabaseHelper.instance.getUnits();
    if (mounted) setState(() => _units = units);
  }

  void _save() {
    Navigator.pop(
      context,
      GlobalPricingSettings(
        defaultGstPercent: double.tryParse(_gstCtrl.text) ?? 0,
        defaultOverheadCost: double.tryParse(_overheadCtrl.text) ?? 0,
        defaultProfitMarginPercent: double.tryParse(_marginCtrl.text) ?? 0,
        gstRegistered: widget.settings.gstRegistered,
        showPurchasePriceGlobally: widget.settings.showPurchasePriceGlobally,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSheetFrame(
      title: 'Pricing Defaults',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MoneyField(controller: _gstCtrl, label: 'Default GST %'),
          const SizedBox(height: 10),
          _MoneyField(controller: _overheadCtrl, label: 'Default Overhead ₹'),
          const SizedBox(height: 10),
          _MoneyField(
            controller: _marginCtrl,
            label: 'Default Profit Margin %',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Custom Units',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _addUnit,
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Add unit',
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _units
                .where((unit) => !Product.presetUnits.contains(unit))
                .map(
                  (unit) => InputChip(
                    label: Text(unit),
                    onDeleted: () => _deleteUnit(unit),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
              child: const Text('Save Defaults'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryPricingSheet extends StatefulWidget {
  final CategoryPricingSettings settings;
  final GlobalPricingSettings global;

  const _CategoryPricingSheet({required this.settings, required this.global});

  @override
  State<_CategoryPricingSheet> createState() => _CategoryPricingSheetState();
}

class _CategoryPricingSheetState extends State<_CategoryPricingSheet> {
  late final TextEditingController _gstCtrl;
  late final TextEditingController _overheadCtrl;
  late final TextEditingController _marginCtrl;

  @override
  void initState() {
    super.initState();
    _gstCtrl = TextEditingController(
      text: widget.settings.gstPercent?.toStringAsFixed(2) ?? '',
    );
    _overheadCtrl = TextEditingController(
      text: widget.settings.overheadCost?.toStringAsFixed(2) ?? '',
    );
    _marginCtrl = TextEditingController(
      text: widget.settings.profitMarginPercent?.toStringAsFixed(2) ?? '',
    );
  }

  @override
  void dispose() {
    _gstCtrl.dispose();
    _overheadCtrl.dispose();
    _marginCtrl.dispose();
    super.dispose();
  }

  CategoryPricingSettings _settings() {
    return CategoryPricingSettings(
      id: widget.settings.id,
      name: widget.settings.name,
      gstPercent: double.tryParse(_gstCtrl.text),
      overheadCost: double.tryParse(_overheadCtrl.text),
      profitMarginPercent: double.tryParse(_marginCtrl.text),
      directPriceToggle: false,
      manualPrice: null,
    );
  }

  void _save() => Navigator.pop(context, _settings());

  @override
  Widget build(BuildContext context) {
    return _SettingsSheetFrame(
      title: '${widget.settings.name} Pricing',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MoneyField(
            controller: _gstCtrl,
            label: 'GST % (blank = ${widget.global.defaultGstPercent}%)',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          _MoneyField(
            controller: _overheadCtrl,
            label: 'Overhead ₹ (blank = ${widget.global.defaultOverheadCost})',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          _MoneyField(
            controller: _marginCtrl,
            label:
                'Profit Margin % (blank = ${widget.global.defaultProfitMarginPercent}%)',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
              child: const Text('Save Category Pricing'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSheetFrame extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsSheetFrame({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.creamDark,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopProfileSheet extends StatefulWidget {
  final ShopProfile profile;

  const _ShopProfileSheet({required this.profile});

  @override
  State<_ShopProfileSheet> createState() => _ShopProfileSheetState();
}

class _ShopProfileSheetState extends State<_ShopProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _gstinCtrl;
  late final TextEditingController _addressCtrl;
  late bool _gstRegistered;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _nameCtrl = TextEditingController(text: profile.name);
    _phoneCtrl = TextEditingController(text: profile.phone ?? '');
    _emailCtrl = TextEditingController(text: profile.email ?? '');
    _gstinCtrl = TextEditingController(text: profile.gstin ?? '');
    _addressCtrl = TextEditingController(text: profile.address ?? '');
    _gstRegistered = profile.gstRegistered;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _gstinCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final current = widget.profile;
    Navigator.pop(
      context,
      ShopProfile(
        id: current.id,
        uuid: current.uuid,
        name: _nameCtrl.text.trim(),
        phone: _cleanOptional(_phoneCtrl.text),
        email: _cleanOptional(_emailCtrl.text),
        gstin: _cleanOptional(_gstinCtrl.text)?.toUpperCase(),
        address: _cleanOptional(_addressCtrl.text),
        gstRegistered: _gstRegistered,
        createdAt: current.createdAt,
        updatedAt: current.updatedAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSheetFrame(
      title: 'Shop Profile',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameCtrl,
              autofocus: widget.profile.name.isEmpty,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Shop Name *',
                prefixIcon: Icon(Icons.storefront_outlined, size: 18),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined, size: 18),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return null;
                return email.contains('@') ? null : 'Invalid email';
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _gstinCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'GSTIN',
                prefixIcon: Icon(Icons.receipt_long_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _addressCtrl,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.location_on_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Shop is GST registered'),
              subtitle: Text(
                _gstRegistered
                    ? 'GST is added on selling price'
                    : 'Purchase GST is included in cost',
              ),
              value: _gstRegistered,
              activeThumbColor: AppColors.navy,
              onChanged: (value) => setState(() => _gstRegistered = value),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Save Shop'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierProfileSheet extends StatefulWidget {
  final SupplierProfile? supplier;

  const _SupplierProfileSheet({this.supplier});

  @override
  State<_SupplierProfileSheet> createState() => _SupplierProfileSheetState();
}

class _SupplierProfileSheetState extends State<_SupplierProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _gstinCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _nameCtrl = TextEditingController(text: supplier?.name ?? '');
    _phoneCtrl = TextEditingController(text: supplier?.phone ?? '');
    _emailCtrl = TextEditingController(text: supplier?.email ?? '');
    _gstinCtrl = TextEditingController(text: supplier?.gstin ?? '');
    _addressCtrl = TextEditingController(text: supplier?.address ?? '');
    _notesCtrl = TextEditingController(text: supplier?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _gstinCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final current = widget.supplier;
    Navigator.pop(
      context,
      SupplierProfile(
        id: current?.id,
        uuid: current?.uuid,
        shopId: current?.shopId ?? 'local-shop',
        name: _nameCtrl.text.trim(),
        phone: _cleanOptional(_phoneCtrl.text),
        email: _cleanOptional(_emailCtrl.text),
        gstin: _cleanOptional(_gstinCtrl.text)?.toUpperCase(),
        address: _cleanOptional(_addressCtrl.text),
        notes: _cleanOptional(_notesCtrl.text),
        deviceId: current?.deviceId,
        createdAt: current?.createdAt,
        updatedAt: current?.updatedAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.supplier != null;
    return _SettingsSheetFrame(
      title: isEditing ? 'Edit Supplier' : 'Add Supplier',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameCtrl,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Supplier Name *',
                prefixIcon: Icon(Icons.local_shipping_outlined, size: 18),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined, size: 18),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return null;
                return email.contains('@') ? null : 'Invalid email';
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _gstinCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'GSTIN',
                prefixIcon: Icon(Icons.receipt_long_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _addressCtrl,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.location_on_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(isEditing ? 'Update Supplier' : 'Add Supplier'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;

  const _MoneyField({
    required this.controller,
    required this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _NameDialog extends StatefulWidget {
  final String title;
  final String label;
  final String? initialValue;

  const _NameDialog({
    required this.title,
    required this.label,
    this.initialValue,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final value = _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: widget.label),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Required' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _NumberDialog extends StatefulWidget {
  final String title;
  final String label;
  final int initialValue;

  const _NumberDialog({
    required this.title,
    required this.label,
    required this.initialValue,
  });

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(context, int.parse(_controller.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: widget.label,
            suffixText: 'units',
          ),
          validator: (value) {
            final number = int.tryParse(value ?? '');
            if (number == null) return 'Enter a number';
            if (number < 0) return 'Cannot be negative';
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _CustomerTableSheet extends StatefulWidget {
  final List<Customer> customers;
  final Future<void> Function() onAdd;
  final Future<void> Function(Customer customer) onEdit;

  const _CustomerTableSheet({
    required this.customers,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  State<_CustomerTableSheet> createState() => _CustomerTableSheetState();
}

class _CustomerTableSheetState extends State<_CustomerTableSheet> {
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
          (customer.email?.toLowerCase().contains(query) ?? false) ||
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
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.creamDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const _PanelIcon(icon: Icons.people_outline_rounded),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Customers',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: widget.onAdd,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Add customer',
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Search customers',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: customers.isEmpty
                  ? const Center(
                      child: Text(
                        'No matching customers',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 38,
                        dataRowMinHeight: 44,
                        dataRowMaxHeight: 54,
                        columnSpacing: 22,
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Email')),
                          DataColumn(numeric: true, label: Text('Bills')),
                          DataColumn(numeric: true, label: Text('Total')),
                          DataColumn(label: Text('')),
                        ],
                        rows: customers
                            .map(
                              (customer) => DataRow(
                                cells: [
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 150,
                                      ),
                                      child: Text(
                                        customer.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(_displayPhone(customer.phone))),
                                  DataCell(Text(customer.email ?? '-')),
                                  DataCell(Text('${customer.billCount}')),
                                  DataCell(
                                    Text(
                                      '₹${customer.totalPurchaseAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    IconButton(
                                      onPressed: () => widget.onEdit(customer),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 19,
                                      ),
                                      tooltip: 'Edit customer',
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _displayPhone(String phone) {
    if (phone.length == 12 && phone.startsWith('91')) {
      return '+91 ${phone.substring(2, 7)} ${phone.substring(7)}';
    }
    return phone;
  }
}

class _CustomerProfileSheet extends StatefulWidget {
  final Customer? customer;

  const _CustomerProfileSheet({this.customer});

  @override
  State<_CustomerProfileSheet> createState() => _CustomerProfileSheetState();
}

class _CustomerProfileSheetState extends State<_CustomerProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _nameCtrl = TextEditingController(text: customer?.name ?? '');
    _phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    _emailCtrl = TextEditingController(text: customer?.email ?? '');
    _addressCtrl = TextEditingController(text: customer?.address ?? '');
    _notesCtrl = TextEditingController(text: customer?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final current = widget.customer;
    Navigator.pop(
      context,
      Customer(
        id: current?.id,
        uuid: current?.uuid ?? '',
        shopId: current?.shopId ?? 'local-shop',
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _cleanOptional(_emailCtrl.text),
        address: _cleanOptional(_addressCtrl.text),
        notes: _cleanOptional(_notesCtrl.text),
        totalPurchaseAmount: current?.totalPurchaseAmount ?? 0,
        billCount: current?.billCount ?? 0,
        lastPurchaseAt: current?.lastPurchaseAt,
        deviceId: current?.deviceId,
        createdAt: current?.createdAt ?? DateTime.now(),
        updatedAt: current?.updatedAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.customer != null;
    return _SettingsSheetFrame(
      title: isEditing ? 'Edit Customer' : 'Add Customer',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameCtrl,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined, size: 18),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return null;
                return email.contains('@') ? null : 'Invalid email';
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _addressCtrl,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.location_on_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(isEditing ? 'Update Customer' : 'Add Customer'),
            ),
          ],
        ),
      ),
    );
  }
}
