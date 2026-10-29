part of '../products_screen.dart';

/// Local composer. Only completed line edits are staged; unfinished sheets remain
/// editable until the user adds the line. No stock changes before confirmation.
class NewPurchaseScreen extends StatefulWidget {
  final PurchaseComposerDraft initialDraft;
  final List<Product> catalog;
  final List<String> suppliers;
  final Future<String?> Function() addSupplier;
  final Future<String?> Function(BuildContext) scanBarcode;
  final Future<PurchaseDraftLine?> Function(Set<String>, DateTime, String?)
  addProduct;
  final Future<PurchaseDraftLine?> Function(
    PurchaseDraftLine,
    Set<String>,
    DateTime,
    String?,
  )
  editProduct;
  final Future<List<Product>?> Function(BuildContext) pickAndParseImport;
  final Future<int> Function(PurchaseComposerDraft) commitBatch;

  const NewPurchaseScreen({
    super.key,
    required this.initialDraft,
    required this.catalog,
    required this.suppliers,
    required this.addSupplier,
    required this.scanBarcode,
    required this.addProduct,
    required this.editProduct,
    required this.pickAndParseImport,
    required this.commitBatch,
  });
  @override
  State<NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends State<NewPurchaseScreen> {
  late PurchaseComposerDraft _saved;
  late DateTime _date;
  String? _supplier;
  late List<String> _suppliers;
  late List<PurchaseDraftLine> _lines;
  late List<Product> _imports;
  bool _saving = false;
  bool _committing = false;
  String? _saveError;
  bool get _busy => _saving || _committing;
  Set<String> get _names => _lines.map((l) => l.name.toLowerCase()).toSet();

  @override
  void initState() {
    super.initState();
    CloudService.instance.state.addListener(_accessChanged);
    _saved = widget.initialDraft;
    _date = _saved.date;
    _supplier = _saved.supplier;
    _suppliers = List.from(widget.suppliers);
    _lines = List.from(_saved.lines);
    _imports = List.from(_saved.importedRows);
  }

  void _accessChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CloudService.instance.state.removeListener(_accessChanged);
    super.dispose();
  }

  Future<void> _leaveUnsaved() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave without saving recent edits?'),
        content: const Text(
          'Your previously saved draft is preserved. Recent edits could not be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  void _error(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }

  Future<void> _persist() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final next = _saved.copyWith(
        date: _date,
        supplier: _supplier,
        clearSupplier: _supplier == null,
        lines: List.from(_lines),
        importedRows: List.from(_imports),
      );
      _saved = await DatabaseHelper.instance.savePurchaseDraft(next);
    } catch (error) {
      _saveError = friendlyError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _validLine(PurchaseDraftLine line) {
    try {
      purchaseDecimal(line.quantityAdded);
      purchaseDecimal(line.product.purchasePrice);
      return true;
    } catch (error) {
      _error(error);
      return false;
    }
  }

  Future<void> _addNew() async {
    final line = await widget.addProduct(_names, _date, _supplier);
    if (!mounted || line == null) return;
    if (!_validLine(line)) return;
    _lines.add(line);
    await _persist();
  }

  Future<void> _addExisting() async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PurchaseProductPicker(
        products: widget.catalog,
        scanBarcode: widget.scanBarcode,
      ),
    );
    if (!mounted || product == null) return;
    final line = await showModalBottomSheet<PurchaseDraftLine>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PurchaseRestockSheet(product: product),
    );
    if (!mounted || line == null) return;
    if (!_validLine(line)) return;
    _lines.add(line);
    await _persist();
  }

  Future<void> _edit(int index) async {
    final line = _lines[index];
    final updated = line.isRestock
        ? await showModalBottomSheet<PurchaseDraftLine>(
            context: context,
            isScrollControlled: true,
            builder: (_) =>
                PurchaseRestockSheet(product: line.restockTarget!, line: line),
          )
        : await widget.editProduct(
            line,
            _names..remove(line.name.toLowerCase()),
            _date,
            _supplier,
          );
    if (!mounted || updated == null) return;
    if (!_validLine(updated)) return;
    _lines[index] = updated;
    _imports.clear();
    await _persist();
  }

  Product? _importTarget(Product row) {
    final code = row.productCode?.trim().toLowerCase();
    final barcode = row.barcode?.trim().toLowerCase();
    final identified = widget.catalog
        .where(
          (p) =>
              (code != null && p.productCode?.toLowerCase() == code) ||
              (barcode != null && p.barcode?.toLowerCase() == barcode),
        )
        .toList();
    final named = widget.catalog
        .where((p) => p.name.toLowerCase() == row.name.trim().toLowerCase())
        .toList();
    if (identified.length > 1 || (identified.isEmpty && named.length > 1)) {
      throw ArgumentError(
        'Multiple products match "${row.name}". Correct the file code/barcode or choose the product manually.',
      );
    }
    final match = identified.isNotEmpty
        ? identified.single
        : named.isEmpty
        ? null
        : named.single;
    if (match != null) {
      if ((code != null && code != match.productCode?.toLowerCase()) ||
          (barcode != null && barcode != match.barcode?.toLowerCase())) {
        throw ArgumentError(
          'Code/barcode differs for "${row.name}". Correct the file or choose the product manually.',
        );
      }
      if (!match.trackStock) {
        throw ArgumentError(
          '"${match.name}" does not track stock. Use Add product for catalog changes.',
        );
      }
      if (row.unit != null &&
          row.unit!.trim().toLowerCase() !=
              (match.unit ?? 'pcs').trim().toLowerCase()) {
        throw ArgumentError(
          'Convert "${row.name}" to ${match.unit ?? 'pcs'} in the file before importing.',
        );
      }
    }
    return match;
  }

  Future<void> _import() async {
    try {
      final parsed = await widget.pickAndParseImport(context);
      if (!mounted || parsed == null) return;
      if (_lines.length + parsed.length > 200) {
        throw ArgumentError('Use up to 200 purchase rows.');
      }
      // Keep distinct rates and lots; never sum rows merely by product name.
      final rows = [
        for (final p in parsed)
          p.copyWith(supplier: _supplier, clearSupplier: _supplier == null),
      ];
      for (final row in rows) {
        purchaseDecimal(row.quantity);
        purchaseDecimal(row.purchasePrice);
        _importTarget(row);
      }
      if (await DatabaseHelper.instance.wouldImportDuplicate(
            rows,
            purchaseDate: _date,
          ) &&
          mounted) {
        final again = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Already imported?'),
            content: const Text(
              'These items were imported before. Import again only for another real purchase.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Import again'),
              ),
            ],
          ),
        );
        if (again != true) return;
      }
      if (!mounted) return;
      for (final row in rows) {
        final match = _importTarget(row);
        _imports.add(row);
        _lines.add(
          PurchaseDraftLine(
            product: match == null
                ? row
                : match.copyWith(
                    quantity: row.quantity,
                    purchasePrice: row.purchasePrice,
                    source: ProductSource.imported,
                    purchaseBatchNo: row.purchaseBatchNo,
                    purchaseExpiry: row.purchaseExpiry,
                  ),
            quantityAdded: row.quantity,
            restockTarget: match,
          ),
        );
      }
      await _persist();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _datePicker() async {
    final todayUtc = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    final today = DateTime(todayUtc.year, todayUtc.month, todayUtc.day);
    final date = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (date == null || !mounted) return;
    _date = date;
    await _persist();
  }

  Future<void> _addSupplier() async {
    try {
      final supplier = await widget.addSupplier();
      if (!mounted || supplier == null) return;
      if (!_suppliers.contains(supplier)) _suppliers.add(supplier);
      _supplier = supplier;
      await _persist();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _discard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard purchase draft?'),
        content: const Text(
          'Remove the saved draft and all staged lines? Stock has not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    try {
      await DatabaseHelper.instance.discardPurchaseDraft(_saved);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _confirm() async {
    if (_busy || _saveError != null || _lines.isEmpty) return;
    setState(() => _committing = true);
    try {
      final count = await widget.commitBatch(_saved);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('Purchase saved · $count item(s)')),
      );
    } catch (error) {
      if (mounted) setState(() => _committing = false);
      _error(error);
    }
  }

  BigInt get _subtotal => _lines.fold(
    BigInt.zero,
    (sum, line) =>
        sum +
        purchaseLineCents(
          purchaseDecimal(line.quantityAdded),
          purchaseDecimal(line.product.purchasePrice),
        ),
  );

  @override
  Widget build(BuildContext context) {
    final allowed =
        DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true;
    return PopScope(
      canPop: !_busy && _saveError == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy && _saveError != null) _leaveUnsaved();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Add purchase'),
          actions: [
            IconButton(
              tooltip: 'Discard draft',
              onPressed: _busy || !allowed ? null : _discard,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: !allowed
            ? const Center(
                child: Text(
                  'Purchases are available to owners and admins. Your draft is preserved.',
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text(
                    _saving
                        ? 'Saving draft…'
                        : _saveError == null
                        ? 'Draft saved on this device · header and added items'
                        : 'Draft not saved: $_saveError',
                    style: TextStyle(
                      color: _saveError == null
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (_saveError != null)
                    TextButton(
                      onPressed: _busy ? null : _persist,
                      child: const Text('Retry saving draft'),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _datePicker,
                    icon: const Icon(Icons.event_outlined),
                    label: Text('Purchase date: ${_formatFullDate(_date)}'),
                  ),
                  const SizedBox(height: 12),
                  IgnorePointer(
                    ignoring: _busy,
                    child: _OptionDropdown(
                      key: ValueKey(_supplier),
                      label: 'Supplier (optional)',
                      value: _supplier,
                      noValueLabel: 'No supplier',
                      options: _suppliers,
                      onChanged: (value) {
                        _supplier = value;
                        _persist();
                      },
                      onAdd: _addSupplier,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy || _lines.length >= 200
                        ? null
                        : _addExisting,
                    icon: const Icon(Icons.search),
                    label: const Text('Search or scan existing product'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy || _lines.length >= 200
                            ? null
                            : _addNew,
                        icon: const Icon(Icons.add),
                        label: const Text('Add new product'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _import,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Import file'),
                      ),
                    ],
                  ),
                  if (_lines.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        'Add items to this purchase. Stock changes only when you save the purchase.',
                      ),
                    ),
                  for (var i = 0; i < _lines.length; i++) _lineCard(i),
                ],
              ),
        bottomNavigationBar: !allowed
            ? null
            : SafeArea(
                minimum: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Stock cost subtotal: ${purchaseMoney(purchaseCentsText(_subtotal))}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text('Payment not recorded'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy || _saveError != null || _lines.isEmpty
                          ? null
                          : _confirm,
                      child: Text(
                        _committing
                            ? 'Saving purchase…'
                            : 'Save purchase (${_lines.length})',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _lineCard(int index) {
    final line = _lines[index];
    final amount = purchaseCentsText(
      purchaseLineCents(
        purchaseDecimal(line.quantityAdded),
        purchaseDecimal(line.product.purchasePrice),
      ),
    );
    return Card(
      child: ListTile(
        onTap: _busy ? null : () => _edit(index),
        title: Text(line.name),
        subtitle: Text(
          '${line.isRestock ? 'Restock' : 'New product'} · ${purchaseDecimal(line.quantityAdded)} ${line.product.unit ?? ''} × ${purchaseMoney(purchaseDecimal(line.product.purchasePrice))}\n${purchaseMoney(amount)}',
        ),
        trailing: IconButton(
          tooltip: 'Remove ${line.name}',
          onPressed: _busy
              ? null
              : () async {
                  _lines.removeAt(index);
                  // An edited/removed import no longer claims the original whole-file key.
                  _imports.clear();
                  await _persist();
                },
          icon: const Icon(Icons.close),
        ),
      ),
    );
  }
}
