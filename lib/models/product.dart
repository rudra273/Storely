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
  final double purchasePrice;
  final double? gstPercent;
  final double? overheadCost;
  final double? profitMarginPercent;
  final bool directPriceToggle;
  final double? manualPrice;
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
    double? purchasePrice,
    this.gstPercent,
    this.overheadCost,
    this.profitMarginPercent,
    this.directPriceToggle = false,
    this.manualPrice,
    required this.quantity,
    this.unit,
    this.supplier,
    this.source = ProductSource.mobile,
    DateTime? createdAt,
  }) : purchasePrice = purchasePrice ?? mrp,
       createdAt = createdAt ?? DateTime.now();

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
    'purchase_price': purchasePrice,
    'gst_percent': gstPercent,
    'overhead_cost': overheadCost,
    'profit_margin_percent': profitMarginPercent,
    'direct_price_toggle': directPriceToggle ? 1 : 0,
    'manual_price': manualPrice,
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
    purchasePrice:
        (map['purchase_price'] as num?)?.toDouble() ??
        (map['mrp'] as num).toDouble(),
    gstPercent: (map['gst_percent'] as num?)?.toDouble(),
    overheadCost: (map['overhead_cost'] as num?)?.toDouble(),
    profitMarginPercent: (map['profit_margin_percent'] as num?)?.toDouble(),
    directPriceToggle: (map['direct_price_toggle'] as int? ?? 1) == 1,
    manualPrice: (map['manual_price'] as num?)?.toDouble(),
    quantity: map['quantity'] as int,
    unit: _cleanOptional(map['unit'] as String?),
    supplier: map['supplier'] as String?,
    source: map['source'] as String? ?? ProductSource.mobile,
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  Product copyWith({
    int? id,
    bool clearItemCode = false,
    String? itemCode,
    String? name,
    bool clearCategory = false,
    String? category,
    double? mrp,
    double? purchasePrice,
    bool clearGstPercent = false,
    double? gstPercent,
    bool clearOverheadCost = false,
    double? overheadCost,
    bool clearProfitMarginPercent = false,
    double? profitMarginPercent,
    bool? directPriceToggle,
    bool clearManualPrice = false,
    double? manualPrice,
    int? quantity,
    bool clearUnit = false,
    String? unit,
    bool clearSupplier = false,
    String? supplier,
    String? source,
    DateTime? createdAt,
  }) => Product(
    id: id ?? this.id,
    itemCode: clearItemCode ? null : itemCode ?? this.itemCode,
    name: name ?? this.name,
    category: clearCategory ? null : category ?? this.category,
    mrp: mrp ?? this.mrp,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    gstPercent: clearGstPercent ? null : gstPercent ?? this.gstPercent,
    overheadCost: clearOverheadCost ? null : overheadCost ?? this.overheadCost,
    profitMarginPercent: clearProfitMarginPercent
        ? null
        : profitMarginPercent ?? this.profitMarginPercent,
    directPriceToggle: directPriceToggle ?? this.directPriceToggle,
    manualPrice: clearManualPrice ? null : manualPrice ?? this.manualPrice,
    quantity: quantity ?? this.quantity,
    unit: clearUnit ? null : unit ?? this.unit,
    supplier: clearSupplier ? null : supplier ?? this.supplier,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
  );

  String toQrData() {
    final map = <String, dynamic>{'name': name, 'mrp': mrp, 'qty': quantity};
    if (id != null) map['id'] = id;
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
