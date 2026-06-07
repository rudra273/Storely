import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../db/database_helper.dart';
import '../models/pricing.dart';

/// Consolidated GST & Pricing screen.
///
/// Replaces the two scattered pricing entry points (global "Pricing Defaults"
/// and per-category pricing that was buried inside the Categories manager) with
/// one page:
///   • Section 1 — Pricing Defaults: edited inline (GST %, overhead, margin,
///     custom units). Saving preserves the `gstRegistered` /
///     `showPurchasePriceGlobally` flags, which are owned elsewhere.
///   • Section 2 — Category Pricing: each category shows a live override
///     summary; tapping opens a per-category editor.
class PricingScreen extends StatefulWidget {
  const PricingScreen({super.key});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen> {
  final _gstCtrl = TextEditingController();
  final _overheadCtrl = TextEditingController();
  final _marginCtrl = TextEditingController();

  GlobalPricingSettings _settings = const GlobalPricingSettings();
  List<String> _categories = const [];
  Map<String, CategoryPricingSettings> _categoryPricing = const {};

  bool _isLoading = true;
  bool _savingDefaults = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gstCtrl.dispose();
    _overheadCtrl.dispose();
    _marginCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final settings = await db.getGlobalPricingSettings();
    final categories = await db.getCategories();

    final pricing = <String, CategoryPricingSettings>{};
    for (final name in categories) {
      final cat = await db.getCategoryPricing(name);
      if (cat != null) pricing[name] = cat;
    }

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _categories = categories;
      _categoryPricing = pricing;
      _gstCtrl.text = settings.defaultGstPercent.toStringAsFixed(2);
      _overheadCtrl.text = settings.defaultOverheadCost.toStringAsFixed(2);
      _marginCtrl.text = settings.defaultProfitMarginPercent.toStringAsFixed(2);
      _isLoading = false;
    });
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error.toString().replaceFirst('Invalid argument: ', '')),
      ),
    );
  }

  Future<void> _saveDefaults() async {
    setState(() => _savingDefaults = true);
    // Preserve flags owned elsewhere (Shop Profile / product display settings).
    final updated = _settings.copyWith(
      defaultGstPercent: double.tryParse(_gstCtrl.text) ?? 0,
      defaultOverheadCost: double.tryParse(_overheadCtrl.text) ?? 0,
      defaultProfitMarginPercent: double.tryParse(_marginCtrl.text) ?? 0,
    );
    try {
      await DatabaseHelper.instance.saveGlobalPricingSettings(updated);
      await DatabaseHelper.instance.refreshAllProductSellingPrices();
      if (!mounted) return;
      setState(() => _settings = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pricing defaults saved')),
      );
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _savingDefaults = false);
    }
  }

  Future<void> _editCategoryPricing(String name) async {
    final current =
        _categoryPricing[name] ?? CategoryPricingSettings(name: name);
    final result = await showModalBottomSheet<CategoryPricingSettings>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CategoryPricingSheet(settings: current, global: _settings),
    );
    if (result == null) return;
    try {
      await DatabaseHelper.instance.saveCategoryPricing(result);
      await DatabaseHelper.instance.refreshAllProductSellingPrices();
      if (!mounted) return;
      setState(() {
        _categoryPricing = {..._categoryPricing, name: result};
      });
    } catch (e) {
      _showError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('GST & Pricing'),
        actions: const [
          AppInfoAction(
            title: 'GST & Pricing Help',
            intro:
                'Set the tax and pricing rules used to calculate product selling prices.',
            sections: [
              AppInfoSection(
                title: 'Pricing Defaults',
                points: [
                  'Default GST %, overhead, and profit margin apply to every product.',
                  'Custom units let you measure stock beyond the presets.',
                ],
              ),
              AppInfoSection(
                title: 'Category Pricing',
                points: [
                  'Override the defaults for a specific category.',
                  'Leave a field blank to keep using the default value.',
                ],
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                const SectionHeader(title: 'Pricing Defaults'),
                const SizedBox(height: AppSpacing.sm),
                _DefaultsCard(
                  gstCtrl: _gstCtrl,
                  overheadCtrl: _overheadCtrl,
                  marginCtrl: _marginCtrl,
                  saving: _savingDefaults,
                  onSave: _saveDefaults,
                ),
                const SizedBox(height: AppSpacing.xxl),
                const SectionHeader(title: 'Category Pricing'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Override the defaults per category. Leave fields blank to use the defaults above.',
                  style: AppText.caption.copyWith(
                    color: AppColors.inkMutedOf(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_categories.isEmpty)
                  _EmptyCategories(color: AppColors.inkMutedOf(context))
                else
                  ..._categories.map(
                    (name) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _CategoryPricingRow(
                        name: name,
                        pricing: _categoryPricing[name],
                        global: _settings,
                        onTap: () => _editCategoryPricing(name),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ── Defaults ──────────────────────────────────────────────────────────────

class _DefaultsCard extends StatelessWidget {
  final TextEditingController gstCtrl;
  final TextEditingController overheadCtrl;
  final TextEditingController marginCtrl;
  final bool saving;
  final VoidCallback onSave;

  const _DefaultsCard({
    required this.gstCtrl,
    required this.overheadCtrl,
    required this.marginCtrl,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MoneyField(controller: gstCtrl, label: 'Default GST %'),
          const SizedBox(height: 10),
          _MoneyField(controller: overheadCtrl, label: 'Default Overhead ₹'),
          const SizedBox(height: 10),
          _MoneyField(controller: marginCtrl, label: 'Default Profit Margin %'),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Defaults'),
          ),
        ],
      ),
    );
  }
}

// ── Category rows ───────────────────────────────────────────────────────────

class _CategoryPricingRow extends StatelessWidget {
  final String name;
  final CategoryPricingSettings? pricing;
  final GlobalPricingSettings global;
  final VoidCallback onTap;

  const _CategoryPricingRow({
    required this.name,
    required this.pricing,
    required this.global,
    required this.onTap,
  });

  String _summary() {
    final p = pricing;
    if (p == null) return 'Using defaults';
    final parts = <String>[];
    if (p.gstPercent != null) {
      parts.add('GST ${p.gstPercent!.toStringAsFixed(p.gstPercent! % 1 == 0 ? 0 : 2)}%');
    }
    if (p.profitMarginPercent != null) {
      parts.add('Margin ${p.profitMarginPercent!.toStringAsFixed(p.profitMarginPercent! % 1 == 0 ? 0 : 2)}%');
    }
    if (p.overheadCost != null) {
      parts.add('OH ₹${p.overheadCost!.toStringAsFixed(p.overheadCost! % 1 == 0 ? 0 : 2)}');
    }
    return parts.isEmpty ? 'Using defaults' : parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final hasOverride =
        pricing != null &&
        (pricing!.gstPercent != null ||
            pricing!.profitMarginPercent != null ||
            pricing!.overheadCost != null);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          LeadingIconChip(
            icon: Icons.sell_outlined,
            color: hasOverride ? AppColors.amber : AppColors.inkMutedOf(context),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _summary(),
                  style: AppText.caption.copyWith(
                    color: hasOverride
                        ? AppColors.inkOf(context)
                        : AppColors.inkMutedOf(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.inkMutedOf(context),
          ),
        ],
      ),
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  final Color color;

  const _EmptyCategories({required this.color});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Icon(Icons.category_outlined, color: color, size: 28),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No categories yet',
            style: AppText.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Add categories from the Store tab to price them here.',
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ── Category editor sheet ───────────────────────────────────────────────────

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

  void _save() {
    final gst = double.tryParse(_gstCtrl.text);
    final overhead = double.tryParse(_overheadCtrl.text);
    final margin = double.tryParse(_marginCtrl.text);
    // copyWith preserves directPriceToggle / manualPrice / hsn fields.
    final result = widget.settings.copyWith(
      gstPercent: gst,
      clearGstPercent: gst == null,
      overheadCost: overhead,
      clearOverheadCost: overhead == null,
      profitMarginPercent: margin,
      clearProfitMarginPercent: margin == null,
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.global;
    return _SheetFrame(
      title: '${widget.settings.name} Pricing',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MoneyField(
            controller: _gstCtrl,
            label:
                'GST % (blank = ${g.defaultGstPercent.toStringAsFixed(2)}%)',
          ),
          const SizedBox(height: 10),
          _MoneyField(
            controller: _overheadCtrl,
            label:
                'Overhead ₹ (blank = ${g.defaultOverheadCost.toStringAsFixed(2)})',
          ),
          const SizedBox(height: 10),
          _MoneyField(
            controller: _marginCtrl,
            label:
                'Profit Margin % (blank = ${g.defaultProfitMarginPercent.toStringAsFixed(2)}%)',
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save Category Pricing'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared building blocks (local to this screen) ───────────────────────────

class _MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _MoneyField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  final String title;
  final Widget child;

  const _SheetFrame({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
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
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(24),
          border: isDark
              ? Border.all(color: AppColors.borderOf(context))
              : Border.all(color: Colors.transparent),
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
                    color: AppColors.borderStrongOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  color: AppColors.brandOf(context),
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
