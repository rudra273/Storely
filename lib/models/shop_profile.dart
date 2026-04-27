class ShopProfile {
  final int? id;
  final String uuid;
  final String name;
  final String? phone;
  final String? email;
  final String? gstin;
  final String? address;
  final bool gstRegistered;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  ShopProfile({
    this.id,
    String? uuid,
    required this.name,
    String? phone,
    String? email,
    String? gstin,
    String? address,
    this.gstRegistered = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : uuid = uuid ?? '',
       phone = _cleanOptional(phone),
       email = _cleanOptional(email),
       gstin = _cleanOptional(gstin),
       address = _cleanOptional(address),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  factory ShopProfile.fromMap(
    Map<String, dynamic> map, {
    bool gstRegistered = false,
  }) {
    return ShopProfile(
      id: map['id'] as int?,
      uuid: map['uuid'] as String? ?? '',
      name: map['name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      gstin: map['gstin'] as String?,
      address: map['address'] as String?,
      gstRegistered: gstRegistered,
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
    'name': name,
    'phone': phone,
    'email': email,
    'gstin': gstin,
    'address': address,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  static String? _cleanOptional(String? value) {
    final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
