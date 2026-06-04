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
                '₹${product.purchasePrice.toStringAsFixed(2)}',
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
