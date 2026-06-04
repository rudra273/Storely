part of '../products_screen.dart';

class _NewPurchaseScreen extends StatefulWidget {
  final DateTime purchaseDate;
  final String? supplier;

  /// Opens the detail editor in staging mode; returns a draft (or null).
  /// [stagedNames] are lowercase names already in the batch (blocked as dups).
  final Future<_PurchaseDraft?> Function(Set<String> stagedNames) addProduct;

  /// Edits an existing staged draft; returns the updated draft (or null).
  final Future<_PurchaseDraft?> Function(
    _PurchaseDraft draft,
    Set<String> stagedNames,
  )
  editProduct;

  /// Picks + parses an import file (loading spinner over the given context).
  final Future<List<Product>?> Function(BuildContext dialogContext)
  pickAndParseImport;

  /// Finds a matching existing catalog product by name, or null.
  final Product? Function(String name) matchExisting;

  /// Commits the batch; returns the number of items written.
  final Future<int> Function(List<_PurchaseDraft> drafts, DateTime purchaseDate)
  commitBatch;

  const _NewPurchaseScreen({
    required this.purchaseDate,
    required this.supplier,
    required this.addProduct,
    required this.editProduct,
    required this.pickAndParseImport,
    required this.matchExisting,
    required this.commitBatch,
  });

  @override
  State<_NewPurchaseScreen> createState() => _NewPurchaseScreenState();
}

class _NewPurchaseScreenState extends State<_NewPurchaseScreen> {
  final List<_PurchaseDraft> _drafts = [];
  var _committing = false;

  Set<String> get _stagedNames =>
      _drafts.map((d) => d.name.toLowerCase()).toSet();

  Future<void> _addProduct() async {
    final draft = await widget.addProduct(_stagedNames);
    if (draft == null || !mounted) return;
    setState(() => _drafts.add(draft));
  }

  Future<void> _editDraft(int index) async {
    final current = _drafts[index];
    // Allow re-saving with the same name: exclude this draft from the blocklist.
    final blocked = _stagedNames..remove(current.name.toLowerCase());
    final draft = await widget.editProduct(current, blocked);
    if (draft == null || !mounted) return;
    setState(() => _drafts[index] = draft);
  }

  void _removeDraft(int index) {
    setState(() => _drafts.removeAt(index));
  }

  Future<void> _import() async {
    final products = await widget.pickAndParseImport(context);
    if (products == null || !mounted) return;
    final existingNames = _stagedNames;
    var added = 0;
    var skipped = 0;
    for (final parsed in products) {
      final lower = parsed.name.trim().toLowerCase();
      if (lower.isEmpty || existingNames.contains(lower)) {
        skipped++;
        continue;
      }
      existingNames.add(lower);
      final parsedForPurchase = parsed.copyWith(
        supplier: widget.supplier,
        clearSupplier: widget.supplier == null || widget.supplier!.isEmpty,
      );
      final match = widget.matchExisting(parsed.name);
      if (match != null) {
        // Restock: keep identity from the existing product, carry imported
        // catalog/pricing fields, add the imported quantity.
        final restockProduct = parsedForPurchase.copyWith(
          id: match.id,
          uuid: match.uuid,
          shopId: match.shopId,
          createdAt: match.createdAt,
        );
        _drafts.add(
          _PurchaseDraft(
            product: restockProduct,
            quantityAdded: parsed.quantity,
            restockTarget: match,
          ),
        );
      } else {
        _drafts.add(
          _PurchaseDraft(
            product: parsedForPurchase,
            quantityAdded: parsed.quantity,
          ),
        );
      }
      added++;
    }
    if (!mounted) return;
    setState(() {});
    final msg = skipped > 0
        ? 'Added $added · skipped $skipped duplicate(s)'
        : 'Added $added product(s)';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirm() async {
    if (_committing || _drafts.isEmpty) return;
    setState(() => _committing = true);
    try {
      final count = await widget.commitBatch(
        List<_PurchaseDraft>.from(_drafts),
        widget.purchaseDate,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$count product(s) added')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _committing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_drafts.isEmpty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.amber,
          size: 34,
        ),
        title: const Text('Discard purchase?'),
        content: Text(
          'You have ${_drafts.length} unsaved product(s) in this batch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    final supplierLabel = (widget.supplier == null || widget.supplier!.isEmpty)
        ? 'No supplier'
        : widget.supplier!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) navigator.pop();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('New Purchase'),
          actions: const [
            AppInfoAction(
              title: 'New Purchase Help',
              intro:
                  'Use this screen to stage a supplier purchase before it touches stock.',
              sections: [
                AppInfoSection(
                  title: 'Add or import products',
                  points: [
                    'Add product opens the full product editor for one item.',
                    'Import file reads CSV or XLSX rows into this same purchase batch.',
                    'Confirm saves all staged rows together; leaving the screen before confirm discards the batch.',
                  ],
                ),
                AppInfoSection(
                  title: 'Import columns',
                  points: [
                    'Required columns are product_name, quantity, purchase_price.',
                    'Optional columns are product_code, barcode, category, selling_price, unit.',
                    'Use selling_price only when you want direct pricing. Leave it blank or remove it to use automatic pricing.',
                    'Supplier and purchase date come from this purchase, not from the file.',
                  ],
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(30),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 14,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_formatFullDate(widget.purchaseDate)}  ·  $supplierLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _committing ? null : _import,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Import file'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _committing ? null : _addProduct,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add product'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _drafts.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: _drafts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _buildDraftRow(i),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: (_drafts.isEmpty || _committing) ? null : _confirm,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: AppColors.navy,
            ),
            child: _committing
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _drafts.isEmpty
                        ? 'Add products to confirm'
                        : 'Confirm (${_drafts.length})',
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.12),
                borderRadius: AppRadius.lgRadius,
              ),
              child: const Icon(
                Icons.add_shopping_cart_outlined,
                size: 34,
                color: AppColors.amber,
              ),
            ),
            const SizedBox(height: 16),
            Text('No products yet', style: AppText.title),
            const SizedBox(height: 6),
            Text(
              'Add products one by one, or import from a file.\nThey\'ll be saved together when you confirm.',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftRow(int index) {
    final draft = _drafts[index];
    final p = draft.product;
    final isRestock =
        draft.isRestock || widget.matchExisting(draft.name) != null;
    final qtyLabel = _formatQuantityInput(draft.quantityAdded);
    final unit = (p.unit == null || p.unit!.isEmpty) ? '' : ' ${p.unit}';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CompactListRow(
        leading: LeadingIconChip(
          icon: isRestock ? Icons.refresh_rounded : Icons.inventory_2_outlined,
          color: isRestock ? AppColors.amber : AppColors.navy,
        ),
        title: p.name,
        subtitle:
            '${isRestock ? 'Restock' : 'New'} · '
            'Qty $qtyLabel$unit · ₹${p.mrp.toStringAsFixed(2)}',
        onTap: _committing ? null : () => _editDraft(index),
        trailing: IconButton(
          tooltip: 'Remove',
          onPressed: _committing ? null : () => _removeDraft(index),
          icon: const Icon(
            Icons.close_rounded,
            size: 18,
            color: AppColors.inkMuted,
          ),
        ),
      ),
    );
  }
}
