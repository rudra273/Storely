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
                const _PanelIcon(icon: Icons.people_outline_rounded),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Customers',
                    style: TextStyle(
                      color: AppColors.navy,
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
                  ? const Center(
                      child: Text(
                        'No matching customers',
                        style: TextStyle(color: AppColors.textMuted),
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
                                    IconButton(
                                      onPressed: () => widget.onEdit(customer),
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 19,
                                      ),
                                      tooltip: 'Edit customer',
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

class _CustomerProfileSheet extends StatefulWidget {
  final Customer? customer;

  const _CustomerProfileSheet({this.customer});

  @override
  State<_CustomerProfileSheet> createState() => _CustomerProfileSheetState();
}

class _CustomerProfileSheetState extends State<_CustomerProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _gstinCtrl;
  late final TextEditingController _gstLegalNameCtrl;
  late final TextEditingController _gstTradeNameCtrl;
  late final TextEditingController _stateCodeCtrl;

  @override
  void initState() {
    super.initState();
    final customer = widget.customer;
    _nameCtrl = TextEditingController(text: customer?.name ?? '');
    _phoneCtrl = TextEditingController(text: customer?.phone ?? '');
    _emailCtrl = TextEditingController(text: customer?.email ?? '');
    _addressCtrl = TextEditingController(text: customer?.address ?? '');
    _notesCtrl = TextEditingController(text: customer?.notes ?? '');
    _gstinCtrl = TextEditingController(text: customer?.gstin ?? '');
    _gstLegalNameCtrl = TextEditingController(
      text: customer?.gstLegalName ?? '',
    );
    _gstTradeNameCtrl = TextEditingController(
      text: customer?.gstTradeName ?? '',
    );
    _stateCodeCtrl = TextEditingController(
      text: customer?.placeOfSupplyStateCode ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    _gstinCtrl.dispose();
    _gstLegalNameCtrl.dispose();
    _gstTradeNameCtrl.dispose();
    _stateCodeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final current = widget.customer;
    Navigator.pop(
      context,
      Customer(
        id: current?.id,
        uuid: current?.uuid ?? '',
        shopId: current?.shopId ?? 'local-shop',
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _cleanOptional(_emailCtrl.text),
        address: _cleanOptional(_addressCtrl.text),
        notes: _cleanOptional(_notesCtrl.text),
        gstin: _cleanOptional(_gstinCtrl.text)?.toUpperCase(),
        gstLegalName: _cleanOptional(_gstLegalNameCtrl.text),
        gstTradeName: _cleanOptional(_gstTradeNameCtrl.text),
        gstSource: _cleanOptional(_gstinCtrl.text) == null ? null : 'manual',
        gstVerifiedAt: _cleanOptional(_gstinCtrl.text) == null
            ? null
            : DateTime.now(),
        placeOfSupplyStateCode: _cleanOptional(_stateCodeCtrl.text),
        totalPurchaseAmount: current?.totalPurchaseAmount ?? 0,
        billCount: current?.billCount ?? 0,
        lastPurchaseAt: current?.lastPurchaseAt,
        deviceId: current?.deviceId,
        createdAt: current?.createdAt ?? DateTime.now(),
        updatedAt: current?.updatedAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.customer != null;
    return _SettingsSheetFrame(
      title: isEditing ? 'Edit Customer' : 'Add Customer',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameCtrl,
              autofocus: !isEditing,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Customer Name *',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined, size: 18),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return null;
                return email.contains('@') ? null : 'Invalid email';
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _gstinCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'GSTIN',
                prefixIcon: Icon(Icons.badge_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _gstLegalNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Legal Business Name',
                prefixIcon: Icon(Icons.business_center_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _gstTradeNameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Trade Name',
                prefixIcon: Icon(Icons.storefront_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _stateCodeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Place of Supply State Code',
                prefixIcon: Icon(Icons.map_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _addressCtrl,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.location_on_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesCtrl,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes',
                prefixIcon: Icon(Icons.notes_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(isEditing ? 'Update Customer' : 'Add Customer'),
            ),
          ],
        ),
      ),
    );
  }
}
