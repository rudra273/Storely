class Bill {
  final int? id;
  final int? customerId;
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
  final DateTime createdAt;
  final List<BillItem> items;

  Bill({
    this.id,
    this.customerId,
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
    DateTime? createdAt,
    this.items = const [],
  }) : subtotalAmount = subtotalAmount ?? totalAmount + discountAmount,
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_id': customerId,
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
    'created_at': createdAt.toIso8601String(),
  };

  factory Bill.fromMap(Map<String, dynamic> map, [List<BillItem>? items]) {
    final totalAmount = (map['total_amount'] as num).toDouble();
    final discountAmount = (map['discount_amount'] as num?)?.toDouble() ?? 0;
    return Bill(
      id: map['id'] as int?,
      customerId: map['customer_id'] as int?,
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
      createdAt: DateTime.parse(map['created_at'] as String),
      items: items ?? [],
    );
  }
}

class BillItem {
  final int? id;
  final int? billId;
  final int? productId;
  final String productName;
  final double mrp;
  String? unit;
  final double purchasePriceSnapshot;
  final double sellingPriceSnapshot;
  final double costSnapshot;
  final double profitSnapshot;
  final double commissionSnapshot;
  final double gstSnapshot;
  final bool wasDirectPrice;
  int quantity;

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
  String get quantityLabel =>
      unitLabel.isEmpty ? '$quantity' : '$quantity $unitLabel';

  BillItem({
    this.id,
    this.billId,
    this.productId,
    required this.productName,
    required this.mrp,
    this.unit,
    double? purchasePriceSnapshot,
    double? sellingPriceSnapshot,
    double? costSnapshot,
    double? profitSnapshot,
    double? commissionSnapshot,
    double? gstSnapshot,
    this.wasDirectPrice = true,
    this.quantity = 1,
  }) : purchasePriceSnapshot = purchasePriceSnapshot ?? mrp,
       sellingPriceSnapshot = sellingPriceSnapshot ?? mrp,
       costSnapshot = costSnapshot ?? mrp,
       profitSnapshot = profitSnapshot ?? 0,
       commissionSnapshot = commissionSnapshot ?? 0,
       gstSnapshot = gstSnapshot ?? 0;

  Map<String, dynamic> toMap(int billId) => {
    'bill_id': billId,
    'product_id': productId,
    'product_name': productName,
    'mrp': mrp,
    'unit': unit,
    'purchase_price_snapshot': purchasePriceSnapshot,
    'selling_price_snapshot': sellingPriceSnapshot,
    'cost_snapshot': costSnapshot,
    'profit_snapshot': profitSnapshot,
    'commission_snapshot': commissionSnapshot,
    'gst_snapshot': gstSnapshot,
    'was_direct_price': wasDirectPrice ? 1 : 0,
    'quantity': quantity,
    'subtotal': subtotal,
  };

  factory BillItem.fromMap(Map<String, dynamic> map) {
    return BillItem(
      id: map['id'] as int?,
      billId: map['bill_id'] as int?,
      productId: map['product_id'] as int?,
      productName: map['product_name'] as String,
      mrp: (map['mrp'] as num).toDouble(),
      unit: _cleanOptional(map['unit'] as String?),
      purchasePriceSnapshot: (map['purchase_price_snapshot'] as num?)
          ?.toDouble(),
      sellingPriceSnapshot: (map['selling_price_snapshot'] as num?)?.toDouble(),
      costSnapshot: (map['cost_snapshot'] as num?)?.toDouble(),
      profitSnapshot: (map['profit_snapshot'] as num?)?.toDouble(),
      commissionSnapshot: (map['commission_snapshot'] as num?)?.toDouble(),
      gstSnapshot: (map['gst_snapshot'] as num?)?.toDouble(),
      wasDirectPrice: (map['was_direct_price'] as int? ?? 1) == 1,
      quantity: map['quantity'] as int,
    );
  }

  static String? _cleanOptional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
