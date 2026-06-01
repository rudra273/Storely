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
  final String uuid;
  final String shopId;
  final String? productCode;
  final String? barcode;
  final String name;
  final String? hsnCode;
  final String? hsnType;
  final String? hsnDescription;
  final int? categoryId;
  final String? category;
  final int? supplierId;
  final String? supplier;
  final double sellingPrice;
  final double purchasePrice;
  final double? gstPercent;
  final double? overheadCost;
  final double? profitMarginPercent;
  final bool directPriceToggle;
  final double? manualPrice;
  final double quantity;
  final int? unitId;
  final String? unit;
  final String source;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Product({
    this.id,
    String? uuid,
    this.shopId = '',
    String? itemCode,
    String? productCode,
    String? barcode,
    required this.name,
    String? hsnCode,
    String? hsnType,
    String? hsnDescription,
    this.categoryId,
    this.category,
    this.supplierId,
    this.supplier,
    double? mrp,
    double? sellingPrice,
    double? purchasePrice,
    this.gstPercent,
    this.overheadCost,
    this.profitMarginPercent,
    this.directPriceToggle = false,
    this.manualPrice,
    required num quantity,
    this.unitId,
    this.unit,
    this.source = ProductSource.mobile,
    this.deviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : uuid = uuid ?? '',
       productCode = _cleanOptional(productCode ?? itemCode),
       barcode = _cleanOptional(barcode),
       hsnCode = _cleanHsnCode(hsnCode),
       hsnType = _cleanOptional(hsnType),
       hsnDescription = _cleanOptional(hsnDescription),
       sellingPrice = sellingPrice ?? mrp ?? 0,
       purchasePrice = purchasePrice ?? sellingPrice ?? mrp ?? 0,
       quantity = quantity.toDouble(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  String? get itemCode => productCode;
  double get mrp => sellingPrice;
  bool get isImported => source == ProductSource.imported;
  String get sourceLabel => isImported ? 'Imported' : 'In-app';

  String get priceLabel {
    final amount = sellingPrice.toStringAsFixed(
      sellingPrice == sellingPrice.roundToDouble() ? 0 : 2,
    );
    return unit == null || unit!.trim().isEmpty
        ? '₹$amount'
        : '₹$amount / ${unit!.trim()}';
  }

  String get quantityLabel {
    final amount = quantity.toStringAsFixed(
      quantity == quantity.roundToDouble() ? 0 : 2,
    );
    return unit == null || unit!.trim().isEmpty
        ? amount
        : '$amount ${unit!.trim()}';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'uuid': uuid,
    'shop_id': shopId,
    'product_code': productCode,
    'barcode': barcode,
    'name': name,
    'hsn_code': hsnCode,
    'hsn_type': hsnType,
    'hsn_description': hsnDescription,
    'category_id': categoryId,
    'supplier_id': supplierId,
    'selling_price': sellingPrice,
    'purchase_price': purchasePrice,
    'gst_percent': gstPercent,
    'overhead_cost': overheadCost,
    'profit_margin_percent': profitMarginPercent,
    'direct_price_toggle': directPriceToggle ? 1 : 0,
    'manual_price': manualPrice,
    'quantity_cache': quantity,
    'unit_id': unitId,
    'source': source,
    'device_id': deviceId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
    id: map['id'] as int?,
    uuid: map['uuid'] as String? ?? '',
    shopId: map['shop_id'] as String? ?? '',
    productCode: map['product_code'] as String? ?? map['item_code'] as String?,
    barcode: map['barcode'] as String?,
    name: map['name'] as String,
    hsnCode: map['hsn_code'] as String?,
    hsnType: map['hsn_type'] as String?,
    hsnDescription: map['hsn_description'] as String?,
    categoryId: map['category_id'] as int?,
    category: _cleanOptional(
      map['category_name'] as String? ?? map['category'] as String?,
    ),
    supplierId: map['supplier_id'] as int?,
    supplier: _cleanOptional(
      map['supplier_name'] as String? ?? map['supplier'] as String?,
    ),
    sellingPrice:
        (map['selling_price'] as num?)?.toDouble() ??
        (map['mrp'] as num?)?.toDouble() ??
        0,
    purchasePrice:
        (map['purchase_price'] as num?)?.toDouble() ??
        (map['selling_price'] as num?)?.toDouble() ??
        (map['mrp'] as num?)?.toDouble() ??
        0,
    gstPercent: (map['gst_percent'] as num?)?.toDouble(),
    overheadCost: (map['overhead_cost'] as num?)?.toDouble(),
    profitMarginPercent: (map['profit_margin_percent'] as num?)?.toDouble(),
    directPriceToggle: (map['direct_price_toggle'] as int? ?? 0) == 1,
    manualPrice: (map['manual_price'] as num?)?.toDouble(),
    quantity:
        (map['quantity_cache'] as num?)?.toDouble() ??
        (map['quantity'] as num?)?.toDouble() ??
        0,
    unitId: map['unit_id'] as int?,
    unit: _cleanOptional(map['unit_name'] as String? ?? map['unit'] as String?),
    source: map['source'] as String? ?? ProductSource.mobile,
    deviceId: map['device_id'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    updatedAt:
        DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
        DateTime.parse(map['created_at'] as String),
    deletedAt: map['deleted_at'] == null
        ? null
        : DateTime.tryParse(map['deleted_at'] as String),
  );

  Product copyWith({
    int? id,
    String? uuid,
    String? shopId,
    bool clearItemCode = false,
    String? itemCode,
    String? productCode,
    bool clearBarcode = false,
    String? barcode,
    String? name,
    bool clearHsnCode = false,
    String? hsnCode,
    bool clearHsnType = false,
    String? hsnType,
    bool clearHsnDescription = false,
    String? hsnDescription,
    bool clearCategory = false,
    int? categoryId,
    String? category,
    bool clearSupplier = false,
    int? supplierId,
    String? supplier,
    double? mrp,
    double? sellingPrice,
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
    num? quantity,
    bool clearUnit = false,
    int? unitId,
    String? unit,
    String? source,
    String? deviceId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) => Product(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    shopId: shopId ?? this.shopId,
    productCode: clearItemCode
        ? null
        : productCode ?? itemCode ?? this.productCode,
    barcode: clearBarcode ? null : barcode ?? this.barcode,
    name: name ?? this.name,
    hsnCode: clearHsnCode ? null : hsnCode ?? this.hsnCode,
    hsnType: clearHsnType ? null : hsnType ?? this.hsnType,
    hsnDescription: clearHsnDescription
        ? null
        : hsnDescription ?? this.hsnDescription,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    category: clearCategory ? null : category ?? this.category,
    supplierId: clearSupplier ? null : supplierId ?? this.supplierId,
    supplier: clearSupplier ? null : supplier ?? this.supplier,
    sellingPrice: sellingPrice ?? mrp ?? this.sellingPrice,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    gstPercent: clearGstPercent ? null : gstPercent ?? this.gstPercent,
    overheadCost: clearOverheadCost ? null : overheadCost ?? this.overheadCost,
    profitMarginPercent: clearProfitMarginPercent
        ? null
        : profitMarginPercent ?? this.profitMarginPercent,
    directPriceToggle: directPriceToggle ?? this.directPriceToggle,
    manualPrice: clearManualPrice ? null : manualPrice ?? this.manualPrice,
    quantity: quantity ?? this.quantity,
    unitId: clearUnit ? null : unitId ?? this.unitId,
    unit: clearUnit ? null : unit ?? this.unit,
    source: source ?? this.source,
    deviceId: deviceId ?? this.deviceId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
  );

  String toQrData() {
    final map = <String, dynamic>{
      'uuid': uuid,
      'name': name,
      'mrp': sellingPrice,
      'qty': quantity,
    };
    if (id != null) map['id'] = id;
    final unitValue = unit?.trim();
    if (unitValue != null && unitValue.isNotEmpty) map['unit'] = unitValue;
    if (productCode != null) map['code'] = productCode;
    if (barcode != null) map['barcode'] = barcode;
    if (hsnCode != null) map['hsn'] = hsnCode;
    if (category != null) map['cat'] = category;
    return jsonEncode(map);
  }

  static String? _cleanOptional(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String? _cleanHsnCode(String? value) {
    final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
    return digits == null || digits.isEmpty ? null : digits;
  }
}
