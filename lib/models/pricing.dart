import 'product.dart';
import 'shop_profile.dart';
import 'pricing_default_input.dart';

class GlobalPricingSettings {
  final double defaultGstPercent;
  final double defaultOverheadCost;
  final double defaultProfitMarginPercent;
  final bool gstRegistered;
  final bool showPurchasePriceGlobally;
  final Map<String, String> storedDefaults;

  String get gstInput =>
      storedDefaults['default_gst_percent'] ?? defaultGstPercent.toString();
  String get overheadInput =>
      storedDefaults['default_overhead_cost'] ?? defaultOverheadCost.toString();
  String get marginInput =>
      storedDefaults['default_profit_margin_percent'] ??
      defaultProfitMarginPercent.toString();

  factory GlobalPricingSettings.fromStoredValues(Map<String, String?> values) {
    final gst = PricingDefaultNumber.parse(
      values['default_gst_percent'],
      maximum: 100,
    );
    final overhead = PricingDefaultNumber.parse(
      values['default_overhead_cost'],
      maximum: 999999999,
    );
    final margin = PricingDefaultNumber.parse(
      values['default_profit_margin_percent'],
      maximum: 100,
    );
    final scheme = GstScheme.clean(
      values['gst_scheme'],
      fallbackRegistered: values['gst_registered'] == '1',
    );
    return GlobalPricingSettings(
      defaultGstPercent: gst?.value ?? 18,
      defaultOverheadCost: overhead?.value ?? 0,
      defaultProfitMarginPercent: margin?.value ?? 0,
      gstRegistered: scheme == GstScheme.regular,
      showPurchasePriceGlobally: values['show_purchase_price_globally'] == '1',
      storedDefaults: {
        'default_gst_percent': gst?.text ?? '18',
        'default_overhead_cost': overhead?.text ?? '0',
        'default_profit_margin_percent': margin?.text ?? '0',
      },
    );
  }

  GlobalPricingSettings editedDefaults({
    required String gst,
    required String overhead,
    required String margin,
  }) {
    double edited(
      String value,
      String original,
      int maximum,
      int scale,
      String label, {
      bool gstRate = false,
    }) {
      if (value == original) {
        return PricingDefaultNumber.parse(original, maximum: maximum)!.value;
      }
      final parsed = PricingDefaultNumber.parse(value, maximum: maximum);
      if (parsed == null || parsed.scale > scale) {
        throw FormatException(
          '$label must be between 0 and $maximum with at most $scale decimal places.',
        );
      }
      if (gstRate &&
          !{
            0.0,
            0.25,
            3.0,
            5.0,
            12.0,
            18.0,
            28.0,
            40.0,
          }.contains(parsed.value)) {
        throw const FormatException(
          'Default GST % must be 0, 0.25, 3, 5, 12, 18, 28 or 40.',
        );
      }
      return parsed.value;
    }

    return GlobalPricingSettings(
      gstRegistered: gstRegistered,
      showPurchasePriceGlobally: showPurchasePriceGlobally,
      storedDefaults: {
        'default_gst_percent': gst.trim(),
        'default_overhead_cost': overhead.trim(),
        'default_profit_margin_percent': margin.trim(),
      },
      defaultGstPercent: edited(
        gst,
        gstInput,
        100,
        3,
        'Default GST %',
        gstRate: true,
      ),
      defaultOverheadCost: edited(
        overhead,
        overheadInput,
        999999999,
        2,
        'Default Overhead',
      ),
      defaultProfitMarginPercent: edited(
        margin,
        marginInput,
        100,
        3,
        'Default Profit Margin %',
      ),
    );
  }

  const GlobalPricingSettings({
    this.defaultGstPercent = 18,
    this.defaultOverheadCost = 0,
    this.defaultProfitMarginPercent = 0,
    this.gstRegistered = false,
    this.showPurchasePriceGlobally = false,
    this.storedDefaults = const {},
  });

  GlobalPricingSettings copyWith({
    double? defaultGstPercent,
    double? defaultOverheadCost,
    double? defaultProfitMarginPercent,
    bool? gstRegistered,
    bool? showPurchasePriceGlobally,
  }) {
    final inputs = Map<String, String>.of(storedDefaults);
    if (defaultGstPercent != null &&
        defaultGstPercent != this.defaultGstPercent) {
      inputs.remove('default_gst_percent');
    }
    if (defaultOverheadCost != null &&
        defaultOverheadCost != this.defaultOverheadCost) {
      inputs.remove('default_overhead_cost');
    }
    if (defaultProfitMarginPercent != null &&
        defaultProfitMarginPercent != this.defaultProfitMarginPercent) {
      inputs.remove('default_profit_margin_percent');
    }
    return GlobalPricingSettings(
      storedDefaults: inputs,
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

  /// Default [TaxType] for new items in this category (null = no default).
  final String? taxType;

  /// Default cess % for new items in this category (null = no default).
  final double? cessPercent;

  const CategoryPricingSettings({
    this.id,
    required this.name,
    this.taxType,
    this.cessPercent,
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
      taxType: TaxType.cleanOptional(map['tax_type']),
      cessPercent: _optionalDouble(map['cess_percent']),
    );
  }

  /// True when the category carries any default tax setting for new items.
  bool get hasTaxDefault =>
      taxType != null || gstPercent != null || cessPercent != null;

  Map<String, dynamic> toPricingMap() => {
    'gst_percent': gstPercent,
    'overhead_cost': overheadCost,
    'profit_margin_percent': profitMarginPercent,
    'direct_price_toggle': directPriceToggle ? 1 : 0,
    'manual_price': manualPrice,
    'hsn_code': hsnCode,
    'hsn_type': hsnType,
    'hsn_description': hsnDescription,
    'tax_type': taxType,
    'cess_percent': cessPercent,
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
    String? taxType,
    bool clearTaxType = false,
    double? cessPercent,
    bool clearCessPercent = false,
  }) {
    return CategoryPricingSettings(
      id: id,
      name: name,
      taxType: clearTaxType ? null : taxType ?? this.taxType,
      cessPercent: clearCessPercent ? null : cessPercent ?? this.cessPercent,
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
    // Exempt and non-GST items never carry GST, whatever the rate field says.
    final gstPercent = product.taxType != TaxType.taxable
        ? 0.0
        : product.gstPercent ??
              category?.gstPercent ??
              global.defaultGstPercent;
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
