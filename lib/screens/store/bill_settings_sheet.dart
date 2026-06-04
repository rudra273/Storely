part of '../store_screen.dart';

class _BillSettingsResult {
  final BillSettings settings;
  final InvoiceSeriesSettings invoiceSeries;

  const _BillSettingsResult({
    required this.settings,
    required this.invoiceSeries,
  });
}

class _BillSettingsSheet extends StatefulWidget {
  final BillSettings settings;
  final InvoiceSeriesSettings invoiceSeries;

  const _BillSettingsSheet({
    required this.settings,
    required this.invoiceSeries,
  });

  @override
  State<_BillSettingsSheet> createState() => _BillSettingsSheetState();
}

class _BillSettingsSheetState extends State<_BillSettingsSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _footerCtrl;
  late final TextEditingController _patternCtrl;
  late final TextEditingController _paddingCtrl;
  late final TextEditingController _seriesNameCtrl;
  late BillSettings _settings;
  late InvoiceSeriesSettings _series;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    _series = widget.invoiceSeries;
    _titleCtrl = TextEditingController(text: _settings.invoiceTitle);
    _footerCtrl = TextEditingController(text: _settings.footerText);
    _patternCtrl = TextEditingController(text: _series.formatTemplate);
    _paddingCtrl = TextEditingController(
      text: _series.sequencePadding.toString(),
    );
    _seriesNameCtrl = TextEditingController(text: _series.name);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _footerCtrl.dispose();
    _patternCtrl.dispose();
    _paddingCtrl.dispose();
    _seriesNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() => _pickImage((base64) {
    setState(() {
      _settings = _settings.copyWith(
        shopLogoBase64: base64,
        showShopLogo: true,
      );
    });
  });

  Future<void> _pickSignature() => _pickImage((base64) {
    setState(() {
      _settings = _settings.copyWith(
        digitalSignatureBase64: base64,
        showDigitalSignature: true,
      );
    });
  });

  Future<void> _pickImage(ValueChanged<String> onPicked) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null || bytes.isEmpty) return;
    if (bytes.length > 400 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image must be below 400 KB')),
      );
      return;
    }
    onPicked(base64Encode(bytes));
  }

  void _save() {
    final pattern = _patternCtrl.text.trim();
    if (!pattern.contains('{SEQ}')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill number pattern must include {SEQ}')),
      );
      return;
    }
    final padding = int.tryParse(_paddingCtrl.text.trim()) ?? 4;
    Navigator.pop(
      context,
      _BillSettingsResult(
        settings: _settings.copyWith(
          invoiceTitle: _titleCtrl.text,
          footerText: _footerCtrl.text,
        ),
        invoiceSeries: _series.copyWith(
          name: _seriesNameCtrl.text.trim().isEmpty
              ? 'Default'
              : _seriesNameCtrl.text.trim(),
          formatTemplate: pattern,
          sequencePadding: padding.clamp(1, 8),
        ),
      ),
    );
  }

  Widget _sequenceDigitsField() {
    return TextField(
      controller: _paddingCtrl,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Sequence digits',
        prefixIcon: Icon(Icons.format_list_numbered_rounded),
      ),
    );
  }

  Widget _resetPeriodField() {
    return DropdownButtonFormField<String>(
      initialValue: _series.resetPeriod,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Reset',
        prefixIcon: Icon(Icons.restart_alt_rounded),
      ),
      items: const [
        DropdownMenuItem(value: 'daily', child: Text('Daily')),
        DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
        DropdownMenuItem(
          value: 'financial_year',
          child: Text('Financial year'),
        ),
        DropdownMenuItem(value: 'never', child: Text('Never')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => _series = _series.copyWith(resetPeriod: value));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.88;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final isDark = AppColors.isDark(context);
    return SafeArea(
      top: false,
      child: Container(
        height: height,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(24),
          border: isDark
              ? Border.all(color: AppColors.borderOf(context))
              : null,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  const _PanelIcon(icon: Icons.receipt_long_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bill Settings',
                      style: TextStyle(
                        color: AppColors.brandOf(context),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 20),
                children: [
                  const _SectionLabel(title: 'Numbering'),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _seriesNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Series name',
                      prefixIcon: Icon(Icons.label_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _patternCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Bill number pattern',
                      helperText:
                          'Tokens: {YYYY}, {YY}, {MM}, {DD}, {SEQ}, {DEVICE}',
                      helperMaxLines: 2,
                      prefixIcon: Icon(Icons.tag_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 420) {
                        return Column(
                          children: [
                            _sequenceDigitsField(),
                            const SizedBox(height: AppSpacing.sm),
                            _resetPeriodField(),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: _sequenceDigitsField()),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: _resetPeriodField()),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _SectionLabel(title: 'Invoice Content'),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _titleCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Invoice title',
                      prefixIcon: Icon(Icons.title_rounded),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _footerCtrl,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Footer text',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _ToggleGroup(
                    title: 'Header',
                    children: [
                      _switch(
                        'Invoice title',
                        _settings.showInvoiceTitle,
                        (value) => _settings = _settings.copyWith(
                          showInvoiceTitle: value,
                        ),
                      ),
                      _AssetRow(
                        title: 'Shop logo',
                        hasAsset: _settings.shopLogoBase64 != null,
                        enabled: _settings.showShopLogo,
                        onToggle: (value) => setState(
                          () => _settings = _settings.copyWith(
                            showShopLogo: value,
                          ),
                        ),
                        onPick: _pickLogo,
                        onClear: () => setState(
                          () => _settings = _settings.copyWith(
                            clearShopLogo: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ToggleGroup(
                    title: 'Seller / Shop Details',
                    children: [
                      _switch(
                        'Shop name',
                        _settings.showShopName,
                        (value) =>
                            _settings = _settings.copyWith(showShopName: value),
                      ),
                      _switch(
                        'Shop address',
                        _settings.showShopAddress,
                        (value) => _settings = _settings.copyWith(
                          showShopAddress: value,
                        ),
                      ),
                      _switch(
                        'Shop phone',
                        _settings.showShopPhone,
                        (value) => _settings = _settings.copyWith(
                          showShopPhone: value,
                        ),
                      ),
                      _switch(
                        'Shop email',
                        _settings.showShopEmail,
                        (value) => _settings = _settings.copyWith(
                          showShopEmail: value,
                        ),
                      ),
                      _switch(
                        'Shop GSTIN',
                        _settings.showShopGstin,
                        (value) => _settings = _settings.copyWith(
                          showShopGstin: value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ToggleGroup(
                    title: 'Buyer / Customer Details',
                    children: [
                      _switch(
                        'Customer name',
                        _settings.showCustomerName,
                        (value) => _settings = _settings.copyWith(
                          showCustomerName: value,
                        ),
                      ),
                      _switch(
                        'Customer phone',
                        _settings.showCustomerPhone,
                        (value) => _settings = _settings.copyWith(
                          showCustomerPhone: value,
                        ),
                      ),
                      _switch(
                        'Customer address',
                        _settings.showCustomerAddress,
                        (value) => _settings = _settings.copyWith(
                          showCustomerAddress: value,
                        ),
                      ),
                      _switch(
                        'Customer GSTIN',
                        _settings.showCustomerGstin,
                        (value) => _settings = _settings.copyWith(
                          showCustomerGstin: value,
                        ),
                      ),
                      _switch(
                        'Legal business name',
                        _settings.showCustomerLegalName,
                        (value) => _settings = _settings.copyWith(
                          showCustomerLegalName: value,
                        ),
                      ),
                      _switch(
                        'Trade name',
                        _settings.showCustomerTradeName,
                        (value) => _settings = _settings.copyWith(
                          showCustomerTradeName: value,
                        ),
                      ),
                      _switch(
                        'Place of supply',
                        _settings.showCustomerPlaceOfSupply,
                        (value) => _settings = _settings.copyWith(
                          showCustomerPlaceOfSupply: value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ToggleGroup(
                    title: 'Invoice Info Row',
                    children: [
                      _switch(
                        'Invoice number',
                        _settings.showInvoiceNumber,
                        (value) => _settings = _settings.copyWith(
                          showInvoiceNumber: value,
                        ),
                      ),
                      _switch(
                        'Invoice date',
                        _settings.showInvoiceDate,
                        (value) => _settings = _settings.copyWith(
                          showInvoiceDate: value,
                        ),
                      ),
                      _switch(
                        'Place of supply',
                        _settings.showInvoicePlaceOfSupply,
                        (value) => _settings = _settings.copyWith(
                          showInvoicePlaceOfSupply: value,
                        ),
                      ),
                      _switch(
                        'Supply type',
                        _settings.showInvoiceSupplyType,
                        (value) => _settings = _settings.copyWith(
                          showInvoiceSupplyType: value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ToggleGroup(
                    title: 'Item Table Columns',
                    children: [
                      _switch(
                        'Serial number',
                        _settings.showItemSerialColumn,
                        (value) => _settings = _settings.copyWith(
                          showItemSerialColumn: value,
                        ),
                      ),
                      _switch(
                        'Item name',
                        _settings.showItemNameColumn,
                        (value) => _settings = _settings.copyWith(
                          showItemNameColumn: value,
                        ),
                      ),
                      _switch(
                        'HSN column',
                        _settings.showHsnColumn,
                        (value) => _settings = _settings.copyWith(
                          showHsnColumn: value,
                        ),
                      ),
                      _switch(
                        'Quantity',
                        _settings.showQuantityColumn,
                        (value) => _settings = _settings.copyWith(
                          showQuantityColumn: value,
                        ),
                      ),
                      _switch(
                        'Rate',
                        _settings.showRateColumn,
                        (value) => _settings = _settings.copyWith(
                          showRateColumn: value,
                        ),
                      ),
                      _switch(
                        'GST percent',
                        _settings.showGstPercentColumn,
                        (value) => _settings = _settings.copyWith(
                          showGstPercentColumn: value,
                        ),
                      ),
                      _switch(
                        'GST amount',
                        _settings.showGstAmountColumn,
                        (value) => _settings = _settings.copyWith(
                          showGstAmountColumn: value,
                        ),
                      ),
                      _switch(
                        'Amount',
                        _settings.showAmountColumn,
                        (value) => _settings = _settings.copyWith(
                          showAmountColumn: value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ToggleGroup(
                    title: 'Totals',
                    children: [
                      _switch(
                        'Subtotal',
                        _settings.showSubtotal,
                        (value) =>
                            _settings = _settings.copyWith(showSubtotal: value),
                      ),
                      _switch(
                        'Discount',
                        _settings.showDiscount,
                        (value) =>
                            _settings = _settings.copyWith(showDiscount: value),
                      ),
                      _switch(
                        'Taxable amount',
                        _settings.showTaxableAmount,
                        (value) => _settings = _settings.copyWith(
                          showTaxableAmount: value,
                        ),
                      ),
                      _switch(
                        'CGST / SGST / IGST',
                        _settings.showCgstSgstIgst,
                        (value) => _settings = _settings.copyWith(
                          showCgstSgstIgst: value,
                        ),
                      ),
                      _switch(
                        'GST total',
                        _settings.showGstTotal,
                        (value) =>
                            _settings = _settings.copyWith(showGstTotal: value),
                      ),
                      _switch(
                        'Grand total',
                        _settings.showGrandTotal,
                        (value) => _settings = _settings.copyWith(
                          showGrandTotal: value,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ToggleGroup(
                    title: 'Footer',
                    children: [
                      _switch(
                        'Footer text',
                        _settings.showFooterText,
                        (value) => _settings = _settings.copyWith(
                          showFooterText: value,
                        ),
                      ),
                      _AssetRow(
                        title: 'Digital signature',
                        hasAsset: _settings.digitalSignatureBase64 != null,
                        enabled: _settings.showDigitalSignature,
                        onToggle: (value) => setState(
                          () => _settings = _settings.copyWith(
                            showDigitalSignature: value,
                          ),
                        ),
                        onPick: _pickSignature,
                        onClear: () => setState(
                          () => _settings = _settings.copyWith(
                            clearDigitalSignature: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ToggleGroup(
                    title: 'Tax Display',
                    children: [
                      _switch(
                        'GST breakdown',
                        _settings.showGstBreakdown,
                        (value) => _settings = _settings.copyWith(
                          showGstBreakdown: value,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save Bill Settings'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switch(String title, bool value, ValueChanged<bool> update) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: (next) => setState(() => update(next)),
    );
  }
}

class _ToggleGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ToggleGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: Text(
              title,
              style: AppText.caption.copyWith(
                color: AppColors.inkMutedOf(context),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _AssetRow extends StatelessWidget {
  final String title;
  final bool hasAsset;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _AssetRow({
    required this.title,
    required this.hasAsset,
    required this.enabled,
    required this.onToggle,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Switch(value: enabled, onChanged: onToggle),
          Expanded(
            child: Text(
              hasAsset ? '$title selected' : title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Choose'),
          ),
          if (hasAsset)
            IconButton(
              tooltip: 'Remove $title',
              onPressed: onClear,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
    );
  }
}
