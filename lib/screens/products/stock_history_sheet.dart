part of '../products_screen.dart';

class _StockMovementHistorySheet extends StatelessWidget {
  final Product product;
  final List<StockMovement> movements;

  const _StockMovementHistorySheet({
    required this.product,
    required this.movements,
  });

  @override
  Widget build(BuildContext context) {
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
              '${product.name} • Current ${product.quantityLabel}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: movements.isEmpty
                  ? const Center(
                      child: Text(
                        'No stock movement yet',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: movements.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: AppColors.borderOf(context)),
                      itemBuilder: (_, index) =>
                          _StockMovementRow(movement: movements[index]),
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

  const _StockMovementRow({required this.movement});

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
                  _movementLabel(movement.movementType),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    _formatFullDate(movement.createdAt),
                    if (movement.sourceType != null) movement.sourceType!,
                    if (movement.unitCost != null)
                      '₹${movement.unitCost!.toStringAsFixed(2)}',
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
          Text(
            '${positive ? '+' : ''}${_formatQuantityInput(movement.quantityDelta)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
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
