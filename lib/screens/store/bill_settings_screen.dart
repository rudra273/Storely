import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../models/bill_settings.dart';
import '../../theme/app_theme.dart';

/// Full-page editor for invoice/bill appearance: numbering series, visible
/// fields, logo/signature assets, and a live preview of the generated PDF.
///
/// Self-contained: loads its own [BillSettings] + [InvoiceSeriesSettings] from
/// the database, saves on Save, and pops `true` when changes were persisted so
/// callers (Store screen, Bills screen) can refresh. This lets it be opened
/// from anywhere without preloaded data.
class BillSettingsScreen extends StatefulWidget {
  const BillSettingsScreen({super.key});

  @override
  State<BillSettingsScreen> createState() => _BillSettingsScreenState();
}

class _BillSettingsScreenState extends State<BillSettingsScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _footerCtrl = TextEditingController();
  final TextEditingController _patternCtrl = TextEditingController();
  final TextEditingController _paddingCtrl = TextEditingController();
  final TextEditingController _seriesNameCtrl = TextEditingController();
  BillSettings _settings = BillSettings();
  InvoiceSeriesSettings _series = const InvoiceSeriesSettings();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    final db = DatabaseHelper.instance;
    final settings = await db.getBillSettings();
    final series = await db.getDefaultInvoiceSeriesSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _series = series;
      _titleCtrl.text = settings.invoiceTitle;
      _footerCtrl.text = settings.footerText;
      _patternCtrl.text = series.formatTemplate;
      _paddingCtrl.text = series.sequencePadding.toString();
      _seriesNameCtrl.text = series.name;
      _isLoading = false;
    });
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

  Future<void> _save() async {
    if (_isSaving) return;
    final pattern = _patternCtrl.text.trim();
    if (!pattern.contains('{SEQ}')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill number pattern must include {SEQ}')),
      );
      return;
    }
    final padding = int.tryParse(_paddingCtrl.text.trim()) ?? 4;
    final settings = _settings.copyWith(
      invoiceTitle: _titleCtrl.text,
      footerText: _footerCtrl.text,
    );
    final series = _series.copyWith(
      name: _seriesNameCtrl.text.trim().isEmpty
          ? 'Default'
          : _seriesNameCtrl.text.trim(),
      formatTemplate: pattern,
      sequencePadding: padding.clamp(1, 8),
    );
    setState(() => _isSaving = true);
    try {
      final db = DatabaseHelper.instance;
      await db.saveBillSettings(settings);
      await db.saveDefaultInvoiceSeriesSettings(series);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Bill Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _BillPreviewPanel(settings: _settings),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, bottomInset + 20),
                    children: [
                      const _SettingsSectionLabel(title: 'Numbering'),
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
                      const _SettingsSectionLabel(title: 'Invoice Content'),
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
                            (value) => _settings = _settings.copyWith(
                              showShopName: value,
                            ),
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
                            (value) => _settings = _settings.copyWith(
                              showSubtotal: value,
                            ),
                          ),
                          _switch(
                            'Discount',
                            _settings.showDiscount,
                            (value) => _settings = _settings.copyWith(
                              showDiscount: value,
                            ),
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
                            (value) => _settings = _settings.copyWith(
                              showGstTotal: value,
                            ),
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
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          _isSaving ? 'Saving...' : 'Save Bill Settings',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _switch(String title, bool value, ValueChanged<bool> update) {
    return _CheckRow(
      title: title,
      value: value,
      onChanged: (next) => setState(() => update(next)),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  final String title;

  const _SettingsSectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title.toUpperCase(), style: AppText.label);
  }
}

class _CheckRow extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CheckRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: AppRadius.smRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xs,
        ),
        child: Row(
          children: [
            _CheckBox(value: value),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                title,
                style: AppText.body.copyWith(
                  color: value
                      ? AppColors.inkOf(context)
                      : AppColors.inkMutedOf(context),
                  fontWeight: value ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  final bool value;

  const _CheckBox({required this.value});

  @override
  Widget build(BuildContext context) {
    final brand = AppColors.brandOf(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: value ? brand : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: value ? brand : AppColors.borderStrongOf(context),
          width: 1.5,
        ),
      ),
      child: value
          ? Icon(
              Icons.check_rounded,
              size: 16,
              color: AppColors.isDark(context)
                  ? AppColors.darkBg
                  : Colors.white,
            )
          : null,
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
          InkWell(
            onTap: () => onToggle(!enabled),
            borderRadius: AppRadius.smRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
                horizontal: AppSpacing.xs,
              ),
              child: _CheckBox(value: enabled),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              hasAsset ? '$title selected' : title,
              style: AppText.body.copyWith(
                color: enabled
                    ? AppColors.inkOf(context)
                    : AppColors.inkMutedOf(context),
                fontWeight: FontWeight.w600,
              ),
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

/// Sample data used by the live preview so the layout looks realistic.
class _PreviewSample {
  static const shopName = 'Acme Traders';
  static const shopAddress = '14 Market Road, Pune 411001';
  static const shopPhone = '+91 98765 43210';
  static const shopEmail = 'sales@acme.in';
  static const shopGstin = '27AAAAA0000A1Z5';

  static const customerName = 'Rahul Sharma';
  static const customerLegalName = 'Sharma Enterprises Pvt Ltd';
  static const customerTradeName = 'Sharma Stores';
  static const customerGstin = '27BBBBB1111B2Z6';
  static const customerPhone = '+91 91234 56789';
  static const customerAddress = '5 Hill View, Pune';
  static const placeOfSupply = '27';

  static const invoiceNo = 'INV-2025-0042';
  static const invoiceDate = '05 Jun 2026, 11:30 AM';
  static const supplyType = 'Intrastate';

  // name, hsn, qty, rate, gst%, gstAmt, amount
  static const items = [
    ['Steel Bolt M6', '7318', '20', '4.50', '18%', '16.20', '106.20'],
    ['Hex Nut M6', '7318', '20', '2.00', '18%', '7.20', '47.20'],
    ['Washer 6mm', '7318', '50', '0.80', '18%', '7.20', '47.20'],
  ];

  static const subtotal = '200.60';
  static const discount = '-10.00';
  static const taxable = '190.60';
  static const cgst = '17.15';
  static const sgst = '17.15';
  static const gstTotal = '34.30';
  static const grandTotal = '224.90';
}

/// A live, scaled-down mock of the generated invoice PDF. Mirrors the section
/// layout and visibility rules in [BillPdfGenerator] using sample data, so the
/// shopkeeper can see what each toggle adds/removes in real time.
class _BillPreviewPanel extends StatelessWidget {
  final BillSettings settings;

  const _BillPreviewPanel({required this.settings});

  bool get _showHeader =>
      settings.showInvoiceTitle ||
      (settings.showShopLogo && settings.shopLogoBase64 != null);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, AppSpacing.xs),
            child: Row(
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: 14,
                  color: AppColors.brandOf(context),
                ),
                const SizedBox(width: 6),
                Text(
                  'LIVE PREVIEW',
                  style: AppText.label.copyWith(
                    color: AppColors.inkMutedOf(context),
                  ),
                ),
              ],
            ),
          ),
          // The PDF page is always white; render it on white regardless of theme.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E5EA)),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Color(0xFF1F1F1F),
                    fontSize: 7,
                    height: 1.25,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _sections(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections() {
    final out = <Widget>[];
    final header = _header();
    if (header != null) {
      out.add(header);
      out.add(const SizedBox(height: 6));
    }
    final party = _partyBlock();
    if (party != null) {
      out.add(party);
      out.add(const SizedBox(height: 6));
    }
    final meta = _meta();
    if (meta != null) {
      out.add(meta);
      out.add(const SizedBox(height: 6));
    }
    final table = _itemsTable();
    if (table != null) {
      out.add(table);
      out.add(const SizedBox(height: 6));
    }
    final totals = _totals();
    if (totals != null) {
      out.add(totals);
      out.add(const SizedBox(height: 6));
    }
    final footer = _footer();
    if (footer != null) out.add(footer);

    if (out.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              'Everything is hidden',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 8),
            ),
          ),
        ),
      ];
    }
    return out;
  }

  Widget? _header() {
    if (!_showHeader) return null;
    final title = settings.invoiceTitle.trim().isEmpty
        ? BillSettings.defaultInvoiceTitle
        : settings.invoiceTitle.trim().toUpperCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF9CA3AF))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: settings.showShopLogo && settings.shopLogoBase64 != null
                ? _logo(settings.shopLogoBase64!)
                : const SizedBox(),
          ),
          Expanded(
            child: settings.showInvoiceTitle
                ? Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : const SizedBox(),
          ),
          const SizedBox(width: 26),
        ],
      ),
    );
  }

  Widget _logo(String base64Value) {
    try {
      return SizedBox(
        height: 22,
        child: Image.memory(base64Decode(base64Value), fit: BoxFit.contain),
      );
    } catch (_) {
      return const SizedBox();
    }
  }

  Widget? _partyBlock() {
    final seller = _sellerLines();
    final buyer = _buyerLines();
    if (seller.isEmpty && buyer.isEmpty) return null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (seller.isNotEmpty)
          Expanded(child: _infoBox('Seller / From', seller)),
        if (seller.isNotEmpty && buyer.isNotEmpty) const SizedBox(width: 6),
        if (buyer.isNotEmpty)
          Expanded(child: _infoBox('Buyer / Bill To', buyer)),
      ],
    );
  }

  Widget _infoBox(String title, List<String> lines) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF9CA3AF), width: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 7.5),
          ),
          const SizedBox(height: 3),
          ...lines.map((l) => Text(l)),
        ],
      ),
    );
  }

  List<String> _sellerLines() => [
    if (settings.showShopName) _PreviewSample.shopName,
    if (settings.showShopAddress) _PreviewSample.shopAddress,
    if (settings.showShopPhone) 'Phone: ${_PreviewSample.shopPhone}',
    if (settings.showShopEmail) 'Email: ${_PreviewSample.shopEmail}',
    if (settings.showShopGstin) 'GSTIN: ${_PreviewSample.shopGstin}',
  ];

  List<String> _buyerLines() => [
    if (settings.showCustomerName) _PreviewSample.customerLegalName,
    if (settings.showCustomerTradeName)
      'Trade Name: ${_PreviewSample.customerTradeName}',
    if (settings.showCustomerLegalName)
      'Legal Name: ${_PreviewSample.customerLegalName}',
    if (settings.showCustomerName) 'Contact: ${_PreviewSample.customerName}',
    if (settings.showCustomerGstin) 'GSTIN: ${_PreviewSample.customerGstin}',
    if (settings.showCustomerPhone) 'Phone: ${_PreviewSample.customerPhone}',
    if (settings.showCustomerAddress)
      'Address: ${_PreviewSample.customerAddress}',
    if (settings.showCustomerPlaceOfSupply)
      'Place of Supply: ${_PreviewSample.placeOfSupply}',
  ];

  Widget? _meta() {
    final cells = <List<String>>[
      if (settings.showInvoiceNumber) ['INVOICE NO', _PreviewSample.invoiceNo],
      if (settings.showInvoiceDate) ['DATE', _PreviewSample.invoiceDate],
      if (settings.showInvoicePlaceOfSupply)
        ['PLACE OF SUPPLY', _PreviewSample.placeOfSupply],
      if (settings.showInvoiceSupplyType)
        ['SUPPLY TYPE', _PreviewSample.supplyType],
    ];
    if (cells.isEmpty) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        border: Border.all(color: const Color(0xFF9CA3AF), width: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        children: [
          for (final c in cells)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c[0],
                    style: const TextStyle(
                      fontSize: 5.5,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    c[1],
                    style: const TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget? _itemsTable() {
    final showGst = settings.showGstBreakdown;
    final cols = <_PreviewCol>[
      if (settings.showItemSerialColumn)
        const _PreviewCol('#', 0.4, TextAlign.center, _ColKind.serial),
      if (settings.showItemNameColumn)
        const _PreviewCol('Item', 2.4, TextAlign.left, _ColKind.data, 0),
      if (settings.showHsnColumn)
        const _PreviewCol('HSN', 0.8, TextAlign.right, _ColKind.data, 1),
      if (settings.showQuantityColumn)
        const _PreviewCol('Qty', 0.7, TextAlign.right, _ColKind.data, 2),
      if (settings.showRateColumn)
        const _PreviewCol('Rate', 0.9, TextAlign.right, _ColKind.data, 3),
      if (showGst && settings.showGstPercentColumn)
        const _PreviewCol('GST %', 0.7, TextAlign.right, _ColKind.data, 4),
      if (showGst && settings.showGstAmountColumn)
        const _PreviewCol('GST', 0.9, TextAlign.right, _ColKind.data, 5),
      if (settings.showAmountColumn)
        const _PreviewCol('Amount', 1.0, TextAlign.right, _ColKind.data, 6),
    ];
    if (cols.isEmpty) return null;

    const border = BorderSide(color: Color(0xFF9CA3AF), width: 0.5);
    Widget cell(String text, _PreviewCol col, {bool header = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
        decoration: const BoxDecoration(
          border: Border(right: border, bottom: border),
        ),
        child: Text(
          text,
          textAlign: col.align,
          style: TextStyle(
            fontSize: 6.5,
            fontWeight: header ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }

    TableRow row(List<String>? item, int? serial) {
      return TableRow(
        decoration: item == null
            ? const BoxDecoration(color: Color(0xFFE5E7EB))
            : null,
        children: [
          for (final col in cols)
            cell(
              item == null
                  ? col.label
                  : col.kind == _ColKind.serial
                  ? '$serial'
                  : item[col.dataIndex],
              col,
              header: item == null,
            ),
        ],
      );
    }

    return Container(
      decoration: const BoxDecoration(
        border: Border(left: border, top: border),
      ),
      child: Table(
        columnWidths: {
          for (var i = 0; i < cols.length; i++)
            i: FlexColumnWidth(cols[i].flex),
        },
        children: [
          row(null, null),
          for (var i = 0; i < _PreviewSample.items.length; i++)
            row(_PreviewSample.items[i], i + 1),
        ],
      ),
    );
  }

  Widget? _totals() {
    final showGst = settings.showGstBreakdown;
    final rows = <List<dynamic>>[
      if (settings.showSubtotal) ['Subtotal', _PreviewSample.subtotal, false],
      if (settings.showDiscount)
        ['Discount (5%)', _PreviewSample.discount, false],
      if (showGst && settings.showTaxableAmount)
        ['Taxable Amount', _PreviewSample.taxable, false],
      if (showGst && settings.showCgstSgstIgst)
        ['CGST', _PreviewSample.cgst, false],
      if (showGst && settings.showCgstSgstIgst)
        ['SGST', _PreviewSample.sgst, false],
      if (showGst && settings.showGstTotal)
        ['GST Total', _PreviewSample.gstTotal, false],
      if (settings.showGrandTotal)
        ['Grand total', _PreviewSample.grandTotal, true],
    ];
    if (rows.isEmpty) return null;
    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 150,
        child: Column(
          children: [
            for (final r in rows)
              _totalRow(r[0] as String, r[1] as String, r[2] as bool),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, String value, bool bold) {
    final style = TextStyle(
      fontSize: bold ? 8.5 : 7,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Column(
      children: [
        if (bold) const Divider(height: 6, color: Color(0xFFD1D5DB)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              Expanded(child: Text(label, style: style)),
              Text('Rs. $value', style: style),
            ],
          ),
        ),
      ],
    );
  }

  Widget? _footer() {
    final hasSignature = settings.showDigitalSignature &&
        settings.digitalSignatureBase64 != null;
    final footerText =
        settings.showFooterText ? settings.footerText.trim() : '';
    if (footerText.isEmpty && !hasSignature) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 8, color: Color(0xFF9CA3AF)),
        if (footerText.isNotEmpty)
          Text(
            footerText,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 7.5),
          ),
        if (hasSignature) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              children: [
                SizedBox(
                  height: 22,
                  child: _logo(settings.digitalSignatureBase64!),
                ),
                Container(
                  width: 70,
                  height: 0.5,
                  color: const Color(0xFF6B7280),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Authorised signature',
                  style: TextStyle(fontSize: 6),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

enum _ColKind { serial, data }

class _PreviewCol {
  final String label;
  final double flex;
  final TextAlign align;
  final _ColKind kind;
  final int dataIndex;

  const _PreviewCol(this.label, this.flex, this.align, this.kind,
      [this.dataIndex = 0]);
}
