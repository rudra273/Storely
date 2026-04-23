class Bill {
  final int? id;
  final double totalAmount;
  final int itemCount;
  final DateTime createdAt;
  final List<BillItem> items;

  Bill({
    this.id,
    required this.totalAmount,
    required this.itemCount,
    DateTime? createdAt,
    this.items = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'total_amount': totalAmount,
    'item_count': itemCount,
    'created_at': createdAt.toIso8601String(),
  };

  factory Bill.fromMap(Map<String, dynamic> map, [List<BillItem>? items]) {
    return Bill(
      id: map['id'] as int?,
      totalAmount: (map['total_amount'] as num).toDouble(),
      itemCount: map['item_count'] as int,
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
