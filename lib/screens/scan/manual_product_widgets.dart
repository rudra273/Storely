part of '../scan_screen.dart';

class _ManualEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ManualEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 38,
            color: AppColors.inkMutedOf(context).withValues(alpha: 0.4),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.inkMutedOf(context),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;

  const _ManualProductTile({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final isOut = product.quantity == 0;
    return Material(
      color: AppColors.softBgOf(context),
      borderRadius: AppRadius.mdRadius,
      child: InkWell(
        onTap: onAdd,
        borderRadius: AppRadius.mdRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        product.priceLabel,
                        if (product.itemCode != null) product.itemCode!,
                        if (product.barcode != null) product.barcode!,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.inkMutedOf(context),
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
                    isOut ? 'Out' : product.quantityLabel,
                    style: TextStyle(
                      color: isOut
                          ? AppColors.error
                          : AppColors.inkMutedOf(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.add_circle_rounded,
                    color: AppColors.brandOf(context),
                    size: 22,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
