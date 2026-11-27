part of '../products_screen.dart';

typedef _StockMovementHistorySheet = StockMovementHistorySheet;

class StockMovementHistorySheet extends StatefulWidget {
  final Product product;
  final List<StockMovement> movements;

  const StockMovementHistorySheet({
    super.key,
    required this.product,
    required this.movements,
  });

  @override
  State<StockMovementHistorySheet> createState() =>
      _StockMovementHistorySheetState();
}

class _StockMovementHistorySheetState extends State<StockMovementHistorySheet> {
  String? _selectedType;

  static const _typeFilters = <(String?, String, String)>[
    (null, 'All', 'stock-filter-all'),
    (StockMovementType.sale, 'Sale', 'stock-filter-sale'),
    (StockMovementType.purchase, 'Purchase', 'stock-filter-purchase'),
    (StockMovementType.adjustment, 'Adjustment', 'stock-filter-adjustment'),
    (StockMovementType.returnIn, 'Return', 'stock-filter-return'),
    (StockMovementType.voidSale, 'Void', 'stock-filter-void'),
  ];

  /// Computes the running balance after each movement by walking backward from
  /// [widget.product.quantity] through newest-first [widget.movements].
  List<({StockMovement movement, double balanceAfter})> _withBalances() {
    var running = widget.product.quantity;
    final rows = <({StockMovement movement, double balanceAfter})>[];
    for (final movement in widget.movements) {
      rows.add((movement: movement, balanceAfter: running));
      running -= movement.quantityDelta;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final allRows = _withBalances();
    final filtered = _selectedType == null
        ? allRows
        : allRows
              .where((row) => row.movement.movementType == _selectedType)
              .toList();

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(24),
        ),
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
              'Stock History',
              style: TextStyle(
                color: AppColors.inkOf(context),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.product.name} • Current ${widget.product.quantityLabel}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filter in _typeFilters) ...[
                    ChoiceChip(
                      key: ValueKey(filter.$3),
                      label: Text(filter.$2),
                      selected: _selectedType == filter.$1,
                      onSelected: (_) =>
                          setState(() => _selectedType = filter.$1),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          widget.movements.isEmpty
                              ? 'No stock movement yet'
                              : 'No matching stock movements',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: AppColors.borderOf(context),
                      ),
                      itemBuilder: (_, index) => _StockMovementRow(
                        movement: filtered[index].movement,
                        balanceAfter: filtered[index].balanceAfter,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockMovementRow extends StatelessWidget {
  final StockMovement movement;
  final double balanceAfter;

  const _StockMovementRow({
    required this.movement,
    required this.balanceAfter,
  });

  @override
  Widget build(BuildContext context) {
    final positive = movement.quantityDelta >= 0;
    final color = positive ? AppColors.success : AppColors.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              positive ? Icons.add_rounded : Icons.remove_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.reason == null
                      ? _movementLabel(movement.movementType)
                      : StockAdjustmentReason.label(movement.reason),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    _formatFullDate(movement.createdAt),
                    if (movement.sourceType != null) movement.sourceType!,
                    if (movement.importRowNumber != null)
                      'File row ${movement.importRowNumber}',
                    if (movement.unitCost != null) rupees(movement.unitCost!),
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${positive ? '+' : ''}${_formatQuantityInput(movement.quantityDelta)}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              Text(
                'Bal: ${_formatQuantityInput(balanceAfter)}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _movementLabel(String type) {
    switch (type) {
      case StockMovementType.purchase:
        return 'Purchase / Restock';
      case StockMovementType.sale:
        return 'Sale';
      case StockMovementType.adjustment:
        return 'Adjustment';
      case StockMovementType.returnIn:
        return 'Return';
      case StockMovementType.voidSale:
        return 'Bill void';
      default:
        return type;
    }
  }
}

// ── Product Card (Professional Design) ──
