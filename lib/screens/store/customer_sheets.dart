part of '../store_screen.dart';

class _CustomerTableSheet extends StatefulWidget {
  final List<Customer> customers;
  final Future<void> Function() onAdd;
  final Future<void> Function(Customer customer) onEdit;

  const _CustomerTableSheet({
    required this.customers,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  State<_CustomerTableSheet> createState() => _CustomerTableSheetState();
}

class _CustomerTableSheetState extends State<_CustomerTableSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Customer> get _filtered {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return widget.customers;
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    return widget.customers.where((customer) {
      return customer.name.toLowerCase().contains(query) ||
          customer.phone.contains(digits.isEmpty ? query : digits) ||
          (customer.email?.toLowerCase().contains(query) ?? false) ||
          (customer.address?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final customers = _filtered;
    final isDark = AppColors.isDark(context);
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
          border: isDark
              ? Border.all(color: AppColors.borderOf(context))
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrongOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const _PanelIcon(icon: Icons.people_outline_rounded),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Customers',
                    style: TextStyle(
                      color: AppColors.brandOf(context),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: widget.onAdd,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Add customer',
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Search customers',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: customers.isEmpty
                  ? Center(
                      child: Text(
                        'No matching customers',
                        style: TextStyle(color: AppColors.inkMutedOf(context)),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 38,
                        dataRowMinHeight: 44,
                        dataRowMaxHeight: 54,
                        columnSpacing: 22,
                        columns: const [
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Email')),
                          DataColumn(numeric: true, label: Text('Bills')),
                          DataColumn(numeric: true, label: Text('Total')),
                          DataColumn(label: Text('')),
                        ],
                        rows: customers
                            .map(
                              (customer) => DataRow(
                                cells: [
                                  DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 150,
                                      ),
                                      child: Text(
                                        customer.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(_displayPhone(customer.phone))),
                                  DataCell(Text(customer.email ?? '-')),
                                  DataCell(Text('${customer.billCount}')),
                                  DataCell(
                                    Text(
                                      '₹${customer.totalPurchaseAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    TestKeys.tag(
                                      TestKeys.customerRow(
                                        customer.id ?? customer.name,
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            widget.onEdit(customer),
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 19,
                                        ),
                                        tooltip: 'Edit customer',
                                      ),
                                      label: 'Edit customer',
                                      button: true,
                                    ),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _displayPhone(String phone) {
    if (phone.length == 12 && phone.startsWith('91')) {
      return '+91 ${phone.substring(2, 7)} ${phone.substring(7)}';
    }
    return phone;
  }
}
