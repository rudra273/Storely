import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/test_keys.dart';
import '../models/customer.dart';

/// Shared Add / Edit customer sheet.
///
/// Returns the edited [Customer] via [Navigator.pop] (or `null` if dismissed).
/// Used by both the Store customers table and the Home Customers quick action
/// so customers can be added from either place with the same form.
class CustomerProfileSheet extends StatefulWidget {
  final Customer? customer;

  const CustomerProfileSheet({super.key, this.customer});

  @override
  State<CustomerProfileSheet> createState() => _CustomerProfileSheetState();
}

class _CustomerProfileSheetState extends State<CustomerProfileSheet> {
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

  String? _cleanOptional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final current = widget.customer;
    Navigator.pop(
      context,
      Customer(
        id: current?.id,
        uuid: current?.uuid ?? '',
        shopId: current?.shopId ?? '',
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
    final isDark = AppColors.isDark(context);
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(24),
          border: isDark
              ? Border.all(color: AppColors.borderOf(context))
              : Border.all(color: Colors.transparent),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrongOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isEditing ? 'Edit Customer' : 'Add Customer',
                style: TextStyle(
                  color: AppColors.brandOf(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Form(
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
                        prefixIcon: Icon(
                          Icons.person_outline_rounded,
                          size: 18,
                        ),
                      ),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Required'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone *',
                        prefixIcon: Icon(Icons.phone_outlined, size: 18),
                      ),
                      validator: (value) {
                        final digits = (value ?? '').replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        if (digits.isEmpty) return 'Required';
                        if (digits.length < 10 || digits.length > 12) {
                          return 'Enter a valid phone number';
                        }
                        return null;
                      },
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
                        prefixIcon: Icon(
                          Icons.business_center_outlined,
                          size: 18,
                        ),
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
                    TestKeys.tag(
                      TestKeys.saveBtn,
                      FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          isEditing ? 'Update Customer' : 'Add Customer',
                        ),
                      ),
                      button: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
