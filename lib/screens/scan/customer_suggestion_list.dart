part of '../scan_screen.dart';

class _CustomerSuggestionList extends StatelessWidget {
  final List<Customer> customers;
  final ValueChanged<Customer> onSelected;

  const _CustomerSuggestionList({
    required this.customers,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: customers.length,
        separatorBuilder: (_, index) =>
            Divider(height: 1, indent: 56, color: AppColors.border),
        itemBuilder: (_, index) {
          final customer = customers[index];
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              child: Text(
                customer.name.trim().isEmpty
                    ? '?'
                    : customer.name.trim().substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            title: Text(
              customer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${_displayPhone(customer.phone)} • ${customer.billCount} bill${customer.billCount == 1 ? '' : 's'} • ₹${customer.totalPurchaseAmount.toStringAsFixed(2)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.check_circle_outline_rounded),
            onTap: () => onSelected(customer),
          );
        },
      ),
    );
  }

  static String _displayPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+91 ${digits.substring(2, 7)} ${digits.substring(7)}';
    }
    return phone;
  }
}
