import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../db/database_helper.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import '../utils/pdf_generator.dart';

/// Print product labels: choose products and copies, A4 sheet or a thermal
/// label roll, QR code or barcode.
class QrSheetScreen extends StatefulWidget {
  final List<Product> products;

  const QrSheetScreen({super.key, required this.products});

  @override
  State<QrSheetScreen> createState() => _QrSheetScreenState();
}

class _QrSheetScreenState extends State<QrSheetScreen> {
  late List<Product> _products = widget.products;

  /// Labels per product id (0 = skip). Starts at one each.
  late final Map<int, int> _copies = {
    for (final p in widget.products)
      if (p.id != null) p.id!: 1,
  };
  LabelLayout _layout = LabelLayout.a4Sheet;
  String _codeType = PdfGenerator.codeTypeQr;
  int _columns = 3;
  int _rows = 8;
  bool _assigning = false;

  List<LabelRequest> get _requests => [
    for (final p in _products)
      if ((_copies[p.id] ?? 0) > 0) LabelRequest(p, _copies[p.id]!),
  ];

  int get _labelCount => _requests.fold(0, (s, r) => s + r.copies);

  List<Product> get _withoutCode => [
    for (final r in _requests)
      if (r.product.barcode == null && r.product.productCode == null) r.product,
  ];

  Future<void> _assignShortCodes() async {
    setState(() => _assigning = true);
    try {
      final db = DatabaseHelper.instance;
      await db.assignShortCodes(_withoutCode.map((p) => p.id!));
      final fresh = await db.getAllProducts();
      if (!mounted) return;
      setState(() {
        _products = [
          for (final p in _products) fresh.firstWhere((f) => f.id == p.id),
        ];
        _assigning = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _assigning = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  Future<void> _chooseProducts() async {
    final result = await showModalBottomSheet<Map<int, int>>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _CopiesSheet(products: _products, copies: Map.of(_copies)),
    );
    if (!mounted || result == null) return;
    setState(
      () => _copies
        ..clear()
        ..addAll(result),
    );
  }

  @override
  Widget build(BuildContext context) {
    final requests = _requests;
    final pages = PdfGenerator.pageCount(
      _labelCount,
      layout: _layout,
      columns: _columns,
      rows: _rows,
    );
    final missingCodes = _codeType == PdfGenerator.codeTypeBarcode
        ? _withoutCode.length
        : 0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: navyAppBar(title: 'Product labels'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    key: const ValueKey('labels-choose-products'),
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.checklist_rounded),
                    title: Text(
                      '$_labelCount labels · ${requests.length} products',
                    ),
                    subtitle: Text(
                      '$pages ${pages == 1 ? 'page' : 'pages'} · tap to '
                      'choose products and copies',
                      style: AppText.caption,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _chooseProducts,
                  ),
                  DropdownButtonFormField<LabelLayout>(
                    initialValue: _layout,
                    decoration: const InputDecoration(labelText: 'Print on'),
                    items: [
                      for (final layout in LabelLayout.values)
                        DropdownMenuItem(
                          value: layout,
                          child: Text(layout.label),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _layout = value ?? _layout),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: PdfGenerator.codeTypeQr,
                        icon: Icon(Icons.qr_code_2_rounded),
                        label: Text('QR code'),
                      ),
                      ButtonSegment(
                        value: PdfGenerator.codeTypeBarcode,
                        icon: Icon(Icons.view_week_outlined),
                        label: Text('Barcode'),
                      ),
                    ],
                    selected: {_codeType},
                    onSelectionChanged: (v) =>
                        setState(() => _codeType = v.first),
                  ),
                  if (_layout == LabelLayout.a4Sheet) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: _Stepper(
                            label: 'Columns',
                            value: _columns,
                            min: 1,
                            max: 6,
                            onChanged: (v) => setState(() => _columns = v),
                          ),
                        ),
                        Expanded(
                          child: _Stepper(
                            label: 'Rows',
                            value: _rows,
                            min: 1,
                            max: 14,
                            onChanged: (v) => setState(() => _rows = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (missingCodes > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '$missingCodes products have no barcode or code, so '
                      'their barcodes would be very long.',
                      style: AppText.caption.copyWith(color: AppColors.error),
                    ),
                    TextButton.icon(
                      onPressed: _assigning ? null : _assignShortCodes,
                      icon: const Icon(Icons.auto_fix_high_rounded),
                      label: Text(
                        _assigning ? 'Assigning…' : 'Give them short codes',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: requests.isEmpty
                ? const AppEmptyState(
                    icon: Icons.label_off_outlined,
                    title: 'No labels selected',
                    message: 'Choose products and how many labels each.',
                  )
                : PdfPreview(
                    key: ValueKey(
                      '${_layout.name}_${_codeType}_${_columns}_${_rows}_'
                      '${requests.map((r) => '${r.product.id}x${r.copies}${r.product.productCode}').join(',')}',
                    ),
                    build: (_) => PdfGenerator.generate(
                      requests,
                      layout: _layout,
                      columns: _columns,
                      rows: _rows,
                      codeType: _codeType,
                    ),
                    allowPrinting: true,
                    allowSharing: true,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    pdfFileName: 'storely_labels.pdf',
                  ),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: AppText.caption),
        IconButton(
          tooltip: 'Fewer $label',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$value', style: AppText.subtitle),
        IconButton(
          tooltip: 'More $label',
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}

/// Pick products and the number of labels for each. Pops the new counts.
class _CopiesSheet extends StatefulWidget {
  final List<Product> products;
  final Map<int, int> copies;

  const _CopiesSheet({required this.products, required this.copies});

  @override
  State<_CopiesSheet> createState() => _CopiesSheetState();
}

class _CopiesSheetState extends State<_CopiesSheet> {
  late final Map<int, int> _copies = widget.copies;
  String _query = '';

  void _setAll(int Function(Product p) count) => setState(() {
    for (final p in widget.products) {
      if (p.id != null) _copies[p.id!] = count(p).clamp(0, 500);
    }
  });

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final p in widget.products)
        if (p.id != null &&
            (q.isEmpty ||
                p.name.toLowerCase().contains(q) ||
                (p.productCode?.toLowerCase().contains(q) ?? false) ||
                (p.barcode?.toLowerCase().contains(q) ?? false)))
          p,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Labels per product', style: AppText.title),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search products',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  ActionChip(
                    label: const Text('1 each'),
                    onPressed: () => _setAll((_) => 1),
                  ),
                  ActionChip(
                    label: const Text('Match stock'),
                    onPressed: () => _setAll(
                      (p) => p.trackStock && p.quantity > 0
                          ? p.quantity.ceil()
                          : 0,
                    ),
                  ),
                  ActionChip(
                    label: const Text('None'),
                    onPressed: () => _setAll((_) => 0),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) {
                    final p = shown[i];
                    final n = _copies[p.id] ?? 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      subtitle: Text(
                        p.trackStock ? 'In stock: ${p.quantityLabel}' : '',
                        style: AppText.caption,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Fewer',
                            onPressed: n > 0
                                ? () => setState(() => _copies[p.id!] = n - 1)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text(
                              '$n',
                              textAlign: TextAlign.center,
                              style: AppText.subtitle,
                            ),
                          ),
                          IconButton(
                            tooltip: 'More',
                            onPressed: () =>
                                setState(() => _copies[p.id!] = n + 1),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, _copies),
                child: const Text('Done'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}
