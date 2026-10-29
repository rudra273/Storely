part of '../products_screen.dart';

class _ImportReviewRow {
  final int number;
  final Product? product;
  final String? parseError;
  final TextEditingController quantity;
  final TextEditingController cost;
  bool included = true;
  String? selection;
  _ImportReviewRow(this.number, this.product, this.parseError)
    : quantity = TextEditingController(
        text: product?.quantity.toString() ?? '',
      ),
      cost = TextEditingController(
        text: product?.purchasePrice.toString() ?? '',
      );
}

/// Preview is deliberately local and read-only. Each name-only match requires a choice.
class PurchaseImportReviewScreen extends StatefulWidget {
  final ImportParseResult parsed;
  final List<Product> catalog;
  final String fingerprint;
  final bool possibleDuplicate;
  const PurchaseImportReviewScreen({
    super.key,
    required this.parsed,
    required this.catalog,
    required this.fingerprint,
    required this.possibleDuplicate,
  });
  @override
  State<PurchaseImportReviewScreen> createState() =>
      _PurchaseImportReviewScreenState();
}

class _PurchaseImportReviewScreenState
    extends State<PurchaseImportReviewScreen> {
  late List<_ImportReviewRow> rows;
  bool approved = false;
  bool get _allowed =>
      DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true;
  String? _norm(String? value) => value?.trim().toLowerCase();
  List<Product> _strong(Product p) => widget.catalog
      .where(
        (c) =>
            (_norm(p.productCode) != null &&
                _norm(p.productCode) == _norm(c.productCode)) ||
            (_norm(p.barcode) != null && _norm(p.barcode) == _norm(c.barcode)),
      )
      .toList();
  List<Product> _named(Product p) =>
      widget.catalog.where((c) => _norm(c.name) == _norm(p.name)).toList();

  @override
  void initState() {
    super.initState();
    CloudService.instance.state.addListener(_accessChanged);
    rows = [
      for (final row in widget.parsed.rows)
        _ImportReviewRow(row.number, row.product, null),
      for (final row in widget.parsed.errors)
        _ImportReviewRow(row.row, null, row.message),
    ]..sort((a, b) => a.number.compareTo(b.number));
    // Test/legacy callers may provide the old result shape without numbered rows.
    if (widget.parsed.rows.isEmpty && widget.parsed.products.isNotEmpty) {
      rows.addAll([
        for (var i = 0; i < widget.parsed.products.length; i++)
          _ImportReviewRow(i + 2, widget.parsed.products[i], null),
      ]);
      rows.sort((a, b) => a.number.compareTo(b.number));
    }
    final createdByIdentifier = <String, String>{};
    for (final row in rows) {
      final p = row.product;
      if (p == null) continue;
      final strong = _strong(p);
      if (strong.length == 1) {
        row.selection = 'existing:${strong.single.uuid}';
      } else if (strong.isEmpty && _named(p).isEmpty) {
        final identifiers = [
          if (p.productCode != null) 'code:${_norm(p.productCode)}',
          if (p.barcode != null) 'barcode:${_norm(p.barcode)}',
        ];
        final earlier = identifiers
            .map((id) => createdByIdentifier[id])
            .whereType<String>()
            .toSet();
        row.selection = earlier.length == 1
            ? earlier.single
            : 'new:${row.number}';
        for (final id in identifiers) {
          createdByIdentifier[id] = row.selection!;
        }
      }
    }
  }

  void _accessChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CloudService.instance.state.removeListener(_accessChanged);
    for (final row in rows) {
      row.quantity.dispose();
      row.cost.dispose();
    }
    super.dispose();
  }

  String? _rowProblem(_ImportReviewRow row) {
    if (!row.included) return null;
    if (row.number > 2020) {
      return 'Row number exceeds 2020. Split the file or exclude this row.';
    }
    if (row.parseError != null) {
      return '${row.parseError} Exclude this row or fix the file.';
    }
    final p = row.product!;
    final strong = _strong(p);
    if (strong.length > 1) {
      return 'Code and barcode point to different products. Fix the file or exclude this row.';
    }
    if (row.selection == null) {
      return 'Choose an existing product or create a new product.';
    }
    if (row.selection!.startsWith('existing:')) {
      final id = row.selection!.substring('existing:'.length);
      final matches = widget.catalog.where((p) => p.uuid == id).toList();
      if (matches.length != 1 || !matches.single.trackStock) {
        return 'Choose a tracked product.';
      }
      final selected = matches.single;
      if ((p.productCode != null &&
              _norm(p.productCode) != _norm(selected.productCode)) ||
          (p.barcode != null && _norm(p.barcode) != _norm(selected.barcode))) {
        return 'Code or barcode differs from this product. Correct the file or create a different product.';
      }
      if (p.unit != null && _norm(p.unit) != _norm(selected.unit ?? 'pcs')) {
        return 'Convert quantity to ${selected.unit ?? 'pcs'} in the file before importing.';
      }
    } else if (strong.isNotEmpty) {
      return 'This code or barcode already belongs to a product. Select it or fix the file.';
    }
    final qty = double.tryParse(row.quantity.text.trim());
    final cost = double.tryParse(row.cost.text.trim());
    try {
      if (qty == null || qty <= 0 || cost == null) {
        return 'Enter a positive quantity and a non-negative unit cost.';
      }
      purchaseDecimal(qty);
      purchaseDecimal(cost);
    } catch (_) {
      return 'Use non-negative numbers with up to four decimal places.';
    }
    return null;
  }

  List<DropdownMenuItem<String>> _choices(_ImportReviewRow row) {
    final p = row.product!;
    final candidates = {
      ..._strong(p),
      ..._named(p),
    }.where((p) => p.trackStock).toList();
    final options = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: 'new:${row.number}',
        child: const Text('Create new product'),
      ),
      for (final c in candidates)
        DropdownMenuItem(
          value: 'existing:${c.uuid}',
          child: Text(
            'Existing: ${c.name} · ${c.productCode ?? c.barcode ?? c.unit ?? 'no code'}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    for (final prior in rows.where(
      (r) => r.number < row.number && r.product != null,
    )) {
      if (!prior.selection.toString().startsWith('new:')) continue;
      if (options.any((o) => o.value == prior.selection)) continue;
      options.add(
        DropdownMenuItem(
          value: prior.selection,
          child: Text(
            'Same new product as row ${prior.number}: ${prior.product!.name}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    // A source row may remain linked even if the original row was excluded.
    if (row.selection != null &&
        !options.any((o) => o.value == row.selection)) {
      options.add(
        DropdownMenuItem(
          value: row.selection,
          child: Text(
            'Linked product: ${p.name}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return options;
  }

  String? _lineAmount(_ImportReviewRow row) {
    final quantity = double.tryParse(row.quantity.text.trim());
    final cost = double.tryParse(row.cost.text.trim());
    if (quantity == null || cost == null || quantity <= 0) return null;
    try {
      return purchaseMoney(
        purchaseCentsText(
          purchaseLineCents(purchaseDecimal(quantity), purchaseDecimal(cost)),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void _stage() {
    if (!_allowed) return;
    final included = rows.where((r) => r.included).toList();
    if (included.isEmpty) {
      _message('Select at least one valid row.');
      return;
    }
    final problematic = included.where((r) => _rowProblem(r) != null).toList();
    if (problematic.isNotEmpty) {
      _message('Review row ${problematic.first.number} before adding.');
      return;
    }
    if (widget.possibleDuplicate && !approved) {
      _message('Confirm that this is an intentional repeat.');
      return;
    }
    final staged = <PurchaseImportChoice>[];
    final newMetadata = <String, String>{};
    for (final row in included) {
      final p = row.product!.copyWith(
        quantity: double.parse(row.quantity.text.trim()),
        purchasePrice: double.parse(row.cost.text.trim()),
      );
      final selection = row.selection!;
      if (selection.startsWith('existing:')) {
        final id = selection.substring('existing:'.length);
        final existing = widget.catalog.singleWhere((c) => c.uuid == id);
        staged.add(
          PurchaseImportChoice(
            number: row.number,
            product: p,
            existing: existing,
          ),
        );
      } else {
        final data = PurchaseDraftLine.productJson(p)
          ..removeWhere(
            (key, _) => {
              'quantity_cache',
              'purchase_price',
              'purchase_batch_no',
              'purchase_expiry',
              'created_at',
              'updated_at',
            }.contains(key),
          );
        final signature = jsonEncode(data);
        if (newMetadata.containsKey(selection) &&
            newMetadata[selection] != signature) {
          _message(
            'Rows linked to one new product must have identical product details. Fix the file or choose separate products.',
          );
          return;
        }
        newMetadata[selection] = signature;
        staged.add(
          PurchaseImportChoice(
            number: row.number,
            product: p,
            newProductKey: '${widget.fingerprint}:$selection',
          ),
        );
      }
    }
    Navigator.pop(
      context,
      ReviewedPurchaseImport(
        fingerprint: widget.fingerprint,
        rows: staged,
        duplicateApproved: approved,
      ),
    );
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Review purchase file')),
    body: !_allowed
        ? const Center(
            child: Text('Purchase review is available to owners and admins.'),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Review every row. Name matches need your choice. Existing products keep their pricing rules.',
              ),
              const Text(
                'Your choices are saved after you add the reviewed rows. Duplicate checks use stock history on this device; web imports may not match yet.',
              ),
              for (final warning in widget.parsed.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(warning),
                ),
              if (widget.possibleDuplicate)
                CheckboxListTile(
                  value: approved,
                  onChanged: (v) => setState(() => approved = v == true),
                  title: const Text('This file may already be recorded'),
                  subtitle: const Text(
                    'Confirm only if this is another real purchase.',
                  ),
                ),
              for (final row in rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Row ${row.number}: ${row.product?.name ?? 'Invalid row'}',
                          ),
                          subtitle: Text(
                            row.included ? 'Included' : 'Excluded',
                          ),
                          value: row.included,
                          onChanged: (v) => setState(() => row.included = v),
                        ),
                        if (row.product != null && row.included) ...[
                          DropdownButtonFormField<String>(
                            key: ValueKey('choice-${row.number}'),
                            initialValue: row.selection,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Product match',
                            ),
                            hint: const Text('Choose a product'),
                            items: _choices(row),
                            onChanged: (v) => setState(() => row.selection = v),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: row.quantity,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    labelText:
                                        'Quantity (${row.product!.unit ?? 'pcs'})',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: row.cost,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    labelText: 'Unit cost',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_lineAmount(row) != null)
                            Text('Line total: ${_lineAmount(row)}'),
                          if (row.product!.purchaseBatchNo != null)
                            Text('Batch: ${row.product!.purchaseBatchNo}'),
                          if (row.product!.purchaseExpiry != null)
                            Text(
                              'Expiry: ${_formatFullDate(row.product!.purchaseExpiry!)}',
                            ),
                        ],
                        if (_rowProblem(row) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _rowProblem(row)!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
    bottomNavigationBar: !_allowed
        ? null
        : SafeArea(
            minimum: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _stage,
              child: const Text('Add reviewed rows'),
            ),
          ),
  );
}
