part of '../products_screen.dart';

/// Full-screen Create / Edit Item page.
///
/// Quick entry on top (name, type, category, selling price, GST, item code);
/// purchase price, opening stock, low-stock alert and HSN/SAC live in the
/// collapsible "More details" sections. Pops:
/// - the saved [Product] when [checkoutScope] is set (billing quick add),
/// - `true` after any other save.
class ItemFormScreen extends StatefulWidget {
  /// The item being edited; null creates a new item.
  final Product? product;
  final List<String> categories;
  final List<String> units;
  final String? initialBarcode;
  final CheckoutScope? checkoutScope;
  final Future<String?> Function(BuildContext context) scanBarcode;

  const ItemFormScreen({
    super.key,
    this.product,
    required this.categories,
    required this.units,
    required this.scanBarcode,
    this.initialBarcode,
    this.checkoutScope,
  });

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _codeController = TextEditingController();
  final _skuController = TextEditingController();
  final _costController = TextEditingController();
  final _qtyController = TextEditingController();
  final _reorderController = TextEditingController();
  final _hsnController = TextEditingController();
  final _nameFocus = FocusNode();

  late List<String> _categories = List.of(widget.categories);
  late List<String> _units = List.of(widget.units);
  String _itemType = ItemType.product;
  String? _category;
  String? _unit = 'pcs';
  TaxSelection _tax = const TaxSelection();
  String? _taxHint;
  bool _trackStock = true;
  bool _moreOpen = false;
  bool _saving = false;
  bool _dirty = false;
  bool _generating = false;
  String? _nameError;

  Product? get _editing => widget.product;
  bool get _isEditing => _editing != null;
  bool get _isService => _itemType == ItemType.service;

  @override
  void initState() {
    super.initState();
    final product = _editing;
    if (product != null) {
      _nameController.text = product.name;
      _priceController.text = _moneyInput(product.sellingPrice);
      _codeController.text = product.barcode ?? '';
      _skuController.text = product.productCode ?? '';
      _costController.text = _moneyInput(product.purchasePrice);
      _qtyController.text = _formatQuantityInput(product.quantity);
      _reorderController.text = product.reorderLevel == null
          ? ''
          : _formatQuantityInput(product.reorderLevel!);
      _hsnController.text = product.hsnCode ?? '';
      _itemType = product.itemType;
      _category = product.category;
      _unit = product.unit;
      _trackStock = product.trackStock || product.isService;
      _tax = TaxSelection(
        taxType: product.taxType,
        gstPercent: product.gstPercent ?? 0,
        cessPercent: product.cessPercent,
      ).normalised();
      _moreOpen =
          product.hsnCode != null ||
          product.productCode != null ||
          product.reorderLevel != null;
      if (product.gstPercent == null) _loadInheritedGst(product);
    } else {
      _codeController.text = widget.initialBarcode ?? '';
      // Stock decides whether billing can add the new item right away.
      _moreOpen = widget.checkoutScope != null;
      _loadDefaultGst();
    }
    _snapshotTexts();
  }

  List<TextEditingController> get _textControllers => [
    _nameController,
    _priceController,
    _codeController,
    _skuController,
    _costController,
    _qtyController,
    _reorderController,
    _hsnController,
  ];

  /// Text as last saved/opened; selection changes alone never count as edits.
  List<String> _savedTexts = const [];

  void _snapshotTexts() =>
      _savedTexts = [for (final c in _textControllers) c.text];

  bool get _hasEdits {
    if (_dirty) return true;
    final texts = _textControllers;
    for (var i = 0; i < texts.length; i++) {
      if (texts[i].text != _savedTexts[i]) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _codeController.dispose();
    _skuController.dispose();
    _costController.dispose();
    _qtyController.dispose();
    _reorderController.dispose();
    _hsnController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  static String _moneyInput(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  Future<void> _loadDefaultGst() async {
    final global = await DatabaseHelper.instance.getGlobalPricingSettings();
    if (!mounted || _dirty || _category != null) return;
    setState(() => _tax = TaxSelection(gstPercent: global.defaultGstPercent));
  }

  /// Items saved before M1.0 may inherit GST from their category or the shop
  /// default; show the effective rate.
  Future<void> _loadInheritedGst(Product product) async {
    final db = DatabaseHelper.instance;
    final global = await db.getGlobalPricingSettings();
    final category = product.category == null
        ? null
        : await db.getCategoryPricing(product.category!);
    if (!mounted || !_tax.isTaxable) return;
    setState(() {
      _tax = _tax.copyWith(
        gstPercent: category?.gstPercent ?? global.defaultGstPercent,
      );
    });
  }

  Future<void> _selectCategory(String? value) async {
    setState(() {
      _category = value;
      _dirty = true;
    });
    if (value == null || _isEditing) return;
    final defaults = await DatabaseHelper.instance.getCategoryPricing(value);
    if (!mounted || _category != value) return;
    if (defaults == null || !defaults.hasTaxDefault) {
      setState(() => _taxHint = null);
      return;
    }
    setState(() {
      _tax = TaxSelection(
        taxType: defaults.taxType ?? TaxType.taxable,
        gstPercent: defaults.gstPercent ?? _tax.gstPercent,
        cessPercent: defaults.cessPercent ?? 0,
      ).normalised();
      _taxHint = 'From category $value. You can change it for this item.';
    });
  }

  Future<void> _addCategory() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _AddOptionDialog(label: 'Category'),
    );
    if (value == null || !mounted) return;
    try {
      await DatabaseHelper.instance.addCategoryOption(value);
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyError(error));
      return;
    }
    if (!mounted) return;
    setState(() {
      if (!_categories.contains(value)) _categories = [..._categories, value];
    });
    await _selectCategory(value);
  }

  Future<void> _addUnit() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => const _AddOptionDialog(label: 'Unit'),
    );
    if (value == null || !mounted) return;
    try {
      await DatabaseHelper.instance.addUnitOption(value);
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyError(error));
      return;
    }
    if (!mounted) return;
    setState(() {
      if (!_units.contains(value)) _units = [..._units, value];
      _unit = value;
      _dirty = true;
    });
  }

  List<String> get _unitOptions {
    final seen = <String>{};
    return [
      for (final unit in [...Product.presetUnits, ..._units])
        if (seen.add(unit.toLowerCase())) unit,
    ];
  }

  Future<bool> _confirmReplaceCode(String action) async {
    if (_codeController.text.trim().isEmpty) return true;
    final replace = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Replace item code?'),
        content: Text(
          '"${_codeController.text.trim()}" is already entered. $action a new code instead?',
        ),
        actions: [
          TextButton(
            key: const ValueKey('item-code-keep'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const ValueKey('item-code-replace'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    return replace == true;
  }

  Future<void> _scanCode() async {
    final value = await widget.scanBarcode(context);
    if (!mounted || value == null || value.trim().isEmpty) return;
    if (value.trim() == _codeController.text.trim()) return;
    if (!await _confirmReplaceCode('Use the scanned')) return;
    if (!mounted) return;
    setState(() => _codeController.text = value.trim());
  }

  Future<void> _generateCode() async {
    if (_generating) return;
    if (!await _confirmReplaceCode('Generate')) return;
    if (!mounted) return;
    setState(() => _generating = true);
    try {
      final code = await DatabaseHelper.instance.generateUniqueItemCode();
      if (!mounted) return;
      setState(() => _codeController.text = code);
    } catch (error) {
      if (!mounted) return;
      _showSnack(friendlyError(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _price(String? value) {
    final n = double.tryParse(value?.trim() ?? '');
    return n == null || n <= 0 ? 'Enter a price' : null;
  }

  String? _optionalNumber(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final n = double.tryParse(text);
    return n == null || n < 0 ? 'Enter a valid number' : null;
  }

  Product _buildProduct() {
    final price = double.parse(_priceController.text.trim());
    final cost = double.tryParse(_costController.text.trim());
    final tax = _tax.normalised();
    final tracked = !_isService && _trackStock;
    final reorder = tracked
        ? double.tryParse(_reorderController.text.trim())
        : null;
    final existing = _editing;
    if (existing == null) {
      return Product(
        name: _nameController.text.trim(),
        itemType: _itemType,
        category: _category,
        sellingPrice: price,
        manualPrice: price,
        directPriceToggle: true,
        // Without a cost, profit shows as zero rather than as 100%.
        purchasePrice: cost ?? price,
        taxType: tax.taxType,
        gstPercent: tax.gstPercent,
        cessPercent: tax.cessPercent,
        quantity: tracked
            ? double.tryParse(_qtyController.text.trim()) ?? 0
            : 0.0,
        trackStock: tracked,
        reorderLevel: reorder,
        unit: _unit,
        barcode: _optionalControllerText(_codeController),
        productCode: _optionalControllerText(_skuController),
        hsnCode: _optionalControllerText(_hsnController),
      );
    }
    final priceChanged = (price - existing.sellingPrice).abs() > 0.004;
    final code = _optionalControllerText(_codeController);
    final sku = _optionalControllerText(_skuController);
    final hsn = _optionalControllerText(_hsnController);
    return existing.copyWith(
      name: _nameController.text.trim(),
      itemType: _itemType,
      trackStock: tracked,
      clearCategory: _category == null,
      category: _category,
      clearUnit: _unit == null,
      unit: _unit,
      // A new selling price becomes the item's direct price; an untouched
      // one keeps the item's pricing rule (formula or direct).
      directPriceToggle: priceChanged ? true : null,
      manualPrice: priceChanged ? price : null,
      sellingPrice: priceChanged ? price : null,
      purchasePrice: cost ?? existing.purchasePrice,
      taxType: tax.taxType,
      gstPercent: tax.gstPercent,
      cessPercent: tax.cessPercent,
      // Services keep whatever stock count they had; it is never used.
      quantity: tracked
          ? double.tryParse(_qtyController.text.trim()) ?? existing.quantity
          : existing.quantity,
      clearReorderLevel: reorder == null,
      reorderLevel: reorder,
      clearBarcode: code == null,
      barcode: code,
      clearItemCode: sku == null,
      productCode: sku,
      clearHsnCode: hsn == null,
      hsnCode: hsn,
    );
  }

  Future<void> _save({required bool addAnother}) async {
    if (_saving) return;
    setState(() => _nameError = null);
    if (!_formKey.currentState!.validate()) {
      // A hidden invalid field would otherwise block saving silently.
      if (!_moreOpen) setState(() => _moreOpen = true);
      return;
    }
    if (_tax.isTaxable && !isAllowedGstRate(_tax.gstPercent)) {
      _showSnack('Pick a GST rate: this item\'s old rate is not a GST slab.');
      return;
    }
    final name = _nameController.text.trim();
    final db = DatabaseHelper.instance;
    setState(() => _saving = true);
    try {
      if (!await db.isNameUnique(name, excludeId: _editing?.id)) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _nameError = 'An item with this name exists';
        });
        return;
      }
      final product = _buildProduct();
      Product? saved;
      final editing = _editing;
      if (editing != null) {
        await db.updateProduct(product, expectedUpdatedAt: editing.updatedAt);
      } else if (widget.checkoutScope case final scope?) {
        saved = await db.insertProductForCheckout(product, scope);
      } else {
        await db.insertProduct(product);
      }
      if (!mounted) return;
      _dirty = false;
      if (!addAnother) {
        Navigator.pop<Object?>(context, saved ?? true);
        return;
      }
      for (final controller in _textControllers) {
        controller.clear();
      }
      _snapshotTexts();
      _dirty = false;
      setState(() => _saving = false);
      _nameFocus.requestFocus();
      _showSnack('Added "$name"');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack('Could not save: ${friendlyError(error)}');
    }
  }

  Future<void> _requestClose() async {
    if (_saving) return;
    if (!_hasEdits) {
      Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your item changes have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            key: const ValueKey('item-form-discard'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(context.l10n.discard),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final decimal = [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
    ];
    const numberKeyboard = TextInputType.numberWithOptions(decimal: true);
    final inCheckout = widget.checkoutScope != null;
    final codeLabel = _isService ? 'SAC code' : 'HSN code';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const ValueKey('quick-add-cancel'),
            tooltip: context.l10n.cancel,
            icon: const Icon(Icons.close_rounded),
            onPressed: _saving ? null : _requestClose,
          ),
          title: Text(_isEditing ? 'Edit Item' : 'Create Item'),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                _ItemFormSection(
                  title: 'Basic Info',
                  icon: Icons.inventory_2_outlined,
                  children: [
                    TextFormField(
                      key: const ValueKey('quick-add-name'),
                      controller: _nameController,
                      focusNode: _nameFocus,
                      autofocus: !_isEditing,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: context.l10n.productNameReq,
                        errorText: _nameError,
                      ),
                      validator: _required,
                    ),
                    SegmentedButton<String>(
                      key: const ValueKey('item-type'),
                      segments: const [
                        ButtonSegment(
                          value: ItemType.product,
                          icon: Icon(Icons.inventory_2_outlined),
                          label: Text('Product'),
                        ),
                        ButtonSegment(
                          value: ItemType.service,
                          icon: Icon(Icons.handyman_outlined),
                          label: Text('Service'),
                        ),
                      ],
                      selected: {_itemType},
                      onSelectionChanged: (value) => setState(() {
                        _itemType = value.single;
                        _dirty = true;
                      }),
                    ),
                    _OptionDropdown(
                      key: ValueKey('item-category-$_category'),
                      label: 'Category',
                      value: _category,
                      options: _categories,
                      onChanged: _selectCategory,
                      onAdd: _addCategory,
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('quick-add-price'),
                            controller: _priceController,
                            keyboardType: numberKeyboard,
                            inputFormatters: decimal,
                            decoration: InputDecoration(
                              labelText: context.l10n.sellingPriceReq,
                              prefixText: '₹ ',
                            ),
                            validator: _price,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _OptionDropdown(
                            key: ValueKey('item-unit-$_unit'),
                            label: context.l10n.unit,
                            value: _unit,
                            options: _unitOptions,
                            noValueLabel: 'No Unit',
                            addLabel: 'Add custom',
                            onChanged: (value) => setState(() {
                              _unit = value;
                              _dirty = true;
                            }),
                            onAdd: _addUnit,
                          ),
                        ),
                      ],
                    ),
                    TaxSelector(
                      value: _tax,
                      helperText: _taxHint,
                      onChanged: (value) => setState(() {
                        _tax = value.normalised();
                        _taxHint = null;
                        _dirty = true;
                      }),
                    ),
                    _ItemCodeField(
                      controller: _codeController,
                      generating: _generating,
                      // The billing camera stays with the bill screen.
                      onScan: inCheckout ? null : _scanCode,
                      onGenerate: _generateCode,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _MoreDetailsToggle(
                  open: _moreOpen,
                  onTap: () => setState(() => _moreOpen = !_moreOpen),
                ),
                if (_moreOpen) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ItemFormSection(
                    title: 'Pricing & Tax',
                    icon: Icons.receipt_long_outlined,
                    children: [
                      TextFormField(
                        key: const ValueKey('item-purchase-price'),
                        controller: _costController,
                        keyboardType: numberKeyboard,
                        inputFormatters: decimal,
                        decoration: InputDecoration(
                          labelText: context.l10n.costPrice,
                          hintText: context.l10n.optional,
                          prefixText: '₹ ',
                        ),
                        validator: _optionalNumber,
                      ),
                      TextFormField(
                        key: const ValueKey('item-hsn'),
                        controller: _hsnController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: InputDecoration(
                          labelText: codeLabel,
                          hintText: context.l10n.optional,
                        ),
                      ),
                      TextFormField(
                        key: const ValueKey('item-sku'),
                        controller: _skuController,
                        decoration: InputDecoration(
                          labelText: 'Short code / SKU',
                          hintText: context.l10n.optional,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ItemFormSection(
                    title: 'Stock / Inventory',
                    icon: Icons.warehouse_outlined,
                    children: _isService
                        ? [
                            Text(
                              'Services are not stock-tracked: billing never '
                              'checks or reduces their stock.',
                              style: AppText.caption.copyWith(
                                color: AppColors.inkMutedOf(context),
                              ),
                            ),
                          ]
                        : [
                            Material(
                              // ListTile ink needs its own Material inside the card.
                              type: MaterialType.transparency,
                              child: SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(context.l10n.trackStock),
                                subtitle: Text(
                                  'Turn off for loose items',
                                  style: AppText.caption,
                                ),
                                value: _trackStock,
                                onChanged: (value) => setState(() {
                                  _trackStock = value;
                                  _dirty = true;
                                }),
                              ),
                            ),
                            if (_trackStock) ...[
                              TextFormField(
                                key: const ValueKey('quick-add-qty'),
                                controller: _qtyController,
                                keyboardType: numberKeyboard,
                                inputFormatters: decimal,
                                decoration: InputDecoration(
                                  labelText: _isEditing
                                      ? 'Current stock'
                                      : 'Opening stock',
                                  hintText: '0',
                                ),
                                validator: _optionalNumber,
                              ),
                              TextFormField(
                                key: const ValueKey('item-reorder'),
                                controller: _reorderController,
                                keyboardType: numberKeyboard,
                                inputFormatters: decimal,
                                decoration: InputDecoration(
                                  labelText: 'Low-stock alert at',
                                  hintText: 'Shop default',
                                ),
                                validator: _optionalNumber,
                              ),
                            ],
                          ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Row(
              children: [
                if (!_isEditing && !inCheckout) ...[
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('item-save-another'),
                      onPressed: _saving ? null : () => _save(addAnother: true),
                      child: Text(context.l10n.saveAndAddAnother),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('quick-add-save'),
                    onPressed: _saving ? null : () => _save(addAnother: false),
                    child: Text(context.l10n.save),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemFormSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _ItemFormSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LeadingIconChip(icon: icon, color: AppColors.brandOf(context)),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: AppText.subtitle),
            ],
          ),
          for (final child in children) ...[
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ],
      ),
    );
  }
}

class _MoreDetailsToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onTap;

  const _MoreDetailsToggle({required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const ValueKey('item-more-details'),
      onPressed: onTap,
      icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
      label: Text(
        open ? 'Hide details' : 'More details · purchase price, stock, HSN/SAC',
      ),
    );
  }
}

/// Item code / barcode field with inline Scan and Generate actions.
class _ItemCodeField extends StatelessWidget {
  final TextEditingController controller;
  final bool generating;
  final VoidCallback? onScan;
  final VoidCallback onGenerate;

  const _ItemCodeField({
    required this.controller,
    required this.generating,
    required this.onScan,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('quick-add-barcode'),
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Item code / barcode',
            hintText: context.l10n.optional,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('item-code-scan'),
                onPressed: onScan,
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('item-code-generate'),
                onPressed: generating ? null : onGenerate,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Generate'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
