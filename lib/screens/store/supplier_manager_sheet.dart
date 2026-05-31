part of '../store_screen.dart';

class _SupplierManagerSheet extends StatelessWidget {
  final List<SupplierProfile> suppliers;
  final Future<void> Function() onAdd;
  final Future<void> Function(SupplierProfile supplier) onEdit;
  final Future<void> Function(SupplierProfile supplier) onDelete;

  const _SupplierManagerSheet({
    required this.suppliers,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.creamDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const _PanelIcon(icon: Icons.local_shipping_outlined),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Suppliers',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Add supplier',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: suppliers.isEmpty
                  ? const Center(
                      child: Text(
                        'No suppliers yet',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: suppliers.length,
                      itemBuilder: (_, index) {
                        final supplier = suppliers[index];
                        return _SupplierProfileRow(
                          supplier: supplier,
                          onEdit: () => onEdit(supplier),
                          onDelete: () => onDelete(supplier),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupplierProfileRow extends StatelessWidget {
  final SupplierProfile supplier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SupplierProfileRow({
    required this.supplier,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      if (supplier.phone != null) supplier.phone!,
      if (supplier.email != null) supplier.email!,
      if (supplier.gstin != null) 'GSTIN ${supplier.gstin}',
      if (supplier.address != null) supplier.address!,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplier.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Edit',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 20),
            color: AppColors.error,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}
