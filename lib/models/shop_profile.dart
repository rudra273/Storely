/// How the shop is registered under GST. Decides the document type:
/// regular -> TAX INVOICE with GST; composition -> BILL OF SUPPLY, no tax;
/// unregistered -> plain BILL, no GST.
class GstScheme {
  static const regular = 'regular';
  static const composition = 'composition';
  static const unregistered = 'unregistered';
  static const values = [regular, composition, unregistered];

  /// Legend CGST Rule 49 requires on a composition dealer's bill of supply.
  static const compositionLegend =
      'Composition taxable person, not eligible to collect tax on supplies';

  static String clean(String? value, {bool fallbackRegistered = false}) {
    if (values.contains(value)) return value!;
    return fallbackRegistered ? regular : unregistered;
  }

  static String label(String scheme) => switch (scheme) {
    regular => 'GST registered (regular)',
    composition => 'GST composition scheme',
    _ => 'GST not registered',
  };
}

class ShopProfile {
  final int? id;
  final String uuid;
  final String name;
  final String? phone;
  final String? email;
  final String? gstin;
  final String? address;
  final String gstScheme;
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
    bool gstRegistered = false,
    String? gstScheme,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : uuid = uuid ?? '',
       gstScheme = GstScheme.clean(
         gstScheme,
         fallbackRegistered: gstRegistered,
       ),
       phone = _cleanOptional(phone),
       email = _cleanOptional(email),
       gstin = _cleanOptional(gstin),
       address = _cleanOptional(address),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  /// Charges GST on its bills (regular scheme only).
  bool get gstRegistered => gstScheme == GstScheme.regular;

  /// Has a GSTIN (regular or composition).
  bool get hasGstRegistration => gstScheme != GstScheme.unregistered;

  factory ShopProfile.fromMap(Map<String, dynamic> map, {String? gstScheme}) {
    return ShopProfile(
      id: map['id'] as int?,
      uuid: map['uuid'] as String? ?? '',
      name: map['name'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      gstin: map['gstin'] as String?,
      address: map['address'] as String?,
      gstScheme: gstScheme,
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
