part of '../scan_screen.dart';

class _BillCheckoutSheet extends StatefulWidget {
  final List<Customer> customers;
  final double subtotal;
  final int itemCount;
  final Bill? initialBill;

  const _BillCheckoutSheet({
    required this.customers,
    required this.subtotal,
    required this.itemCount,
    this.initialBill,
  });

  @override
  State<_BillCheckoutSheet> createState() => _BillCheckoutSheetState();
}

class _BillCheckoutSheetState extends State<_BillCheckoutSheet> {
  final _customerController = TextEditingController();
  final _phoneController = TextEditingController(text: '+91 ');
  final _gstinController = TextEditingController();
  final _legalNameController = TextEditingController();
  final _tradeNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _stateCodeController = TextEditingController();
  final _discountController = TextEditingController();
  final _paidAmountController = TextEditingController();

  var _discountPercent = 0.0;
  var _billType = Bill.typeB2c;
  var _paymentStatus = Bill.statusUnpaid;
  var _paymentMethod = 'cash';
  var _hideCustomerSuggestions = false;

  @override
  void initState() {
    super.initState();
    final bill = widget.initialBill;
    if (bill == null) return;
    _setCheckoutControllerText(_customerController, bill.customerName);
    _setCheckoutControllerText(
      _phoneController,
      _formatCheckoutCustomerPhoneInput(bill.customerPhone ?? ''),
    );
    _setCheckoutControllerText(_gstinController, bill.customerGstin ?? '');
    _setCheckoutControllerText(
      _legalNameController,
      bill.customerGstLegalName ?? '',
    );
    _setCheckoutControllerText(
      _tradeNameController,
      bill.customerGstTradeName ?? '',
    );
    _setCheckoutControllerText(
      _addressController,
      bill.customerAddressSnapshot ?? '',
    );
    _setCheckoutControllerText(
      _stateCodeController,
      bill.placeOfSupplyStateCode ?? '',
    );
    if (bill.discountPercent > 0) {
      _discountPercent = bill.discountPercent;
      _setCheckoutControllerText(
        _discountController,
        bill.discountPercent.toStringAsFixed(2),
      );
    }
    _billType = bill.billType;
    _paymentStatus = Bill.statusUnpaid;
    _paymentMethod = 'cash';
    _hideCustomerSuggestions = true;
  }

  @override
  void dispose() {
    _customerController.dispose();
    _phoneController.dispose();
    _gstinController.dispose();
    _legalNameController.dispose();
    _tradeNameController.dispose();
    _addressController.dispose();
    _stateCodeController.dispose();
    _discountController.dispose();
    _paidAmountController.dispose();
    super.dispose();
  }

  void _selectCustomer(Customer customer) {
    setState(() {
      _setCheckoutControllerText(_customerController, customer.name);
      _setCheckoutControllerText(
        _phoneController,
        _formatCheckoutCustomerPhoneInput(customer.phone),
      );
      _setCheckoutControllerText(_gstinController, customer.gstin ?? '');
      _setCheckoutControllerText(
        _legalNameController,
        customer.gstLegalName ?? '',
      );
      _setCheckoutControllerText(
        _tradeNameController,
        customer.gstTradeName ?? '',
      );
      _setCheckoutControllerText(_addressController, customer.address ?? '');
      _setCheckoutControllerText(
        _stateCodeController,
        customer.placeOfSupplyStateCode ?? '',
      );
      if (customer.gstin != null) _billType = Bill.typeB2b;
      _hideCustomerSuggestions = true;
    });
  }

  void _submit(double total, double paidAmount) {
    if (_billType == Bill.typeB2b && !_validateB2bFields()) return;
    Navigator.pop(
      context,
      _BillDraft(
        customerName: _customerController.text,
        customerPhone: _phoneController.text,
        billType: _billType,
        customerGstin: _gstinController.text,
        customerGstLegalName: _legalNameController.text,
        customerGstTradeName: _tradeNameController.text,
        customerAddress: _addressController.text,
        placeOfSupplyStateCode: _stateCodeController.text.trim().isEmpty
            ? _gstinController.text.trim()
            : _stateCodeController.text,
        discountPercent: _discountPercent.clamp(0, 100).toDouble(),
        paidAmount: paidAmount.clamp(0, total).toDouble(),
        paymentMethod: _paymentMethod,
      ),
    );
  }

  bool _validateB2bFields() {
    final customerName = _customerController.text.trim();
    final gstin = _gstinController.text.trim().toUpperCase();
    final address = _addressController.text.trim();
    final stateCode = _stateCodeController.text.trim();
    if (customerName.isEmpty) {
      _showCheckoutError('Customer name is required for B2B bills');
      return false;
    }
    if (!_isValidGstin(gstin)) {
      _showCheckoutError('Enter a valid 15-character customer GSTIN');
      return false;
    }
    if (address.isEmpty) {
      _showCheckoutError('Business address is required for B2B bills');
      return false;
    }
    if (stateCode.isNotEmpty && !RegExp(r'^\d{2}$').hasMatch(stateCode)) {
      _showCheckoutError('Place of supply state code must be 2 digits');
      return false;
    }
    return true;
  }

  bool _isValidGstin(String value) {
    return RegExp(
      r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
    ).hasMatch(value);
  }

  void _showCheckoutError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final percent = _discountPercent.clamp(0, 100).toDouble();
    final discount = widget.subtotal * percent / 100;
    final total = widget.subtotal - discount;
    final parsedPaid = _paymentStatus == Bill.statusPaid
        ? total
        : _paymentStatus == Bill.statusPartial
        ? (double.tryParse(_paidAmountController.text) ?? 0)
        : 0.0;
    final paidAmount = parsedPaid.clamp(0, total).toDouble();
    final customerMatches = _hideCustomerSuggestions
        ? <Customer>[]
        : _matchingCheckoutCustomers(
            widget.customers,
            _customerController.text,
            _phoneController.text,
          );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, _) =>
          FocusManager.instance.primaryFocus?.unfocus(),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Create Bill',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customerController,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) =>
                    setState(() => _hideCustomerSuggestions = false),
                decoration: const InputDecoration(
                  labelText: 'Customer name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                ],
                onChanged: (_) =>
                    setState(() => _hideCustomerSuggestions = false),
                decoration: const InputDecoration(
                  labelText: 'Phone number (optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: Bill.typeB2c,
                    icon: Icon(Icons.person_outline_rounded),
                    label: Text('B2C'),
                  ),
                  ButtonSegment(
                    value: Bill.typeB2b,
                    icon: Icon(Icons.business_outlined),
                    label: Text('B2B'),
                  ),
                ],
                selected: {_billType},
                onSelectionChanged: (value) =>
                    setState(() => _billType = value.first),
              ),
              if (_billType == Bill.typeB2b) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _gstinController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Customer GSTIN',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _legalNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Legal business name',
                    prefixIcon: Icon(Icons.business_center_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tradeNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Trade name (optional)',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressController,
                  minLines: 2,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Business address',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _stateCodeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Place of supply state code',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                ),
              ],
              if (customerMatches.isNotEmpty) ...[
                const SizedBox(height: 10),
                _CustomerSuggestionList(
                  customers: customerMatches,
                  onSelected: _selectCustomer,
                ),
              ],
              const SizedBox(height: 12),
              _BillSummaryRow(
                label: 'Subtotal',
                value: '₹${widget.subtotal.toStringAsFixed(2)}',
              ),
              _BillSummaryRow(label: 'Items', value: '${widget.itemCount}'),
              const SizedBox(height: 12),
              TextField(
                controller: _discountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final isValid = RegExp(
                      r'^\d*\.?\d{0,2}$',
                    ).hasMatch(newValue.text);
                    return isValid ? newValue : oldValue;
                  }),
                ],
                decoration: const InputDecoration(
                  labelText: 'Discount percentage',
                  suffixText: '%',
                ),
                onChanged: (value) {
                  setState(
                    () => _discountPercent = double.tryParse(value) ?? 0,
                  );
                },
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: Bill.statusPaid,
                    icon: Icon(Icons.check_circle_outline),
                    label: Text('Paid full'),
                  ),
                  ButtonSegment(
                    value: Bill.statusPartial,
                    icon: Icon(Icons.payments_outlined),
                    label: Text('Partial'),
                  ),
                  ButtonSegment(
                    value: Bill.statusUnpaid,
                    icon: Icon(Icons.pending_actions_outlined),
                    label: Text('Unpaid'),
                  ),
                ],
                selected: {_paymentStatus},
                onSelectionChanged: (value) => setState(() {
                  _paymentStatus = value.first;
                  if (_paymentStatus == Bill.statusPaid) {
                    _setCheckoutControllerText(
                      _paidAmountController,
                      total.toStringAsFixed(2),
                    );
                  } else if (_paymentStatus == Bill.statusUnpaid) {
                    _setCheckoutControllerText(_paidAmountController, '');
                  }
                }),
              ),
              if (_paymentStatus == Bill.statusPartial) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _paidAmountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    TextInputFormatter.withFunction((oldValue, newValue) {
                      final isValid = RegExp(
                        r'^\d*\.?\d{0,2}$',
                      ).hasMatch(newValue.text);
                      return isValid ? newValue : oldValue;
                    }),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Amount received',
                    prefixText: '₹ ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (_paymentStatus != Bill.statusUnpaid) ...[
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'cash',
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Cash'),
                    ),
                    ButtonSegment(
                      value: 'online',
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      label: Text('Online'),
                    ),
                  ],
                  selected: {_paymentMethod},
                  onSelectionChanged: (value) =>
                      setState(() => _paymentMethod = value.first),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: AppRadius.mdRadius,
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    _BillSummaryRow(
                      label: 'Discount (${percent.toStringAsFixed(2)}%)',
                      value: '- ₹${discount.toStringAsFixed(2)}',
                    ),
                    const Divider(height: 20),
                    _BillSummaryRow(
                      label: 'Grand Total',
                      value: '₹${total.toStringAsFixed(2)}',
                      isTotal: true,
                    ),
                    if (paidAmount > 0) ...[
                      const Divider(height: 20),
                      _BillSummaryRow(
                        label: 'Received',
                        value: '₹${paidAmount.toStringAsFixed(2)}',
                      ),
                      _BillSummaryRow(
                        label: 'Balance',
                        value:
                            '₹${(total - paidAmount).clamp(0, total).toStringAsFixed(2)}',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _submit(total, paidAmount),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Generate Bill'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.amber,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
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

List<Customer> _matchingCheckoutCustomers(
  List<Customer> customers,
  String nameQuery,
  String phoneQuery,
) {
  final name = nameQuery.trim().toLowerCase();
  final phone = phoneQuery.replaceAll(RegExp(r'[^0-9]'), '');
  final hasNameQuery = name.length >= 2;
  final hasPhoneQuery = phone.length >= 3 && phone != '91';
  if (!hasNameQuery && !hasPhoneQuery) return [];

  return customers
      .where((customer) {
        final customerName = customer.name.toLowerCase();
        final customerPhone = customer.phone.replaceAll(RegExp(r'[^0-9]'), '');
        return (hasNameQuery && customerName.contains(name)) ||
            (hasPhoneQuery && customerPhone.contains(phone));
      })
      .take(5)
      .toList();
}

String _formatCheckoutCustomerPhoneInput(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 12 && digits.startsWith('91')) {
    return '+91 ${digits.substring(2)}';
  }
  if (digits.length == 10) return '+91 $digits';
  return phone;
}

void _setCheckoutControllerText(
  TextEditingController controller,
  String value,
) {
  controller.value = TextEditingValue(
    text: value,
    selection: TextSelection.collapsed(offset: value.length),
  );
}
