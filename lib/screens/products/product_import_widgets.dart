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
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.creamDark),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: products.length,
        separatorBuilder: (_, index) =>
            Divider(height: 1, indent: 56, color: AppColors.creamDark),
        itemBuilder: (_, index) {
          final product = products[index];
          final summary = product.id == null ? null : summaries[product.id];
          final lastDate = summary?.lastPurchaseDate == null
              ? 'No purchase date'
              : 'Last ${_formatFullDate(summary!.lastPurchaseDate!)}';
          return ListTile(
            dense: true,
            leading: const CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              child: Icon(Icons.inventory_2_outlined, size: 17),
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

class _ImportPreviewTable extends StatelessWidget {
  final List<Product> products;

  const _ImportPreviewTable({required this.products});

  @override
  Widget build(BuildContext context) {
    final visible = products.take(12).toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.creamDark),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 720,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(10),
            children: [
              const _ImportPreviewRow(
                name: 'Product',
                code: 'Code',
                barcode: 'Barcode',
                quantity: 'Qty',
                purchase: 'Purchase',
                selling: 'Selling',
                header: true,
              ),
              const Divider(height: 12),
              ...visible.map(
                (product) => _ImportPreviewRow(
                  name: product.name,
                  code: product.productCode ?? '-',
                  barcode: product.barcode ?? '-',
                  quantity: product.quantityLabel,
                  purchase: '₹${product.purchasePrice.toStringAsFixed(2)}',
                  selling: product.priceLabel,
                ),
              ),
              if (products.length > visible.length)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${products.length - visible.length} more rows',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportPreviewRow extends StatelessWidget {
  final String name;
  final String code;
  final String barcode;
  final String quantity;
  final String purchase;
  final String selling;
  final bool header;

  const _ImportPreviewRow({
    required this.name,
    required this.code,
    required this.barcode,
    required this.quantity,
    required this.purchase,
    required this.selling,
    this.header = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: header ? AppColors.navy : AppColors.textDark,
      fontSize: 12,
      fontWeight: header ? FontWeight.w900 : FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          _cell(name, 180, style),
          _cell(code, 90, style),
          _cell(barcode, 120, style),
          _cell(quantity, 72, style, alignEnd: true),
          _cell(purchase, 88, style, alignEnd: true),
          _cell(selling, 110, style, alignEnd: true),
        ],
      ),
    );
  }

  Widget _cell(
    String text,
    double width,
    TextStyle style, {
    bool alignEnd = false,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: style,
      ),
    );
  }
}
