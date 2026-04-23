class Bill {
  final int? id;
  final String customerName;
  final String? customerPhone;
  final double subtotalAmount;
  final double discountPercent;
  final double discountAmount;
  final double totalAmount;
  final int itemCount;
  final bool isPaid;
  final DateTime createdAt;
  final List<BillItem> items;

  Bill({
    this.id,
    this.customerName = 'Walk-in Customer',
    this.customerPhone,
    double? subtotalAmount,
    this.discountPercent = 0,
    this.discountAmount = 0,
    required this.totalAmount,
    required this.itemCount,
    this.isPaid = true,
    DateTime? createdAt,
    this.items = const [],
  }) : subtotalAmount = subtotalAmount ?? totalAmount + discountAmount,
       createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'subtotal_amount': subtotalAmount,
    'discount_percent': discountPercent,
    'discount_amount': discountAmount,
    'total_amount': totalAmount,
    'item_count': itemCount,
    'is_paid': isPaid ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
  };

  factory Bill.fromMap(Map<String, dynamic> map, [List<BillItem>? items]) {
    final totalAmount = (map['total_amount'] as num).toDouble();
    final discountAmount = (map['discount_amount'] as num?)?.toDouble() ?? 0;
    return Bill(
      id: map['id'] as int?,
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
      totalAmount: totalAmount,
      itemCount: map['item_count'] as int,
      isPaid: (map['is_paid'] as int?) != 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      items: items ?? [],
    );
  }
}

class BillItem {
  final int? id;
  final int? billId;
  final String productName;
  final double mrp;
  int quantity;

  double get subtotal => mrp * quantity;

  BillItem({
    this.id,
    this.billId,
    required this.productName,
    required this.mrp,
    this.quantity = 1,
  });

  Map<String, dynamic> toMap(int billId) => {
    'bill_id': billId,
    'product_name': productName,
    'mrp': mrp,
    'quantity': quantity,
    'subtotal': subtotal,
  };

  factory BillItem.fromMap(Map<String, dynamic> map) {
    return BillItem(
      id: map['id'] as int?,
      billId: map['bill_id'] as int?,
      productName: map['product_name'] as String,
      mrp: (map['mrp'] as num).toDouble(),
      quantity: map['quantity'] as int,
    );
  }
}
