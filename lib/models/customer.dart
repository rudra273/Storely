class Customer {
  final int? id;
  final String uuid;
  final String shopId;
  final String name;
  final String phone;
  final String? email;
  final String? address;
  final String? notes;
  final double totalPurchaseAmount;
  final int billCount;
  final DateTime? lastPurchaseAt;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Customer({
    this.id,
    this.uuid = '',
    this.shopId = 'local-shop',
    required this.name,
    required this.phone,
    this.email,
    this.address,
    this.notes,
    required this.totalPurchaseAmount,
    required this.billCount,
    this.lastPurchaseAt,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as int?,
      uuid: map['uuid'] as String? ?? '',
      shopId: map['shop_id'] as String? ?? 'local-shop',
      name: map['name'] as String,
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      totalPurchaseAmount: (map['total_purchase_amount'] as num).toDouble(),
      billCount: map['bill_count'] as int,
      lastPurchaseAt: map['last_purchase_at'] == null
          ? null
          : DateTime.parse(map['last_purchase_at'] as String),
      deviceId: map['device_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
          DateTime.parse(map['created_at'] as String),
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse(map['deleted_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'uuid': uuid,
    'shop_id': shopId,
    'name': name,
    'phone': phone.trim().isEmpty ? null : phone,
    'email': _cleanOptional(email),
    'address': _cleanOptional(address),
    'notes': _cleanOptional(notes),
    'total_purchase_amount': totalPurchaseAmount,
    'bill_count': billCount,
    'last_purchase_at': lastPurchaseAt?.toIso8601String(),
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  Customer copyWith({
    int? id,
    String? uuid,
    String? shopId,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? notes,
    double? totalPurchaseAmount,
    int? billCount,
    DateTime? lastPurchaseAt,
    String? deviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearEmail = false,
    bool clearAddress = false,
    bool clearNotes = false,
    bool clearLastPurchaseAt = false,
    bool clearDeletedAt = false,
  }) {
    return Customer(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: clearEmail ? null : email ?? this.email,
      address: clearAddress ? null : address ?? this.address,
      notes: clearNotes ? null : notes ?? this.notes,
      totalPurchaseAmount: totalPurchaseAmount ?? this.totalPurchaseAmount,
      billCount: billCount ?? this.billCount,
      lastPurchaseAt: clearLastPurchaseAt
          ? null
          : lastPurchaseAt ?? this.lastPurchaseAt,
      deviceId: deviceId ?? this.deviceId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  static String? _cleanOptional(String? value) {
    final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
