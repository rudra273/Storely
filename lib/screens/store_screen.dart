import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../main.dart';
import '../models/product.dart';
import '../models/pricing.dart';
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
  List<String> _categories = [];
  List<String> _suppliers = [];
  List<String> _units = [];
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
    final shopName = await db.getShopName();
    final categories = await db.getCategories();
    final suppliers = await db.getSuppliers();
    final units = await db.getUnits();
    final pricingSettings = await db.getGlobalPricingSettings();
    final lowStockThreshold = await db.getLowStockThreshold();
    if (!mounted) return;
    setState(() {
      _shopName = shopName;
      _categories = categories;
      _suppliers = suppliers;
      _units = units;
      _pricingSettings = pricingSettings;
      _lowStockThreshold = lowStockThreshold;
      _isLoading = false;
    });
  }

  Future<void> _editShopName() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: _shopName == null ? 'Add Shop Name' : 'Update Shop Name',
        label: 'Shop Name',
        initialValue: _shopName,
      ),
    );
    if (value == null) return;
    await _runStoreAction(() => DatabaseHelper.instance.saveShopName(value));
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
    final value = await showDialog<String>(
      context: context,
      builder: (_) =>
          const _NameDialog(title: 'Add Supplier', label: 'Supplier Name'),
    );
    if (value == null) return;
    await _runStoreAction(
      () => DatabaseHelper.instance.addSupplierOption(value),
    );
  }

  Future<void> _editSupplier(String currentName) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Update Supplier',
        label: 'Supplier Name',
        initialValue: currentName,
      ),
    );
    if (value == null) return;
    await _runStoreAction(
      () => DatabaseHelper.instance.updateSupplierOption(currentName, value),
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

  Future<void> _showSupplierManager() {
    return _showOptionManager(
      title: 'Suppliers',
      emptyText: 'No suppliers yet',
      icon: Icons.local_shipping_outlined,
      loadOptions: DatabaseHelper.instance.getSuppliers,
      onAdd: _addSupplier,
      onEdit: _editSupplier,
      onDelete: _deleteSupplier,
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
                  _ShopPanel(shopName: _shopName, onEdit: _editShopName),
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
                    subtitle: '${_suppliers.length} saved',
                    icon: Icons.local_shipping_outlined,
                    onTap: _showSupplierManager,
                  ),
                  const SizedBox(height: 10),
                  _StoreActionRow(
                    title: 'Pricing Defaults',
                    subtitle:
                        '${_pricingSettings.gstRegistered ? 'GST registered' : 'GST not registered'} • Margin ${_pricingSettings.defaultProfitMarginPercent.toStringAsFixed(2)}%',
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

class _ShopPanel extends StatelessWidget {
  final String? shopName;
  final VoidCallback onEdit;

  const _ShopPanel({required this.shopName, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return _StorePanel(
      child: Row(
        children: [
          const _PanelIcon(icon: Icons.storefront_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Shop',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  shopName ?? 'No shop name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit shop name',
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
  late bool _gstRegistered;
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
    _gstRegistered = widget.settings.gstRegistered;
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
        gstRegistered: _gstRegistered,
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
