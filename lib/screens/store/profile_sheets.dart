part of '../store_screen.dart';

class _ShopProfileSheet extends StatefulWidget {
  final ShopProfile profile;

  const _ShopProfileSheet({required this.profile});

  @override
  State<_ShopProfileSheet> createState() => _ShopProfileSheetState();
}

class _ShopProfileSheetState extends State<_ShopProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _gstinCtrl;
  late final TextEditingController _addressCtrl;
  late bool _gstRegistered;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _nameCtrl = TextEditingController(text: profile.name);
    _phoneCtrl = TextEditingController(text: profile.phone ?? '');
    _emailCtrl = TextEditingController(text: profile.email ?? '');
    _gstinCtrl = TextEditingController(text: profile.gstin ?? '');
    _addressCtrl = TextEditingController(text: profile.address ?? '');
    _gstRegistered = profile.gstRegistered;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _gstinCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_gstRegistered && _cleanOptional(_gstinCtrl.text) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a GSTIN to mark the shop as GST registered'),
        ),
      );
      return;
    }
    final current = widget.profile;
    Navigator.pop(
      context,
      ShopProfile(
        id: current.id,
        uuid: current.uuid,
        name: _nameCtrl.text.trim(),
        phone: _cleanOptional(_phoneCtrl.text),
        email: _cleanOptional(_emailCtrl.text),
        gstin: _cleanOptional(_gstinCtrl.text)?.toUpperCase(),
        address: _cleanOptional(_addressCtrl.text),
        gstRegistered: _gstRegistered,
        createdAt: current.createdAt,
        updatedAt: current.updatedAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSheetFrame(
      title: 'Shop Profile',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameCtrl,
              autofocus: widget.profile.name.isEmpty,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Shop Name *',
                prefixIcon: Icon(Icons.storefront_outlined, size: 18),
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
                prefixIcon: Icon(Icons.receipt_long_outlined, size: 18),
              ),
              onChanged: (value) {
                final hasGstin = _cleanOptional(value) != null;
                setState(() {
                  if (!hasGstin) _gstRegistered = false;
                });
              },
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
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final hasGstin = _cleanOptional(_gstinCtrl.text) != null;
                return SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Shop is GST registered'),
                  subtitle: Text(
                    !hasGstin
                        ? 'Add a GSTIN above to enable GST'
                        : _gstRegistered
                        ? 'GST is added on selling price'
                        : 'Purchase GST is included in cost',
                  ),
                  value: _gstRegistered,
                  activeThumbColor: AppColors.brandOf(context),
                  onChanged: hasGstin
                      ? (value) => setState(() => _gstRegistered = value)
                      : null,
                );
              },
            ),
            const SizedBox(height: 14),
            TestKeys.tag(
              TestKeys.saveBtn,
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Save Shop'),
              ),
              button: true,
            ),
          ],
        ),
      ),
    );
  }
}
