part of '../scan_screen.dart';

class _BillCheckoutSheet extends StatefulWidget {
  final List<Customer> customers;
  final Map<String, dynamic> initialState;
  final Future<void> Function(Map<String, dynamic>) onRawChanged;

  /// Payable totals for the current checkout controls, from the same
  /// calculator used to save the bill, so the preview always matches the
  /// saved invoice.
  final BillTotals Function({
    required String discountMode,
    required double discountValue,
    required String taxMode,
    required String roundOffMode,
    required double roundOffIncrement,
    String? placeOfSupplyStateCode,
    String? customerGstin,
  })
  totalsFor;
  final String defaultTaxMode;
  final String defaultRoundOffMode;
  final double defaultRoundOffIncrement;
  final double maxFixedDiscount;
  final int itemCount;
  final bool canBackdate;
  final Bill? initialBill;
  final Future<void> Function() onReview;
  final Future<({int id, BillTotals totals})> Function(_BillDraft) onSave;

  const _BillCheckoutSheet({
    required this.customers,
    required this.initialState,
    required this.onRawChanged,
    required this.onSave,
    required this.onReview,
    required this.totalsFor,
    required this.defaultTaxMode,
    required this.defaultRoundOffMode,
    required this.defaultRoundOffIncrement,
    required this.maxFixedDiscount,
    required this.itemCount,
    this.canBackdate = true,
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
  final _cashReceivedController = TextEditingController();
  final _transactionIdController = TextEditingController();
  final _notesController = TextEditingController();

  final _customerFieldLink = LayerLink();
  final _customerFocusNode = FocusNode();
  OverlayEntry? _suggestionOverlay;
  List<Customer> _overlayMatches = const [];

  var _discountMode = Bill.discountModePercent;
  var _discountValue = 0.0;
  late String _taxMode;
  late String _roundOffMode;
  late double _roundOffIncrement;
  var _billType = Bill.typeB2c;
  DateTime? _billDate;
  String? _paymentStatus;
  bool _allowUnassignedCredit = false;
  bool _saving = false;
  bool _reviewRequired = false;
  bool _frozen = false;
  _BillDraft? _attemptDraft;
  var _paymentMethod = 'cash';
  var _hideCustomerSuggestions = false;

  @override
  void initState() {
    super.initState();
    _taxMode = widget.defaultTaxMode;
    _roundOffMode = widget.defaultRoundOffMode;
    _roundOffIncrement = widget.defaultRoundOffIncrement;
    final bill = widget.initialBill;
    if (bill != null) {
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
      _discountMode = bill.discountMode;
      _discountValue = bill.discountValue;
      if (bill.discountValue > 0) {
        _setCheckoutControllerText(
          _discountController,
          bill.discountValue.toStringAsFixed(2),
        );
      }
      _taxMode = bill.taxMode;
      _roundOffMode = bill.roundOffMode;
      _roundOffIncrement = bill.roundOffIncrement;
      _billType = bill.billType;
      if (bill.notes != null && bill.notes!.isNotEmpty) {
        _setCheckoutControllerText(_notesController, bill.notes!);
      }
      _paymentStatus = null;
      _paymentMethod = 'cash';
      _hideCustomerSuggestions = true;
    }
    final raw = widget.initialState['raw'];
    if (raw is Map) {
      for (final entry in _rawControllers.entries) {
        if (raw[entry.key] is String) {
          entry.value.text = raw[entry.key] as String;
        }
      }
      _discountMode = raw['discountMode'] == Bill.discountModeAmount
          ? Bill.discountModeAmount
          : Bill.discountModePercent;
      _discountValue = double.tryParse(_discountController.text) ?? 0;
      if (raw['taxMode'] == Bill.taxModeInclusive ||
          raw['taxMode'] == Bill.taxModeExclusive) {
        _taxMode = raw['taxMode'] as String;
      }
      if (const {
        Bill.roundOffNone,
        Bill.roundOffNearest,
        Bill.roundOffUp,
        Bill.roundOffDown,
      }.contains(raw['roundOffMode'])) {
        _roundOffMode = raw['roundOffMode'] as String;
      }
      final rawInc = (raw['roundOffIncrement'] as num?)?.toDouble();
      if (rawInc != null &&
          Bill.roundOffIncrements.any((inc) => (inc - rawInc).abs() < 1e-6)) {
        _roundOffIncrement = rawInc;
      }
      _billType = raw['billType'] == Bill.typeB2b ? Bill.typeB2b : Bill.typeB2c;
      _paymentStatus =
          {
            Bill.statusPaid,
            Bill.statusPartial,
            Bill.statusUnpaid,
          }.contains(raw['settlement'])
          ? raw['settlement'] as String
          : null;
      _paymentMethod = normalizeCheckoutPaymentMethod(raw['method']);
      _allowUnassignedCredit = raw['consent'] == true;
      if (raw['billDate'] is String) {
        final parsed = DateTime.tryParse(raw['billDate'] as String);
        if (parsed != null && widget.canBackdate) {
          _billDate = parsed;
        }
      }
    }
    final pending = widget.initialState['pending'];
    if (pending is Map) {
      _attemptDraft = _BillDraft.fromMap(
        Map<String, dynamic>.from(pending['draft'] as Map),
      );
      _frozen = true;
    }
    for (final controller in _rawControllers.values) {
      controller.addListener(_rawChanged);
    }
    _lastRaw = jsonEncode(_raw());
    if (!_frozen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _lastRaw = null;
        _rawChanged();
      });
    }
  }

  Map<String, TextEditingController> get _rawControllers => {
    'name': _customerController,
    'phone': _phoneController,
    'gstin': _gstinController,
    'legal': _legalNameController,
    'trade': _tradeNameController,
    'address': _addressController,
    'state': _stateCodeController,
    'discount': _discountController,
    'partial': _paidAmountController,
    'cash': _cashReceivedController,
    'reference': _transactionIdController,
    'notes': _notesController,
  };
  String? _lastRaw;
  String? _draftError;
  bool _persisting = false;
  int _rawWrites = 0;
  Map<String, dynamic> _raw() => {
    for (final entry in _rawControllers.entries) entry.key: entry.value.text,
    'discountMode': _discountMode,
    'taxMode': _taxMode,
    'roundOffMode': _roundOffMode,
    'roundOffIncrement': _roundOffIncrement,
    'billType': _billType,
    'billDate': _billDate?.toIso8601String(),
    'settlement': _paymentStatus,
    'method': _paymentMethod,
    'consent': _allowUnassignedCredit,
  };
  void _rawChanged() {
    if (_frozen) return;
    final raw = _raw();
    final encoded = jsonEncode(raw);
    if (_lastRaw == encoded) return;
    _lastRaw = encoded;
    _rawWrites++;
    _persisting = true;
    widget
        .onRawChanged(raw)
        .then(
          (_) {
            if (!mounted) return;
            setState(() {
              _rawWrites--;
              _persisting = _rawWrites > 0;
              _draftError = null;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _rawWrites--;
              _persisting = _rawWrites > 0;
              _draftError = 'Could not keep checkout entries: $error';
            });
          },
        );
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rawChanged();
  }

  @override
  void dispose() {
    for (final controller in _rawControllers.values) {
      controller.removeListener(_rawChanged);
    }
    _customerController.dispose();
    _phoneController.dispose();
    _gstinController.dispose();
    _legalNameController.dispose();
    _tradeNameController.dispose();
    _addressController.dispose();
    _stateCodeController.dispose();
    _discountController.dispose();
    _paidAmountController.dispose();
    _cashReceivedController.dispose();
    _transactionIdController.dispose();
    _notesController.dispose();
    _removeSuggestionOverlay();
    _customerFocusNode.dispose();
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
    _customerFocusNode.unfocus();
  }

  /// Keeps the floating suggestion overlay in sync with [matches]. Shows,
  /// rebuilds, or tears down the [OverlayEntry] anchored under the name field.
  void _syncSuggestionOverlay(List<Customer> matches) {
    _overlayMatches = matches;
    if (matches.isEmpty) {
      _removeSuggestionOverlay();
      return;
    }
    if (_suggestionOverlay == null) {
      _suggestionOverlay = _buildSuggestionOverlay();
      Overlay.of(context).insert(_suggestionOverlay!);
    } else {
      _suggestionOverlay!.markNeedsBuild();
    }
  }

  OverlayEntry _buildSuggestionOverlay() {
    return OverlayEntry(
      builder: (context) {
        final width = _customerFieldLink.leaderSize?.width ?? 0;
        final height = _customerFieldLink.leaderSize?.height ?? 0;
        return Positioned(
          width: width,
          child: CompositedTransformFollower(
            link: _customerFieldLink,
            showWhenUnlinked: false,
            offset: Offset(0, height + 6),
            child: _CustomerSuggestionList(
              customers: _overlayMatches,
              onSelected: _selectCustomer,
            ),
          ),
        );
      },
    );
  }

  void _removeSuggestionOverlay() {
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
  }

  String? _checkoutPhone() {
    final digits = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty || digits == '91' ? null : digits;
  }

  Future<void> _pickBillDate() async {
    if (_frozen || !widget.canBackdate) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _billDate != null
        ? DateTime(_billDate!.year, _billDate!.month, _billDate!.day)
        : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(today) ? today : initial,
      firstDate: DateTime(2000, 1, 1),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    final pickedDay = DateTime(picked.year, picked.month, picked.day);
    if (pickedDay.isAfter(today)) {
      _showCheckoutError('Bill date cannot be in the future.');
      return;
    }
    setState(() {
      _billDate = pickedDay == today
          ? null
          : DateTime(pickedDay.year, pickedDay.month, pickedDay.day, 12, 0);
    });
  }

  String _billDateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = _billDate;
    if (date == null) {
      return 'Today (${DateFormat('dd MMM yyyy').format(now)})';
    }
    final pickedDay = DateTime(date.year, date.month, date.day);
    if (pickedDay == today) {
      return 'Today (${DateFormat('dd MMM yyyy').format(now)})';
    }
    return DateFormat('dd MMM yyyy').format(date);
  }

  Future<void> _submit(double total) async {
    if (_saving || _reviewRequired || _draftError != null) return;
    if (!_frozen && _billDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final chosenDay = DateTime(
        _billDate!.year,
        _billDate!.month,
        _billDate!.day,
      );
      if (chosenDay.isAfter(today)) {
        _showCheckoutError('Bill date cannot be in the future.');
        return;
      }
      if (chosenDay.isBefore(today) && !widget.canBackdate) {
        _showCheckoutError('Only a shop owner or admin can backdate bills.');
        return;
      }
    }
    if (!_frozen &&
        _discountMode == Bill.discountModeAmount &&
        _discountValue > widget.maxFixedDiscount + 1e-6) {
      _showCheckoutError('Discount cannot exceed subtotal.');
      return;
    }
    if (!_frozen && _billType == Bill.typeB2b && !_validateB2bFields()) return;
    try {
      if (_attemptDraft == null) {
        final phone = _checkoutPhone();
        if (phone != null && (phone.length < 10 || phone.length > 12)) {
          throw const FormatException('Enter a valid customer phone number.');
        }
        final paise = checkoutPaidPaise(
          settlement: _paymentStatus,
          partialText: _paidAmountController.text,
          totalPaise: decimalScaledInteger(total.toStringAsFixed(2), scale: 2),
          hasCustomer: phone != null,
          allowUnassignedCredit: _allowUnassignedCredit,
        );
        final paidAmount = paise.toDouble() / 100;
        final normalizedMethod = _paymentStatus == Bill.statusUnpaid
            ? 'cash'
            : _paymentMethod;
        final trimmedReference = _transactionIdController.text.trim();
        final effectiveDiscountValue = _discountMode == Bill.discountModePercent
            ? _discountValue.clamp(0, 100).toDouble()
            : _discountValue;
        _attemptDraft = _BillDraft(
          customerName: _customerController.text,
          customerPhone: _checkoutPhone(),
          billType: _billType,
          customerGstin: _gstinController.text,
          customerGstLegalName: _legalNameController.text,
          customerGstTradeName: _tradeNameController.text,
          customerAddress: _addressController.text,
          placeOfSupplyStateCode: _stateCodeController.text.trim().isEmpty
              ? _gstinController.text.trim()
              : _stateCodeController.text,
          discountPercent: _discountMode == Bill.discountModePercent
              ? effectiveDiscountValue
              : 0,
          discountMode: _discountMode,
          discountValue: effectiveDiscountValue,
          taxMode: _taxMode,
          roundOffMode: _roundOffMode,
          roundOffIncrement: _roundOffIncrement,
          paidAmount: paidAmount,
          paymentMethod: normalizedMethod,
          transactionReference:
              (_paymentStatus == Bill.statusUnpaid ||
                  normalizedMethod == 'cash' ||
                  trimmedReference.isEmpty)
              ? null
              : trimmedReference,
          billDate: _billDate,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() {
        _saving = true;
        _frozen = true;
      });
      final saved = await widget.onSave(_attemptDraft!);
      if (!mounted) return;
      Navigator.pop(context, (
        draft: _attemptDraft!,
        id: saved.id,
        totals: saved.totals,
      ));
    } catch (error) {
      if (!mounted) return;
      if (error is CheckoutReviewChanged) {
        _frozen = false;
        _reviewRequired = true;
      }
      _showCheckoutError(
        error
            .toString()
            .replaceFirst('FormatException: ', '')
            .replaceFirst('Bad state: ', ''),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    final discountExceedsSubtotal =
        _discountMode == Bill.discountModeAmount &&
        _discountValue > widget.maxFixedDiscount + 1e-6;
    final previewDiscountValue = _discountMode == Bill.discountModePercent
        ? _discountValue.clamp(0, 100).toDouble()
        : _discountValue.clamp(0, widget.maxFixedDiscount).toDouble();
    final totals = widget.totalsFor(
      discountMode: _discountMode,
      discountValue: previewDiscountValue,
      taxMode: _taxMode,
      roundOffMode: _roundOffMode,
      roundOffIncrement: _roundOffIncrement,
      placeOfSupplyStateCode: _stateCodeController.text,
      customerGstin: _gstinController.text,
    );
    final discount = totals.discountAmount;
    final total = totals.grandTotal;
    final totalPaise = decimalScaledInteger(total.toStringAsFixed(2), scale: 2);
    final changePaise =
        _paymentStatus == Bill.statusPaid && _paymentMethod == 'cash'
        ? checkoutChangePaise(
            cashText: _cashReceivedController.text,
            totalPaise: totalPaise,
          )
        : null;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSuggestionOverlay(customerMatches);
    });

    return PopScope(
      canPop: !_frozen && !_persisting && _draftError == null,
      onPopInvokedWithResult: (_, _) =>
          FocusManager.instance.primaryFocus?.unfocus(),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IgnorePointer(
                ignoring: _frozen,
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Create Bill',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          key: const ValueKey('checkout-close'),
                          onPressed:
                              _frozen || _persisting || _draftError != null
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    CompositedTransformTarget(
                      link: _customerFieldLink,
                      child: TextField(
                        readOnly: _frozen,
                        key: const ValueKey('checkout-customer'),
                        controller: _customerController,
                        focusNode: _customerFocusNode,
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {
                          _hideCustomerSuggestions = false;
                          _allowUnassignedCredit = false;
                        }),
                        decoration: InputDecoration(
                          labelText: context.l10n.customerName,
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      readOnly: _frozen,
                      key: const ValueKey('checkout-phone'),
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                      ],
                      onChanged: (_) => setState(() {
                        _hideCustomerSuggestions = false;
                        _allowUnassignedCredit = false;
                      }),
                      decoration: InputDecoration(
                        labelText: context.l10n.phoneOptional,
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
                        readOnly: _frozen,
                        controller: _gstinController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: context.l10n.customerGstin,
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        readOnly: _frozen,
                        controller: _legalNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: context.l10n.legalName,
                          prefixIcon: Icon(Icons.business_center_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        readOnly: _frozen,
                        controller: _tradeNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: context.l10n.tradeNameOpt,
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        readOnly: _frozen,
                        controller: _addressController,
                        minLines: 2,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: context.l10n.businessAddress,
                          prefixIcon: Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        readOnly: _frozen,
                        controller: _stateCodeController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        decoration: InputDecoration(
                          labelText: context.l10n.placeOfSupplyCode,
                          prefixIcon: Icon(Icons.map_outlined),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    InkWell(
                      key: const ValueKey('checkout-bill-date'),
                      borderRadius: AppRadius.smRadius,
                      onTap: widget.canBackdate && !_frozen
                          ? _pickBillDate
                          : null,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Bill date',
                          prefixIcon: const Icon(Icons.calendar_today_outlined),
                          suffixIcon: widget.canBackdate
                              ? const Icon(Icons.edit_calendar_outlined)
                              : const Icon(Icons.lock_outline_rounded, size: 18),
                          enabled: widget.canBackdate && !_frozen,
                        ),
                        child: Text(
                          _billDateLabel(),
                          style: AppText.body,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      readOnly: _frozen,
                      key: const ValueKey('checkout-notes'),
                      controller: _notesController,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _BillSummaryRow(
                      label: context.l10n.subtotal,
                      value: rupees(totals.subtotal),
                    ),
                    _BillSummaryRow(
                      label: context.l10n.items,
                      value: '${widget.itemCount}',
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            readOnly: _frozen,
                            key: const ValueKey('checkout-discount'),
                            controller: _discountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              TextInputFormatter.withFunction((
                                oldValue,
                                newValue,
                              ) {
                                final isValid = RegExp(
                                  r'^\d*\.?\d{0,2}$',
                                ).hasMatch(newValue.text);
                                return isValid ? newValue : oldValue;
                              }),
                            ],
                            decoration: InputDecoration(
                              labelText:
                                  _discountMode == Bill.discountModePercent
                                  ? context.l10n.discountPercent
                                  : 'Discount (₹)',
                              prefixText:
                                  _discountMode == Bill.discountModeAmount
                                  ? '₹ '
                                  : null,
                              suffixText:
                                  _discountMode == Bill.discountModePercent
                                  ? '%'
                                  : null,
                              errorText: discountExceedsSubtotal
                                  ? 'Cannot exceed subtotal'
                                  : null,
                            ),
                            onChanged: (value) {
                              setState(() {
                                _discountValue = double.tryParse(value) ?? 0;
                                _allowUnassignedCredit = false;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<String>(
                          key: const ValueKey('checkout-discount-mode'),
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: Bill.discountModePercent,
                              label: Text('%'),
                            ),
                            ButtonSegment(
                              value: Bill.discountModeAmount,
                              label: Text('₹'),
                            ),
                          ],
                          selected: {_discountMode},
                          onSelectionChanged: _frozen
                              ? null
                              : (value) => setState(() {
                                  _discountMode = value.first;
                                  _allowUnassignedCredit = false;
                                }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        key: const ValueKey('checkout-tax-mode'),
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: Bill.taxModeInclusive,
                            label: Text('Tax inclusive'),
                          ),
                          ButtonSegment(
                            value: Bill.taxModeExclusive,
                            label: Text('Tax exclusive'),
                          ),
                        ],
                        selected: {_taxMode},
                        onSelectionChanged: _frozen
                            ? null
                            : (value) => setState(() {
                                _taxMode = value.first;
                                _allowUnassignedCredit = false;
                              }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Round off', style: AppText.caption),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        key: const ValueKey('checkout-round-off-mode'),
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final entry in const [
                            (Bill.roundOffNone, 'None'),
                            (Bill.roundOffNearest, 'Nearest'),
                            (Bill.roundOffUp, 'Up'),
                            (Bill.roundOffDown, 'Down'),
                          ])
                            ChoiceChip(
                              key: ValueKey(
                                'checkout-round-off-mode-${entry.$1}',
                              ),
                              label: Text(entry.$2),
                              selected: _roundOffMode == entry.$1,
                              onSelected: _frozen
                                  ? null
                                  : (_) => setState(() {
                                      _roundOffMode = entry.$1;
                                      _allowUnassignedCredit = false;
                                    }),
                            ),
                        ],
                      ),
                    ),
                    if (_roundOffMode != Bill.roundOffNone) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          key: const ValueKey('checkout-round-off-increment'),
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            for (final inc in Bill.roundOffIncrements)
                              ChoiceChip(
                                key: ValueKey(
                                  'checkout-round-off-increment-${inc.toStringAsFixed(2)}',
                                ),
                                label: Text(
                                  inc == 0.5
                                      ? '₹0.50'
                                      : '₹${inc.toStringAsFixed(0)}',
                                ),
                                selected:
                                    (_roundOffIncrement - inc).abs() < 1e-6,
                                onSelected: _frozen
                                    ? null
                                    : (_) => setState(() {
                                        _roundOffIncrement = inc;
                                        _allowUnassignedCredit = false;
                                      }),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: Bill.statusPaid,
                          icon: Icon(Icons.check_circle_outline),
                          label: Text(context.l10n.paidFull),
                        ),
                        ButtonSegment(
                          value: Bill.statusPartial,
                          icon: Icon(Icons.payments_outlined),
                          label: Text(context.l10n.partial),
                        ),
                        ButtonSegment(
                          value: Bill.statusUnpaid,
                          icon: Icon(Icons.pending_actions_outlined),
                          label: Text(context.l10n.unpaid),
                        ),
                      ],
                      emptySelectionAllowed: true,
                      selected: {?_paymentStatus},
                      onSelectionChanged: (value) => setState(() {
                        _paymentStatus = value.firstOrNull;
                        _allowUnassignedCredit = false;
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
                        readOnly: _frozen,
                        key: const ValueKey('checkout-partial-amount'),
                        controller: _paidAmountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: context.l10n.amountReceived,
                          prefixText: '₹ ',
                        ),
                        onChanged: (_) =>
                            setState(() => _allowUnassignedCredit = false),
                      ),
                    ],
                    if (_paymentStatus != null &&
                        _paymentStatus != Bill.statusUnpaid) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final method in checkoutPaymentMethods)
                              ChoiceChip(
                                key: ValueKey('checkout-method-$method'),
                                label: Text(paymentMethodLabel(method)),
                                selected: _paymentMethod == method,
                                onSelected: _frozen
                                    ? null
                                    : (_) => setState(() {
                                        _paymentMethod = method;
                                        _allowUnassignedCredit = false;
                                      }),
                              ),
                          ],
                        ),
                      ),
                      if (_paymentStatus == Bill.statusPaid &&
                          _paymentMethod == 'cash') ...[
                        const SizedBox(height: 12),
                        TextField(
                          readOnly: _frozen,
                          key: const ValueKey('checkout-cash-received'),
                          controller: _cashReceivedController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            TextInputFormatter.withFunction((
                              oldValue,
                              newValue,
                            ) {
                              final isValid = RegExp(
                                r'^\d*\.?\d{0,2}$',
                              ).hasMatch(newValue.text);
                              return isValid ? newValue : oldValue;
                            }),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Cash received',
                            hintText: 'Optional',
                            prefixText: '₹ ',
                          ),
                        ),
                        if (changePaise != null &&
                            changePaise > BigInt.zero) ...[
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.softBgOf(context),
                              borderRadius: AppRadius.smRadius,
                              border: Border.all(
                                color: AppColors.borderOf(context),
                              ),
                            ),
                            child: Text(
                              'Change to return ${rupeesFromPaise(changePaise)}',
                              key: const ValueKey('checkout-change-due'),
                              style: AppText.subtitle.copyWith(
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                      if (_paymentMethod != 'cash') ...[
                        const SizedBox(height: 12),
                        TextField(
                          readOnly: _frozen,
                          key: const ValueKey('checkout-reference'),
                          controller: _transactionIdController,
                          maxLength: 100,
                          onChanged: (_) =>
                              setState(() => _allowUnassignedCredit = false),
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Reference (optional)',
                            prefixIcon: Icon(Icons.receipt_long_outlined),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Storely records the payment method and reference on the invoice; it does not collect the payment itself.',
                            style: AppText.caption,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.softBgOf(context),
                        borderRadius: AppRadius.mdRadius,
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      child: Column(
                        children: [
                          _BillSummaryRow(
                            label: _discountMode == Bill.discountModePercent
                                ? 'Discount (${previewDiscountValue.toStringAsFixed(2)}%)'
                                : 'Discount',
                            value: '- ${rupees(discount)}',
                          ),
                          if (totals.gstAmount > 0) ...[
                            _BillSummaryRow(
                              label: 'Taxable',
                              value: rupees(totals.taxableAmount),
                            ),
                            _BillSummaryRow(
                              label: 'GST',
                              value: rupees(totals.gstAmount),
                            ),
                          ],
                          if (totals.roundOffAmount != 0)
                            _BillSummaryRow(
                              label: context.l10n.roundOff,
                              value:
                                  '${totals.roundOffAmount > 0 ? '+' : '-'} ${rupees(totals.roundOffAmount.abs())}',
                            ),
                          const Divider(height: 20),
                          _BillSummaryRow(
                            valueKey: const ValueKey('checkout-grand-total'),
                            label: context.l10n.grandTotal,
                            value: rupees(total),
                            isTotal: true,
                          ),
                          if (paidAmount > 0) ...[
                            const Divider(height: 20),
                            _BillSummaryRow(
                              label: context.l10n.received,
                              value: rupees(paidAmount),
                            ),
                            _BillSummaryRow(
                              label: context.l10n.balance,
                              value: rupees(
                                (total - paidAmount).clamp(0, total),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if ((_paymentStatus == Bill.statusPartial ||
                            _paymentStatus == Bill.statusUnpaid) &&
                        _checkoutPhone() == null)
                      CheckboxListTile(
                        key: const ValueKey('checkout-unassigned-consent'),
                        title: const Text('Keep this balance unassigned'),
                        subtitle: const Text(
                          'Add a customer with a phone number to put this balance on their account. Unassigned balances can be collected from the invoice.',
                        ),
                        value: _allowUnassignedCredit,
                        onChanged: (value) => setState(
                          () => _allowUnassignedCredit = value ?? false,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (_draftError != null) ...[
                Text(_draftError!),
                TextButton(
                  onPressed: () {
                    _lastRaw = null;
                    _rawChanged();
                  },
                  child: const Text('Retry keeping checkout entries'),
                ),
              ],
              if (_reviewRequired)
                TextButton(
                  key: const ValueKey('checkout-review-latest'),
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() => _saving = true);
                          try {
                            await widget.onReview();
                            if (!mounted) return;
                            setState(() {
                              _reviewRequired = false;
                              _attemptDraft = null;
                              _paymentStatus = null;
                              _allowUnassignedCredit = false;
                              _paidAmountController.clear();
                            });
                          } catch (error) {
                            if (mounted) _showCheckoutError(error.toString());
                          } finally {
                            if (mounted) setState(() => _saving = false);
                          }
                        },
                  child: const Text('Review latest settings and total'),
                ),
              if (_frozen)
                const Text(
                  'Checkout details are kept. Retry this same save to recover its result.',
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('checkout-save'),
                  onPressed: _saving || _reviewRequired
                      ? null
                      : () => _submit(total),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: Text(context.l10n.generateBill),
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
