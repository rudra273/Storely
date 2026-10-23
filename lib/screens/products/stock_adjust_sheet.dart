part of '../products_screen.dart';

/// Add or remove stock with a reason (damaged, expired, count correction…).
/// Pops `true` once the adjustment is saved.
class _StockAdjustSheet extends StatefulWidget {
  final Product product;

  const _StockAdjustSheet({required this.product});

  @override
  State<_StockAdjustSheet> createState() => _StockAdjustSheetState();
}

class _StockAdjustSheetState extends State<_StockAdjustSheet> {
  final _qtyController = TextEditingController();
  final _noteController = TextEditingController();
  String _reason = StockAdjustmentReason.damage;

  /// For a count, the quantity is the new total; otherwise it's how many.
  bool _adding = false;
  bool _saving = false;
  String? _error;

  bool get _isCount => _reason == StockAdjustmentReason.count;

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _setReason(String reason) {
    setState(() {
      _reason = reason;
      if (StockAdjustmentReason.removing.contains(reason)) _adding = false;
      if (reason == StockAdjustmentReason.returnIn) _adding = true;
      _error = null;
    });
  }

  double? get _delta {
    final value = double.tryParse(_qtyController.text.trim());
    if (value == null || value < 0) return null;
    if (_isCount) return value - widget.product.quantity;
    if (value == 0) return null;
    return _adding ? value : -value;
  }

  Future<void> _save() async {
    final delta = _delta;
    if (delta == null) {
      setState(() => _error = 'Enter a quantity');
      return;
    }
    if (delta.abs() < stockQuantityEpsilon) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DatabaseHelper.instance.adjustStock(
        widget.product.id!,
        delta: delta,
        reason: _reason,
        note: _noteController.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final delta = _delta;
    final unit = product.unit ?? '';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Adjust stock', style: AppText.title),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${product.name} · now ${product.quantityLabel}',
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Reason', style: AppText.label),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final reason in [
                    ...StockAdjustmentReason.removing,
                    ...StockAdjustmentReason.neutral,
                  ])
                    ChoiceChip(
                      label: Text(StockAdjustmentReason.label(reason)),
                      selected: _reason == reason,
                      onSelected: (_) => _setReason(reason),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_reason == StockAdjustmentReason.other) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Remove')),
                    ButtonSegment(value: true, label: Text('Add')),
                  ],
                  selected: {_adding},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) =>
                      setState(() => _adding = value.first),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextField(
                key: const ValueKey('stock-adjust-qty'),
                controller: _qtyController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: InputDecoration(
                  labelText: _isCount
                      ? 'Counted stock'
                      : _adding
                      ? 'Quantity to add'
                      : 'Quantity to remove',
                  suffixText: unit,
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (delta != null && delta.abs() >= stockQuantityEpsilon) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Stock becomes '
                  '${_formatQuantityInput(product.quantity + delta)} $unit '
                  '(${delta > 0 ? '+' : ''}${_formatQuantityInput(delta)})',
                  style: AppText.caption,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _noteController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save adjustment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
