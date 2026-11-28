part of '../scan_screen.dart';

/// Label shown when no customer is picked: billing never waits for one.
const walkInPartyLabel = 'Walk-in / Cash';

/// Compact, always-visible Customer / Party bar at the top of Create Bill.
/// Defaults to [walkInPartyLabel]; tapping picks, searches or adds a party.
class _PartyBar extends StatelessWidget {
  final String name;
  final String phone;
  final VoidCallback onTap;

  const _PartyBar({
    required this.name,
    required this.phone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isWalkIn = name.trim().isEmpty;
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final hasPhone = digits.length > 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      child: AppCard(
        key: const ValueKey('bill-party-bar'),
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            LeadingIconChip(
              icon: isWalkIn
                  ? Icons.storefront_outlined
                  : Icons.person_outline_rounded,
              color: isWalkIn ? AppColors.inkMutedOf(context) : AppColors.amber,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Customer',
                    style: AppText.caption.copyWith(
                      color: AppColors.inkMutedOf(context),
                    ),
                  ),
                  Text(
                    isWalkIn ? walkInPartyLabel : name.trim(),
                    key: const ValueKey('bill-party-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (!isWalkIn && hasPhone)
                    Text(
                      phone.trim(),
                      style: AppText.caption.copyWith(
                        color: AppColors.inkMutedOf(context),
                      ),
                    ),
                ],
              ),
            ),
            Text(
              isWalkIn ? 'Add' : 'Change',
              style: AppText.caption.copyWith(
                color: AppColors.brandOf(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.inkMutedOf(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkout raw fields for a walk-in sale (what the checkout form starts with).
Map<String, dynamic> _walkInPartyFields() => {
  'name': '',
  'phone': '+91 ',
  'gstin': '',
  'legal': '',
  'trade': '',
  'address': '',
  'state': '',
  'billType': Bill.typeB2c,
};

/// Checkout raw fields for a saved [customer].
Map<String, dynamic> _customerPartyFields(Customer customer) => {
  'name': customer.name,
  'phone': _formatCheckoutCustomerPhoneInput(customer.phone),
  'gstin': customer.gstin ?? '',
  'legal': customer.gstLegalName ?? '',
  'trade': customer.gstTradeName ?? '',
  'address': customer.address ?? '',
  'state': customer.placeOfSupplyStateCode ?? '',
  'billType': customer.gstin != null ? Bill.typeB2b : Bill.typeB2c,
};

/// Pick a saved customer, search, add a new one (name + phone, saved with the
/// bill), or go back to walk-in. Pops the checkout raw fields to apply.
class _PartyPickerSheet extends StatefulWidget {
  final List<Customer> customers;
  final String currentName;

  const _PartyPickerSheet({required this.customers, required this.currentName});

  @override
  State<_PartyPickerSheet> createState() => _PartyPickerSheetState();
}

class _PartyPickerSheetState extends State<_PartyPickerSheet> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController(text: '+91 ');
  bool _adding = false;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  List<Customer> get _matches {
    final query = _searchController.text.trim().toLowerCase();
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    final list = query.isEmpty
        ? widget.customers
        : widget.customers.where(
            (c) =>
                c.name.toLowerCase().contains(query) ||
                (digits.length >= 3 &&
                    c.phone.replaceAll(RegExp(r'[^0-9]'), '').contains(digits)),
          );
    return list.take(50).toList();
  }

  void _startAdding() {
    final query = _searchController.text.trim();
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    setState(() {
      _adding = true;
      if (digits.length >= 10 && digits.length == query.length) {
        _phoneController.text = _formatCheckoutCustomerPhoneInput(digits);
      } else if (query.isNotEmpty) {
        _nameController.text = query;
      }
    });
  }

  void _submitNew() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a name');
      return;
    }
    Navigator.pop(context, {
      ..._walkInPartyFields(),
      'name': name,
      'phone': _phoneController.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Customer / Party', style: AppText.title),
          const SizedBox(height: AppSpacing.md),
          if (_adding) ...[
            TextField(
              key: const ValueKey('party-new-name'),
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Customer name',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('party-new-phone'),
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _adding = false),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('party-new-save'),
                    onPressed: _submitNew,
                    child: const Text('Use for this bill'),
                  ),
                ),
              ],
            ),
          ] else ...[
            TextField(
              key: const ValueKey('party-search'),
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search name or phone',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              key: const ValueKey('party-walk-in'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_outlined),
              title: const Text(walkInPartyLabel),
              trailing: widget.currentName.trim().isEmpty
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, _walkInPartyFields()),
            ),
            ListTile(
              key: const ValueKey('party-add-new'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('Add new customer'),
              onTap: _startAdding,
            ),
            const Divider(),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Text(
                        widget.customers.isEmpty
                            ? 'No saved customers yet'
                            : 'No matching customers',
                        textAlign: TextAlign.center,
                        style: AppText.caption,
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      itemBuilder: (_, index) {
                        final customer = matches[index];
                        return ListTile(
                          key: ValueKey('party-customer-${customer.uuid}'),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_outline_rounded),
                          title: Text(customer.name),
                          subtitle: Text(customer.phone),
                          trailing: customer.name == widget.currentName.trim()
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(
                            context,
                            _customerPartyFields(customer),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
