part of '../products_screen.dart';

class _BulkSelectionBar extends StatelessWidget {
  final int count;
  final bool allVisibleSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onSetCategory;
  final VoidCallback onSetSupplier;
  final VoidCallback onDelete;

  const _BulkSelectionBar({
    required this.count,
    required this.allVisibleSelected,
    required this.onSelectAll,
    required this.onClear,
    required this.onSetCategory,
    required this.onSetSupplier,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _SelectionToggleButton(
            allVisibleSelected: allVisibleSelected,
            onTap: allVisibleSelected ? onClear : onSelectAll,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count selected',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _BulkActionChip(
                    icon: Icons.category_outlined,
                    label: 'Category',
                    onTap: onSetCategory,
                  ),
                  const SizedBox(width: 8),
                  _BulkActionChip(
                    icon: Icons.storefront_outlined,
                    label: 'Supplier',
                    onTap: onSetSupplier,
                  ),
                  const SizedBox(width: 8),
                  _BulkActionChip(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    onTap: onDelete,
                    destructive: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionToggleButton extends StatelessWidget {
  final bool allVisibleSelected;
  final VoidCallback onTap;

  const _SelectionToggleButton({
    required this.allVisibleSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: allVisibleSelected ? 'Clear selection' : 'Select all visible',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            allVisibleSelected
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
            color: Colors.white,
            size: 17,
          ),
        ),
      ),
    );
  }
}

class _BulkActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _BulkActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = destructive ? AppColors.error : AppColors.navy;
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 16, color: foreground),
      label: Text(label),
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w800),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: destructive
            ? AppColors.error.withValues(alpha: 0.25)
            : Colors.white,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
