import 'dart:convert';

class ProductSource {
  static const mobile = 'mobile';
  static const imported = 'imported';
}

class Product {
  final int? id;
  final String? itemCode;
  final String name;
  final String? category;
  final double mrp;
  final int quantity;
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
    this.supplier,
    this.source = ProductSource.mobile,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isImported => source == ProductSource.imported;
  String get sourceLabel => isImported ? 'Imported' : 'Mobile';

  Map<String, dynamic> toMap() => {
    'id': id,
    'item_code': itemCode,
    'name': name,
    'category': category,
    'mrp': mrp,
    'quantity': quantity,
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
    supplier: supplier ?? this.supplier,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
  );

  String toQrData() {
    final map = <String, dynamic>{'name': name, 'mrp': mrp, 'qty': quantity};
    if (itemCode != null) map['code'] = itemCode;
    if (category != null) map['cat'] = category;
    return jsonEncode(map);
  }
}
