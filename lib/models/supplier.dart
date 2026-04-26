class SupplierProfile {
  final int? id;
  final String uuid;
  final String shopId;
  final String name;
  final String? phone;
  final String? email;
  final String? gstin;
  final String? address;
  final String? notes;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  SupplierProfile({
    this.id,
    String? uuid,
    this.shopId = 'local-shop',
    required this.name,
    String? phone,
    String? email,
    String? gstin,
    String? address,
    String? notes,
    this.deviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : uuid = uuid ?? '',
       phone = _cleanOptional(phone),
       email = _cleanOptional(email),
       gstin = _cleanOptional(gstin),
       address = _cleanOptional(address),
       notes = _cleanOptional(notes),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  factory SupplierProfile.fromMap(Map<String, dynamic> map) {
    return SupplierProfile(
      id: map['id'] as int?,
      uuid: map['uuid'] as String? ?? '',
      shopId: map['shop_id'] as String? ?? 'local-shop',
      name: map['name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      gstin: map['gstin'] as String?,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
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
    'phone': phone,
    'email': email,
    'gstin': gstin,
    'address': address,
    'notes': notes,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  SupplierProfile copyWith({
    int? id,
    String? uuid,
    String? shopId,
    String? name,
    String? phone,
    String? email,
    String? gstin,
    String? address,
    String? notes,
    String? deviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearPhone = false,
    bool clearEmail = false,
    bool clearGstin = false,
    bool clearAddress = false,
    bool clearNotes = false,
    bool clearDeletedAt = false,
  }) {
    return SupplierProfile(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      shopId: shopId ?? this.shopId,
      name: name ?? this.name,
      phone: clearPhone ? null : phone ?? this.phone,
      email: clearEmail ? null : email ?? this.email,
      gstin: clearGstin ? null : gstin ?? this.gstin,
      address: clearAddress ? null : address ?? this.address,
      notes: clearNotes ? null : notes ?? this.notes,
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
