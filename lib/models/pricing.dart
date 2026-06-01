import 'product.dart';

class GlobalPricingSettings {
  final double defaultGstPercent;
  final double defaultOverheadCost;
  final double defaultProfitMarginPercent;
  final bool gstRegistered;
  final bool showPurchasePriceGlobally;

  const GlobalPricingSettings({
    this.defaultGstPercent = 18,
    this.defaultOverheadCost = 0,
    this.defaultProfitMarginPercent = 0,
    this.gstRegistered = false,
    this.showPurchasePriceGlobally = false,
  });

  GlobalPricingSettings copyWith({
    double? defaultGstPercent,
    double? defaultOverheadCost,
    double? defaultProfitMarginPercent,
    bool? gstRegistered,
    bool? showPurchasePriceGlobally,
  }) {
    return GlobalPricingSettings(
      defaultGstPercent: defaultGstPercent ?? this.defaultGstPercent,
      defaultOverheadCost: defaultOverheadCost ?? this.defaultOverheadCost,
      defaultProfitMarginPercent:
          defaultProfitMarginPercent ?? this.defaultProfitMarginPercent,
      gstRegistered: gstRegistered ?? this.gstRegistered,
      showPurchasePriceGlobally:
          showPurchasePriceGlobally ?? this.showPurchasePriceGlobally,
    );
  }
}

class CategoryPricingSettings {
  final int? id;
  final String name;
  final double? gstPercent;
  final double? overheadCost;
  final double? profitMarginPercent;
  final bool directPriceToggle;
  final double? manualPrice;
  final String? hsnCode;
  final String? hsnType;
  final String? hsnDescription;

  const CategoryPricingSettings({
    this.id,
    required this.name,
    this.gstPercent,
    this.overheadCost,
    this.profitMarginPercent,
    this.directPriceToggle = false,
    this.manualPrice,
    this.hsnCode,
    this.hsnType,
    this.hsnDescription,
  });

  factory CategoryPricingSettings.fromMap(Map<String, dynamic> map) {
    return CategoryPricingSettings(
      id: map['id'] as int?,
      name: map['name'] as String,
      gstPercent: _optionalDouble(map['gst_percent']),
      overheadCost: _optionalDouble(map['overhead_cost']),
      profitMarginPercent: _optionalDouble(map['profit_margin_percent']),
      directPriceToggle: (map['direct_price_toggle'] as int? ?? 0) == 1,
      manualPrice: _optionalDouble(map['manual_price']),
      hsnCode: _cleanHsnCode(map['hsn_code']?.toString()),
      hsnType: _cleanOptional(map['hsn_type']?.toString()),
      hsnDescription: _cleanOptional(map['hsn_description']?.toString()),
    );
  }

  Map<String, dynamic> toPricingMap() => {
    'gst_percent': gstPercent,
    'overhead_cost': overheadCost,
    'profit_margin_percent': profitMarginPercent,
    'direct_price_toggle': directPriceToggle ? 1 : 0,
    'manual_price': manualPrice,
    'hsn_code': hsnCode,
    'hsn_type': hsnType,
    'hsn_description': hsnDescription,
  };

  CategoryPricingSettings copyWith({
    double? gstPercent,
    bool clearGstPercent = false,
    double? overheadCost,
    bool clearOverheadCost = false,
    double? profitMarginPercent,
    bool clearProfitMarginPercent = false,
    bool? directPriceToggle,
    double? manualPrice,
    bool clearManualPrice = false,
    String? hsnCode,
    bool clearHsnCode = false,
    String? hsnType,
    bool clearHsnType = false,
    String? hsnDescription,
    bool clearHsnDescription = false,
  }) {
    return CategoryPricingSettings(
      id: id,
      name: name,
      gstPercent: clearGstPercent ? null : gstPercent ?? this.gstPercent,
      overheadCost: clearOverheadCost
          ? null
          : overheadCost ?? this.overheadCost,
      profitMarginPercent: clearProfitMarginPercent
          ? null
          : profitMarginPercent ?? this.profitMarginPercent,
      directPriceToggle: directPriceToggle ?? this.directPriceToggle,
      manualPrice: clearManualPrice ? null : manualPrice ?? this.manualPrice,
      hsnCode: clearHsnCode ? null : hsnCode ?? this.hsnCode,
      hsnType: clearHsnType ? null : hsnType ?? this.hsnType,
      hsnDescription: clearHsnDescription
          ? null
          : hsnDescription ?? this.hsnDescription,
    );
  }
}

class PriceBreakdown {
  final int? productId;
  final String productName;
  final String? unit;
  final double purchasePrice;
  final double gstPercent;
  final double overheadCost;
  final double profitMarginPercent;
  final bool gstRegistered;
  final bool wasDirectPrice;
  final String priceSource;
  final double landedCost;
  final double totalCost;
  final double profitAmount;
  final double inputTaxAmount;
  final double outputGstAmount;
  final double gstAmount;
  final double preGstSellingPrice;
  final double sellingPrice;
  final double yourNet;

  const PriceBreakdown({
    this.productId,
    required this.productName,
    this.unit,
    required this.purchasePrice,
    required this.gstPercent,
    required this.overheadCost,
    required this.profitMarginPercent,
    required this.gstRegistered,
    required this.wasDirectPrice,
    required this.priceSource,
    required this.landedCost,
    required this.totalCost,
    required this.profitAmount,
    required this.inputTaxAmount,
    required this.outputGstAmount,
    required this.gstAmount,
    required this.preGstSellingPrice,
    required this.sellingPrice,
    required this.yourNet,
  });
}

class PricingCalculator {
  const PricingCalculator._();

  static PriceBreakdown resolveProductPrice(
    Product product,
    GlobalPricingSettings global,
    CategoryPricingSettings? category,
  ) {
    final purchasePrice = product.purchasePrice;
    final gstPercent =
        product.gstPercent ?? category?.gstPercent ?? global.defaultGstPercent;
    final overheadCost =
        product.overheadCost ??
        category?.overheadCost ??
        global.defaultOverheadCost;
    final marginPercent =
        product.profitMarginPercent ??
        category?.profitMarginPercent ??
        global.defaultProfitMarginPercent;
    final gstRegistered = global.gstRegistered;
    final purchaseGst = gstRegistered ? 0.0 : purchasePrice * gstPercent / 100;
    final landedCost = purchasePrice + purchaseGst;
    final totalCost = landedCost + overheadCost;
    final formulaProfit = totalCost * marginPercent / 100;
    final formulaPreGstSellingPrice = totalCost + formulaProfit;
    final formulaSellGst = gstRegistered
        ? formulaPreGstSellingPrice * gstPercent / 100
        : 0.0;
    final formulaSellingPrice = formulaPreGstSellingPrice + formulaSellGst;

    final productManualPrice = product.manualPrice ?? product.mrp;
    final useProductDirect = product.directPriceToggle;
    final rawSellingPrice = useProductDirect
        ? productManualPrice
        : formulaSellingPrice;
    final preGstSellingPrice = useProductDirect
        ? gstRegistered
              ? rawSellingPrice / (1 + gstPercent / 100)
              : rawSellingPrice
        : formulaPreGstSellingPrice;
    final outputGstAmount = useProductDirect
        ? gstRegistered
              ? rawSellingPrice - preGstSellingPrice
              : 0.0
        : gstRegistered
        ? formulaSellGst
        : 0.0;
    final profitAmount = preGstSellingPrice - totalCost;
    final resolvedMargin = totalCost == 0
        ? 0.0
        : profitAmount / totalCost * 100;
    return PriceBreakdown(
      productId: product.id,
      productName: product.name,
      unit: product.unit,
      purchasePrice: purchasePrice,
      gstPercent: gstPercent,
      overheadCost: overheadCost,
      profitMarginPercent: useProductDirect ? resolvedMargin : marginPercent,
      gstRegistered: gstRegistered,
      wasDirectPrice: useProductDirect,
      priceSource: useProductDirect ? 'Product direct' : 'Formula',
      landedCost: landedCost,
      totalCost: totalCost,
      profitAmount: profitAmount,
      inputTaxAmount: purchaseGst,
      outputGstAmount: outputGstAmount,
      gstAmount: outputGstAmount,
      preGstSellingPrice: preGstSellingPrice,
      sellingPrice: rawSellingPrice,
      yourNet: profitAmount,
    );
  }
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

String? _cleanOptional(String? value) {
  final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _cleanHsnCode(String? value) {
  final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
  return digits == null || digits.isEmpty ? null : digits;
}
