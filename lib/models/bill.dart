class Bill {
  final int? id;
  final String uuid;
  final String shopId;
  final String billNumber;
  final int? customerId;
  final String? customerUuid;
  final String customerName;
  final String? customerPhone;
  final double subtotalAmount;
  final double discountPercent;
  final double discountAmount;
  final double profitCommissionPercent;
  final double totalAmount;
  final int itemCount;
  final bool isPaid;
  final String paymentMethod;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final List<BillItem> items;

  Bill({
    this.id,
    String? uuid,
    this.shopId = 'local-shop',
    String? billNumber,
    this.customerId,
    this.customerUuid,
    this.customerName = 'Walk-in Customer',
    this.customerPhone,
    double? subtotalAmount,
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.profitCommissionPercent = 0,
    required this.totalAmount,
    required this.itemCount,
    this.isPaid = true,
    this.paymentMethod = 'cash',
    this.deviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
    this.items = const [],
  }) : uuid = uuid ?? '',
       billNumber = billNumber ?? '',
       subtotalAmount = subtotalAmount ?? totalAmount + discountAmount,
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'uuid': uuid,
    'shop_id': shopId,
    'bill_number': billNumber,
    'customer_id': customerId,
    'customer_uuid': customerUuid,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'subtotal_amount': subtotalAmount,
    'discount_percent': discountPercent,
    'discount_amount': discountAmount,
    'profit_commission_percent': profitCommissionPercent,
    'total_amount': totalAmount,
    'item_count': itemCount,
    'is_paid': isPaid ? 1 : 0,
    'payment_method': paymentMethod,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory Bill.fromMap(Map<String, dynamic> map, [List<BillItem>? items]) {
    final totalAmount = (map['total_amount'] as num).toDouble();
    final discountAmount = (map['discount_amount'] as num?)?.toDouble() ?? 0;
    final createdAt = DateTime.parse(map['created_at'] as String);
    return Bill(
      id: map['id'] as int?,
      uuid: map['uuid'] as String? ?? '',
      shopId: map['shop_id'] as String? ?? 'local-shop',
      billNumber: map['bill_number'] as String? ?? '',
      customerId: map['customer_id'] as int?,
      customerUuid: map['customer_uuid'] as String?,
      customerName: (map['customer_name'] as String?)?.trim().isNotEmpty == true
          ? (map['customer_name'] as String).trim()
          : 'Walk-in Customer',
      customerPhone:
          (map['customer_phone'] as String?)?.trim().isNotEmpty == true
          ? (map['customer_phone'] as String).trim()
          : null,
      subtotalAmount:
          (map['subtotal_amount'] as num?)?.toDouble() ??
          totalAmount + discountAmount,
      discountPercent: (map['discount_percent'] as num?)?.toDouble() ?? 0,
      discountAmount: discountAmount,
      profitCommissionPercent:
          (map['profit_commission_percent'] as num?)?.toDouble() ?? 0,
      totalAmount: totalAmount,
      itemCount: map['item_count'] as int,
      isPaid: (map['is_paid'] as int?) != 0,
      paymentMethod: map['payment_method'] as String? ?? 'cash',
      deviceId: map['device_id'] as String?,
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? createdAt,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse(map['deleted_at'] as String),
      items: items ?? [],
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
  String? unit;
  final double purchasePriceSnapshot;
  final double sellingPriceSnapshot;
  final double costSnapshot;
  final double profitSnapshot;
  final double commissionSnapshot;
  final double gstSnapshot;
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
    this.shopId = 'local-shop',
    this.billId,
    this.billUuid,
    this.productId,
    this.productUuid,
    required this.productName,
    double? mrp,
    this.unit,
    double? purchasePriceSnapshot,
    double? sellingPriceSnapshot,
    double? costSnapshot,
    double? profitSnapshot,
    double? commissionSnapshot,
    double? gstSnapshot,
    this.wasDirectPrice = true,
    num quantity = 1,
    this.deviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : uuid = uuid ?? '',
       sellingPriceSnapshot = sellingPriceSnapshot ?? mrp ?? 0,
       purchasePriceSnapshot = purchasePriceSnapshot ?? mrp ?? 0,
       costSnapshot = costSnapshot ?? purchasePriceSnapshot ?? mrp ?? 0,
       profitSnapshot = profitSnapshot ?? 0,
       commissionSnapshot = commissionSnapshot ?? 0,
       gstSnapshot = gstSnapshot ?? 0,
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
    'unit_name': unit,
    'purchase_price_snapshot': purchasePriceSnapshot,
    'selling_price_snapshot': sellingPriceSnapshot,
    'cost_snapshot': costSnapshot,
    'profit_snapshot': profitSnapshot,
    'commission_snapshot': commissionSnapshot,
    'gst_snapshot': gstSnapshot,
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
      shopId: map['shop_id'] as String? ?? 'local-shop',
      billId: map['bill_id'] as int?,
      billUuid: map['bill_uuid'] as String?,
      productId: map['product_id'] as int?,
      productUuid: map['product_uuid'] as String?,
      productName: map['product_name'] as String,
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

  static String? _cleanOptional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
