part of '../products_screen.dart';

class _ProductCard extends StatelessWidget {
  final Product product;
  final ProductPurchaseSummary? purchaseSummary;
  final int lowStockThreshold;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onHistory;
  final VoidCallback onAdjust;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    this.purchaseSummary,
    required this.lowStockThreshold,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onHistory,
    required this.onAdjust,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isLowStock = product.isLowStock(lowStockThreshold);
    final isOutOfStock =
        product.trackStock && product.quantity <= stockQuantityEpsilon;
    final brand = AppColors.brandOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.md),
        color: isSelected
            ? brand.withValues(alpha: AppColors.isDark(context) ? 0.22 : 0.05)
            : null,
        borderRadius: isSelected
            ? AppRadius.mdRadius
            : isOutOfStock
            ? AppRadius.mdRadius
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selectionMode) ...[
                  GestureDetector(
                    onTap: onTap,
                    child: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: isSelected ? brand : AppColors.inkFaintOf(context),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                _SourceBadge(
                  label: product.sourceLabel,
                  highlighted: product.isImported,
                ),
                const SizedBox(width: AppSpacing.sm),
                _SourceBadge(
                  label: product.directPriceToggle ? 'direct' : 'auto',
                  highlighted: product.directPriceToggle,
                ),
                const Spacer(),
                if (isOutOfStock)
                  StatusPill(label: 'Out', variant: PillVariant.out)
                else if (isLowStock)
                  StatusPill(label: 'Low', variant: PillVariant.low),
                if (!selectionMode) ...[
                  PopupMenuButton<VoidCallback>(
                    tooltip: 'More',
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 20,
                      color: AppColors.inkFaintOf(context),
                    ),
                    onSelected: (action) => action(),
                    itemBuilder: (_) => [
                      if (product.trackStock)
                        PopupMenuItem(
                          value: onAdjust,
                          child: const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.tune_rounded),
                            title: Text('Adjust stock'),
                          ),
                        ),
                      PopupMenuItem(
                        value: onHistory,
                        child: const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.history_rounded),
                          title: Text('Stock history'),
                        ),
                      ),
                      PopupMenuItem(
                        value: onDelete,
                        child: const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            GestureDetector(
              onLongPress: onLongPress,
              child: Text(
                product.name,
                style: AppText.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (product.barcode != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _InfoChip(
                icon: Icons.qr_code_scanner_rounded,
                label: product.barcode!,
              ),
            ],
            if (purchaseSummary?.lastPurchaseDate != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    size: 12,
                    color: AppColors.inkFaintOf(context),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Last purchase ${_formatFullDate(purchaseSummary!.lastPurchaseDate!)}',
                    style: AppText.caption,
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                StatusPill(
                  label: product.priceLabel,
                  variant: PillVariant.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.inventory_2_outlined,
                  size: 13,
                  color: AppColors.inkFaintOf(context),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  product.trackStock
                      ? product.quantityLabel
                      : 'Stock not tracked',
                  style: AppText.caption.copyWith(
                    color: isLowStock
                        ? AppColors.error
                        : AppColors.inkMutedOf(context),
                    fontWeight: isLowStock ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (product.supplier != null)
                  Flexible(
                    child: Text(
                      product.supplier!,
                      style: AppText.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: AppRadius.smRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.inkMutedOf(context)),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String label;
  final bool highlighted;

  const _SourceBadge({required this.label, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppColors.amber : AppColors.brandOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.smRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            highlighted
                ? Icons.upload_file_rounded
                : Icons.phone_android_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
