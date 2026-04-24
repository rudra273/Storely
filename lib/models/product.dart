import 'dart:convert';

class ProductSource {
  static const mobile = 'mobile';
  static const imported = 'imported';
}

class Product {
  static const presetUnits = [
    'pcs',
    'pkt',
    'kg',
    'g',
    'mtr',
    'sqft',
    'box',
    'dozen',
    'ltr',
    'ml',
  ];

  final int? id;
  final String? itemCode;
  final String name;
  final String? category;
  final double mrp;
  final int quantity;
  final String? unit;
  final String? supplier;
  final String source;
  final DateTime createdAt;

  Product({
    this.id,
    this.itemCode,
    required this.name,
    this.category,
    required this.mrp,
    required this.quantity,
    this.unit,
    this.supplier,
    this.source = ProductSource.mobile,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isImported => source == ProductSource.imported;
  String get sourceLabel => isImported ? 'Imported' : 'Mobile';
  String get priceLabel {
    final amount = mrp.toStringAsFixed(mrp == mrp.roundToDouble() ? 0 : 2);
    return unit == null || unit!.trim().isEmpty
        ? '₹$amount'
        : '₹$amount / ${unit!.trim()}';
  }

  String get quantityLabel => unit == null || unit!.trim().isEmpty
      ? '$quantity'
      : '$quantity ${unit!.trim()}';

  Map<String, dynamic> toMap() => {
    'id': id,
    'item_code': itemCode,
    'name': name,
    'category': category,
    'mrp': mrp,
    'quantity': quantity,
    'unit': unit,
    'supplier': supplier,
    'source': source,
    'created_at': createdAt.toIso8601String(),
  };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
    id: map['id'] as int?,
    itemCode: map['item_code'] as String?,
    name: map['name'] as String,
    category: map['category'] as String?,
    mrp: (map['mrp'] as num).toDouble(),
    quantity: map['quantity'] as int,
    unit: _cleanOptional(map['unit'] as String?),
    supplier: map['supplier'] as String?,
    source: map['source'] as String? ?? ProductSource.mobile,
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  Product copyWith({
    int? id,
    String? itemCode,
    String? name,
    String? category,
    double? mrp,
    int? quantity,
    String? unit,
    String? supplier,
    String? source,
    DateTime? createdAt,
  }) => Product(
    id: id ?? this.id,
    itemCode: itemCode ?? this.itemCode,
    name: name ?? this.name,
    category: category ?? this.category,
    mrp: mrp ?? this.mrp,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    supplier: supplier ?? this.supplier,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
  );

  String toQrData() {
    final map = <String, dynamic>{'name': name, 'mrp': mrp, 'qty': quantity};
    final unitValue = unit?.trim();
    if (unitValue != null && unitValue.isNotEmpty) map['unit'] = unitValue;
    if (itemCode != null) map['code'] = itemCode;
    if (category != null) map['cat'] = category;
    return jsonEncode(map);
  }

  static String? _cleanOptional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
