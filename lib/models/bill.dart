class Bill {
  static const typeB2c = 'b2c';
  static const typeB2b = 'b2b';
  static const statusUnpaid = 'unpaid';
  static const statusPartial = 'partial';
  static const statusPaid = 'paid';
  static const lifecycleFinalized = 'finalized';
  static const lifecycleCancelled = 'cancelled';

  final int? id;
  final String uuid;
  final String shopId;
  final String billNumber;
  final String? invoiceSeriesUuid;
  final String billType;
  final int? customerId;
  final String? customerUuid;
  final String customerName;
  final String? customerPhone;
  final String? customerGstin;
  final String? customerGstLegalName;
  final String? customerGstTradeName;
  final String? customerAddressSnapshot;
  final String? placeOfSupplyStateCode;
  final double subtotalAmount;
  final double discountPercent;
  final double discountAmount;
  final double profitCommissionPercent;
  final double taxableAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;
  final double totalAmount;
  final int itemCount;
  final bool isPaid;
  final String paymentMethod;
  final double paidAmount;
  final double balanceDue;
  final String paymentStatus;
  final String lifecycleStatus;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final String? duplicatedFromBillUuid;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final List<BillItem> items;

  /// Transaction reference (e.g. UPI/online txn id) from the latest payment on
  /// this bill. Loaded transiently from `bill_payments` for display — it is not
  /// a `bills` column and is never written by [toMap].
  final String? transactionReference;

  Bill({
    this.id,
    String? uuid,
    this.shopId = '',
    String? billNumber,
    this.invoiceSeriesUuid,
    this.billType = typeB2c,
    this.customerId,
    this.customerUuid,
    this.customerName = 'Walk-in Customer',
    this.customerPhone,
    String? customerGstin,
    String? customerGstLegalName,
    String? customerGstTradeName,
    String? customerAddressSnapshot,
    String? placeOfSupplyStateCode,
    double? subtotalAmount,
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.profitCommissionPercent = 0,
    double? taxableAmount,
    this.cgstAmount = 0,
    this.sgstAmount = 0,
    this.igstAmount = 0,
    required this.totalAmount,
    required this.itemCount,
    this.isPaid = true,
    this.paymentMethod = 'cash',
    double? paidAmount,
    double? balanceDue,
    String? paymentStatus,
    this.lifecycleStatus = lifecycleFinalized,
    this.cancelledAt,
    String? cancelReason,
    String? duplicatedFromBillUuid,
    this.deviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.items = const [],
    String? transactionReference,
  }) : uuid = uuid ?? '',
       transactionReference = _cleanOptional(transactionReference),
       billNumber = billNumber ?? '',
       customerGstin = _cleanGstin(customerGstin),
       customerGstLegalName = _cleanOptional(customerGstLegalName),
       customerGstTradeName = _cleanOptional(customerGstTradeName),
       customerAddressSnapshot = _cleanOptional(customerAddressSnapshot),
       placeOfSupplyStateCode = _cleanStateCode(placeOfSupplyStateCode),
       subtotalAmount = subtotalAmount ?? totalAmount + discountAmount,
       taxableAmount = taxableAmount ?? totalAmount,
       paidAmount = paidAmount ?? (isPaid ? totalAmount : 0),
       balanceDue =
           balanceDue ??
           _balanceDue(totalAmount, paidAmount ?? (isPaid ? totalAmount : 0)),
       paymentStatus =
           paymentStatus ??
           _paymentStatus(
             totalAmount,
             paidAmount ?? (isPaid ? totalAmount : 0),
           ),
       cancelReason = _cleanOptional(cancelReason),
       duplicatedFromBillUuid = _cleanOptional(duplicatedFromBillUuid),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'uuid': uuid,
    'shop_id': shopId,
    'bill_number': billNumber,
    'invoice_series_uuid': invoiceSeriesUuid,
    'bill_type': billType,
    'customer_id': customerId,
    'customer_uuid': customerUuid,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'customer_gstin': customerGstin,
    'customer_gst_legal_name': customerGstLegalName,
    'customer_gst_trade_name': customerGstTradeName,
    'customer_address_snapshot': customerAddressSnapshot,
    'place_of_supply_state_code': placeOfSupplyStateCode,
    'subtotal_amount': subtotalAmount,
    'discount_percent': discountPercent,
    'discount_amount': discountAmount,
    'profit_commission_percent': profitCommissionPercent,
    'taxable_amount': taxableAmount,
    'cgst_amount': cgstAmount,
    'sgst_amount': sgstAmount,
    'igst_amount': igstAmount,
    'total_amount': totalAmount,
    'item_count': itemCount,
    'is_paid': isPaid ? 1 : 0,
    'payment_method': paymentMethod,
    'paid_amount': paidAmount,
    'balance_due': balanceDue,
    'payment_status': paymentStatus,
    'lifecycle_status': lifecycleStatus,
    'cancelled_at': cancelledAt?.toIso8601String(),
    'cancel_reason': cancelReason,
    'duplicated_from_bill_uuid': duplicatedFromBillUuid,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory Bill.fromMap(Map<String, dynamic> map, [List<BillItem>? items]) {
    final totalAmount = (map['total_amount'] as num).toDouble();
    final discountAmount = (map['discount_amount'] as num?)?.toDouble() ?? 0;
    final createdAt = DateTime.parse(map['created_at'] as String);
    final legacyPaid = (map['is_paid'] as int?) != 0;
    final paidAmount =
        (map['paid_amount'] as num?)?.toDouble() ??
        (legacyPaid ? totalAmount : 0);
    return Bill(
      id: map['id'] as int?,
      uuid: map['uuid'] as String? ?? '',
      shopId: map['shop_id'] as String? ?? '',
      billNumber: map['bill_number'] as String? ?? '',
      invoiceSeriesUuid: map['invoice_series_uuid'] as String?,
      billType: map['bill_type'] as String? ?? typeB2c,
      customerId: map['customer_id'] as int?,
      customerUuid: map['customer_uuid'] as String?,
      customerName: (map['customer_name'] as String?)?.trim().isNotEmpty == true
          ? (map['customer_name'] as String).trim()
          : 'Walk-in Customer',
      customerPhone:
          (map['customer_phone'] as String?)?.trim().isNotEmpty == true
          ? (map['customer_phone'] as String).trim()
          : null,
      customerGstin: map['customer_gstin'] as String?,
      customerGstLegalName: map['customer_gst_legal_name'] as String?,
      customerGstTradeName: map['customer_gst_trade_name'] as String?,
      customerAddressSnapshot: map['customer_address_snapshot'] as String?,
      placeOfSupplyStateCode: map['place_of_supply_state_code'] as String?,
      subtotalAmount:
          (map['subtotal_amount'] as num?)?.toDouble() ??
          totalAmount + discountAmount,
      discountPercent: (map['discount_percent'] as num?)?.toDouble() ?? 0,
      discountAmount: discountAmount,
      profitCommissionPercent:
          (map['profit_commission_percent'] as num?)?.toDouble() ?? 0,
      taxableAmount: (map['taxable_amount'] as num?)?.toDouble() ?? totalAmount,
      cgstAmount: (map['cgst_amount'] as num?)?.toDouble() ?? 0,
      sgstAmount: (map['sgst_amount'] as num?)?.toDouble() ?? 0,
      igstAmount: (map['igst_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: totalAmount,
      itemCount: map['item_count'] as int,
      isPaid: legacyPaid,
      paymentMethod: map['payment_method'] as String? ?? 'cash',
      paidAmount: paidAmount,
      balanceDue:
          (map['balance_due'] as num?)?.toDouble() ??
          _balanceDue(totalAmount, paidAmount),
      paymentStatus:
          map['payment_status'] as String? ??
          _paymentStatus(totalAmount, paidAmount),
      lifecycleStatus: map['lifecycle_status'] as String? ?? lifecycleFinalized,
      cancelledAt: map['cancelled_at'] == null
          ? null
          : DateTime.tryParse(map['cancelled_at'] as String),
      cancelReason: map['cancel_reason'] as String?,
      duplicatedFromBillUuid: map['duplicated_from_bill_uuid'] as String?,
      deviceId: map['device_id'] as String?,
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? createdAt,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse(map['deleted_at'] as String),
      items: items ?? [],
      // Not a `bills` column; supplied transiently when bills are loaded with
      // their latest payment reference joined in (see getAllBills).
      transactionReference: map['transaction_reference'] as String?,
    );
  }
}

class BillItem {
  final int? id;
  final String uuid;
  final String shopId;
  final int? billId;
  final String? billUuid;
  final int? productId;
  final String? productUuid;
  final String productName;
  final String? hsnCodeSnapshot;
  final String? hsnTypeSnapshot;
  String? unit;
  final double purchasePriceSnapshot;
  final double sellingPriceSnapshot;
  final double costSnapshot;
  final double profitSnapshot;
  final double commissionSnapshot;
  final double gstSnapshot;
  final double? gstPercentSnapshot;
  final double taxableValueSnapshot;
  final double cgstAmountSnapshot;
  final double sgstAmountSnapshot;
  final double igstAmountSnapshot;
  final bool wasDirectPrice;
  double quantity;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  double get mrp => sellingPriceSnapshot;
  double get subtotal => sellingPriceSnapshot * quantity;
  double get totalCost => costSnapshot * quantity;
  double get totalProfit => profitSnapshot * quantity;
  double get totalCommission => commissionSnapshot * quantity;
  double get totalGst => gstSnapshot * quantity;
  double get totalTaxableValue => taxableValueSnapshot * quantity;
  double get totalCgst => cgstAmountSnapshot * quantity;
  double get totalSgst => sgstAmountSnapshot * quantity;
  double get totalIgst => igstAmountSnapshot * quantity;
  double get totalNetProfit => totalProfit - totalCommission;
  String get unitLabel {
    final value = unit?.trim();
    return value == null || value.isEmpty ? '' : value;
  }

  String get priceLabel => unitLabel.isEmpty
      ? '₹${sellingPriceSnapshot.toStringAsFixed(2)}'
      : '₹${sellingPriceSnapshot.toStringAsFixed(2)} / $unitLabel';
  String get quantityLabel {
    final amount = quantity.toStringAsFixed(
      quantity == quantity.roundToDouble() ? 0 : 2,
    );
    return unitLabel.isEmpty ? amount : '$amount $unitLabel';
  }

  BillItem({
    this.id,
    String? uuid,
    this.shopId = '',
    this.billId,
    this.billUuid,
    this.productId,
    this.productUuid,
    required this.productName,
    String? hsnCodeSnapshot,
    String? hsnTypeSnapshot,
    double? mrp,
    this.unit,
    double? purchasePriceSnapshot,
    double? sellingPriceSnapshot,
    double? costSnapshot,
    double? profitSnapshot,
    double? commissionSnapshot,
    double? gstSnapshot,
    this.gstPercentSnapshot,
    double? taxableValueSnapshot,
    this.cgstAmountSnapshot = 0,
    this.sgstAmountSnapshot = 0,
    this.igstAmountSnapshot = 0,
    this.wasDirectPrice = true,
    num quantity = 1,
    this.deviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : uuid = uuid ?? '',
       hsnCodeSnapshot = _cleanHsnCode(hsnCodeSnapshot),
       hsnTypeSnapshot = _cleanOptional(hsnTypeSnapshot),
       sellingPriceSnapshot = sellingPriceSnapshot ?? mrp ?? 0,
       purchasePriceSnapshot = purchasePriceSnapshot ?? mrp ?? 0,
       costSnapshot = costSnapshot ?? purchasePriceSnapshot ?? mrp ?? 0,
       profitSnapshot = profitSnapshot ?? 0,
       commissionSnapshot = commissionSnapshot ?? 0,
       gstSnapshot = gstSnapshot ?? 0,
       taxableValueSnapshot =
           taxableValueSnapshot ??
           ((sellingPriceSnapshot ?? mrp ?? 0) - (gstSnapshot ?? 0)),
       quantity = quantity.toDouble(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toMap(int billId, {String? billUuid}) => {
    'id': id,
    'uuid': uuid,
    'shop_id': shopId,
    'bill_id': billId,
    'bill_uuid': billUuid ?? this.billUuid,
    'product_id': productId,
    'product_uuid': productUuid,
    'product_name': productName,
    'hsn_code_snapshot': hsnCodeSnapshot,
    'hsn_type_snapshot': hsnTypeSnapshot,
    'unit_name': unit,
    'purchase_price_snapshot': purchasePriceSnapshot,
    'selling_price_snapshot': sellingPriceSnapshot,
    'cost_snapshot': costSnapshot,
    'profit_snapshot': profitSnapshot,
    'commission_snapshot': commissionSnapshot,
    'gst_snapshot': gstSnapshot,
    'gst_percent_snapshot': gstPercentSnapshot,
    'taxable_value_snapshot': taxableValueSnapshot,
    'cgst_amount_snapshot': cgstAmountSnapshot,
    'sgst_amount_snapshot': sgstAmountSnapshot,
    'igst_amount_snapshot': igstAmountSnapshot,
    'was_direct_price': wasDirectPrice ? 1 : 0,
    'quantity': quantity,
    'subtotal': subtotal,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory BillItem.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.parse(map['created_at'] as String);
    return BillItem(
      id: map['id'] as int?,
      uuid: map['uuid'] as String? ?? '',
      shopId: map['shop_id'] as String? ?? '',
      billId: map['bill_id'] as int?,
      billUuid: map['bill_uuid'] as String?,
      productId: map['product_id'] as int?,
      productUuid: map['product_uuid'] as String?,
      productName: map['product_name'] as String,
      hsnCodeSnapshot: map['hsn_code_snapshot'] as String?,
      hsnTypeSnapshot: map['hsn_type_snapshot'] as String?,
      mrp: (map['mrp'] as num?)?.toDouble(),
      unit: _cleanOptional(
        map['unit_name'] as String? ?? map['unit'] as String?,
      ),
      purchasePriceSnapshot: (map['purchase_price_snapshot'] as num?)
          ?.toDouble(),
      sellingPriceSnapshot: (map['selling_price_snapshot'] as num?)?.toDouble(),
      costSnapshot: (map['cost_snapshot'] as num?)?.toDouble(),
      profitSnapshot: (map['profit_snapshot'] as num?)?.toDouble(),
      commissionSnapshot: (map['commission_snapshot'] as num?)?.toDouble(),
      gstSnapshot: (map['gst_snapshot'] as num?)?.toDouble(),
      gstPercentSnapshot: (map['gst_percent_snapshot'] as num?)?.toDouble(),
      taxableValueSnapshot: (map['taxable_value_snapshot'] as num?)?.toDouble(),
      cgstAmountSnapshot:
          (map['cgst_amount_snapshot'] as num?)?.toDouble() ?? 0,
      sgstAmountSnapshot:
          (map['sgst_amount_snapshot'] as num?)?.toDouble() ?? 0,
      igstAmountSnapshot:
          (map['igst_amount_snapshot'] as num?)?.toDouble() ?? 0,
      wasDirectPrice: (map['was_direct_price'] as int? ?? 1) == 1,
      quantity: (map['quantity'] as num).toDouble(),
      deviceId: map['device_id'] as String?,
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? createdAt,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse(map['deleted_at'] as String),
    );
  }
}

class InvoiceSeries {
  final int? id;
  final String uuid;
  final String shopId;
  final String name;
  final String formatTemplate;
  final int sequencePadding;
  final String resetPeriod;
  final String allocationMode;
  final int nextSequence;
  final bool isDefault;
  final bool isActive;
  final bool deviceTokenRequired;
  final String? lastSequenceKey;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const InvoiceSeries({
    this.id,
    this.uuid = '',
    this.shopId = '',
    required this.name,
    required this.formatTemplate,
    this.sequencePadding = 4,
    this.resetPeriod = 'financial_year',
    this.allocationMode = 'local_device',
    this.nextSequence = 1,
    this.isDefault = false,
    this.isActive = true,
    this.deviceTokenRequired = true,
    this.lastSequenceKey,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory InvoiceSeries.fromMap(Map<String, dynamic> map) => InvoiceSeries(
    id: map['id'] as int?,
    uuid: map['uuid'] as String? ?? '',
    shopId: map['shop_id'] as String? ?? '',
    name: map['name'] as String,
    formatTemplate: map['format_template'] as String,
    sequencePadding: map['sequence_padding'] as int? ?? 4,
    resetPeriod: map['reset_period'] as String? ?? 'financial_year',
    allocationMode: map['allocation_mode'] as String? ?? 'local_device',
    nextSequence: map['next_sequence'] as int? ?? 1,
    isDefault: (map['is_default'] as int? ?? 0) == 1,
    isActive: (map['is_active'] as int? ?? 1) == 1,
    deviceTokenRequired: (map['device_token_required'] as int? ?? 1) == 1,
    lastSequenceKey: map['last_sequence_key'] as String?,
    deviceId: map['device_id'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt:
        DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
        DateTime.parse(map['created_at'] as String),
    deletedAt: map['deleted_at'] == null
        ? null
        : DateTime.tryParse(map['deleted_at'] as String),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'uuid': uuid,
    'shop_id': shopId,
    'name': name,
    'format_template': formatTemplate,
    'sequence_padding': sequencePadding,
    'reset_period': resetPeriod,
    'allocation_mode': allocationMode,
    'next_sequence': nextSequence,
    'is_default': isDefault ? 1 : 0,
    'is_active': isActive ? 1 : 0,
    'device_token_required': deviceTokenRequired ? 1 : 0,
    'last_sequence_key': lastSequenceKey,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

class BillPayment {
  final int? id;
  final String uuid;
  final String shopId;
  final String billUuid;
  final double amount;
  final String paymentMethod;
  final String? paymentReference;
  final String? notes;
  final DateTime receivedAt;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  BillPayment({
    this.id,
    this.uuid = '',
    this.shopId = '',
    required this.billUuid,
    required this.amount,
    this.paymentMethod = 'cash',
    this.paymentReference,
    this.notes,
    DateTime? receivedAt,
    this.deviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : receivedAt = receivedAt ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  factory BillPayment.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.parse(map['created_at'] as String);
    return BillPayment(
      id: map['id'] as int?,
      uuid: map['uuid'] as String? ?? '',
      shopId: map['shop_id'] as String? ?? '',
      billUuid: map['bill_uuid'] as String,
      amount: (map['amount'] as num).toDouble(),
      paymentMethod: map['payment_method'] as String? ?? 'cash',
      paymentReference: map['payment_reference'] as String?,
      notes: map['notes'] as String?,
      receivedAt: DateTime.parse(map['received_at'] as String),
      deviceId: map['device_id'] as String?,
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? createdAt,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse(map['deleted_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'uuid': uuid,
    'shop_id': shopId,
    'bill_uuid': billUuid,
    'amount': amount,
    'payment_method': paymentMethod,
    'payment_reference': _cleanOptional(paymentReference),
    'notes': _cleanOptional(notes),
    'received_at': receivedAt.toIso8601String(),
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };
}

double _balanceDue(double total, double paid) {
  final due = total - paid;
  return due <= 0.005 ? 0 : due;
}

String _paymentStatus(double total, double paid) {
  if (paid <= 0.005) return Bill.statusUnpaid;
  if (paid + 0.005 >= total) return Bill.statusPaid;
  return Bill.statusPartial;
}

String? _cleanOptional(String? value) {
  final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _cleanGstin(String? value) {
  final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), '').toUpperCase();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _cleanStateCode(String? value) {
  final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits == null || digits.isEmpty) return null;
  return digits.padLeft(2, '0').substring(0, 2);
}

String? _cleanHsnCode(String? value) {
  final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
  return digits == null || digits.isEmpty ? null : digits;
}
