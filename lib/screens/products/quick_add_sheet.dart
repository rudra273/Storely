part of '../products_screen.dart';

/// The fast way to add a product: name, price, stock and an optional
/// barcode. Supplier, cost breakdown and imports stay in "New purchase".
/// Pops [_QuickAddSheet.openPurchase] when the user wants the full flow.
class _QuickAddSheet extends StatefulWidget {
  static const openPurchase = 'purchase';

  final List<String> units;
  final Future<String?> Function(BuildContext sheetContext) scanBarcode;

  const _QuickAddSheet({required this.units, required this.scanBarcode});

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController();
  final _costController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _nameFocus = FocusNode();
  String _unit = 'pcs';
  bool _trackStock = true;
  bool _saving = false;
  String? _nameError;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    _costController.dispose();
    _barcodeController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  List<String> get _unitOptions {
    final seen = <String>{};
    return [
      for (final unit in [...Product.presetUnits, ...widget.units])
        if (seen.add(unit.toLowerCase())) unit,
    ];
  }

  Future<void> _scan() async {
    final value = await widget.scanBarcode(context);
    if (!mounted || value == null) return;
    setState(() => _barcodeController.text = value);
  }

  Future<void> _save({required bool addAnother}) async {
    if (_saving) return;
    setState(() => _nameError = null);
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    final db = DatabaseHelper.instance;
    setState(() => _saving = true);
    try {
      if (!await db.isNameUnique(name)) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _nameError = 'A product with this name exists';
        });
        return;
      }
      final price = double.parse(_priceController.text.trim());
      final cost = double.tryParse(_costController.text.trim());
      final qty = _trackStock
          ? double.tryParse(_qtyController.text.trim()) ?? 0
          : 0.0;
      final barcode = _barcodeController.text.trim();
      await db.insertProduct(
        Product(
          name: name,
          sellingPrice: price,
          manualPrice: price,
          directPriceToggle: true,
          // Without a cost, profit shows as zero rather than as 100%.
          purchasePrice: cost ?? price,
          quantity: qty,
          trackStock: _trackStock,
          unit: _unit,
          barcode: barcode.isEmpty ? null : barcode,
        ),
      );
      if (!mounted) return;
      if (!addAnother) {
        Navigator.pop(context);
        return;
      }
      _nameController.clear();
      _priceController.clear();
      _qtyController.clear();
      _costController.clear();
      _barcodeController.clear();
      setState(() => _saving = false);
      _nameFocus.requestFocus();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Added "$name"')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _price(String? value) {
    final n = double.tryParse(value?.trim() ?? '');
    return n == null || n <= 0 ? 'Enter a price' : null;
  }

  @override
  Widget build(BuildContext context) {
    final decimal = [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
    ];
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Quick add product', style: AppText.title),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const ValueKey('quick-add-name'),
                  controller: _nameController,
                  focusNode: _nameFocus,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Product name *',
                    errorText: _nameError,
                  ),
                  validator: _required,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('quick-add-price'),
                        controller: _priceController,
                        keyboardType: numberKeyboard,
                        inputFormatters: decimal,
                        decoration: const InputDecoration(
                          labelText: 'Selling price *',
                          prefixText: '₹ ',
                        ),
                        validator: _price,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: [
                          for (final unit in _unitOptions)
                            DropdownMenuItem(value: unit, child: Text(unit)),
                        ],
                        onChanged: (value) =>
                            setState(() => _unit = value ?? _unit),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('quick-add-qty'),
                        controller: _qtyController,
                        enabled: _trackStock,
                        keyboardType: numberKeyboard,
                        inputFormatters: decimal,
                        decoration: InputDecoration(
                          labelText: _trackStock
                              ? 'Opening stock'
                              : 'Not tracked',
                          hintText: '0',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _costController,
                        keyboardType: numberKeyboard,
                        inputFormatters: decimal,
                        decoration: const InputDecoration(
                          labelText: 'Cost price',
                          hintText: 'Optional',
                          prefixText: '₹ ',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _barcodeController,
                  decoration: InputDecoration(
                    labelText: 'Barcode (optional)',
                    suffixIcon: IconButton(
                      tooltip: 'Scan barcode',
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      onPressed: _scan,
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Track stock'),
                  subtitle: Text(
                    'Turn off for services and loose items',
                    style: AppText.caption,
                  ),
                  value: _trackStock,
                  onChanged: (value) => setState(() => _trackStock = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => _save(addAnother: true),
                        child: const Text('Save & add another'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('quick-add-save'),
                        onPressed: _saving
                            ? null
                            : () => _save(addAnother: false),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () =>
                            Navigator.pop(context, _QuickAddSheet.openPurchase),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Full purchase entry (supplier, import)'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
