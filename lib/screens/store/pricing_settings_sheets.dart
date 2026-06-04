part of '../store_screen.dart';

class _StorePanel extends StatelessWidget {
  final Widget child;

  const _StorePanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
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
    return LeadingIconChip(icon: icon, color: AppColors.amber);
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
