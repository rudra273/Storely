part of '../products_screen.dart';

class _ProductSuggestionList extends StatelessWidget {
  final List<Product> products;
  final Map<int, ProductPurchaseSummary> summaries;
  final ValueChanged<Product> onSelected;

  const _ProductSuggestionList({
    required this.products,
    required this.summaries,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: products.length,
        separatorBuilder: (_, index) =>
            Divider(height: 1, indent: 56, color: AppColors.borderOf(context)),
        itemBuilder: (_, index) {
          final product = products[index];
          final summary = product.id == null ? null : summaries[product.id];
          final lastDate = summary?.lastPurchaseDate == null
              ? 'No purchase date'
              : 'Last ${_formatFullDate(summary!.lastPurchaseDate!)}';
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.brandOf(context),
              foregroundColor: AppColors.isDark(context)
                  ? Colors.black
                  : Colors.white,
              child: const Icon(Icons.inventory_2_outlined, size: 17),
            ),
            title: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              [
                product.quantityLabel,
                lastDate,
                if (product.productCode != null) 'Code ${product.productCode}',
                if (product.barcode != null) 'Barcode ${product.barcode}',
                rupees(product.purchasePrice),
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.add_box_outlined),
            onTap: () => onSelected(product),
          );
        },
      ),
    );
  }
}

/// Lists rows that can't be imported; lets the user import the rest.
/// Pops `true` to import the valid rows.
class _ImportErrorsDialog extends StatelessWidget {
  final ImportParseResult result;

  const _ImportErrorsDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = result.products.length;
    final bad = result.errors.length;
    return AlertDialog(
      icon: const Icon(Icons.rule_rounded, size: 32),
      title: Text(
        ok == 0 ? 'No rows can be imported' : '$ok ready · $bad skipped',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ok == 0
                  ? 'Fix these rows in the file and import it again.'
                  : 'These rows have problems and will be left out. '
                        'Fix them in the file to import them later.',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: bad,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final error = result.errors[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text('Row ${error.row}', style: AppText.label),
                    title: Text(error.message),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        if (ok > 0)
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Import $ok row${ok == 1 ? '' : 's'}'),
          ),
      ],
    );
  }
}
