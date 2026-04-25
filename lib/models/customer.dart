class Customer {
  final int? id;
  final String name;
  final String phone;
  final double totalPurchaseAmount;
  final int billCount;
  final DateTime? lastPurchaseAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Customer({
    this.id,
    required this.name,
    required this.phone,
    required this.totalPurchaseAmount,
    required this.billCount,
    this.lastPurchaseAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String,
      totalPurchaseAmount: (map['total_purchase_amount'] as num).toDouble(),
      billCount: map['bill_count'] as int,
      lastPurchaseAt: map['last_purchase_at'] == null
          ? null
          : DateTime.parse(map['last_purchase_at'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
