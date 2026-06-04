class BillSettings {
  static const defaultInvoiceTitle = 'TAX INVOICE';
  static const defaultFooterText = 'Thank you for your business.';

  final int? id;
  final String uuid;
  final String shopId;
  final String invoiceTitle;
  final String footerText;
  final bool showInvoiceTitle;
  final bool showShopLogo;
  final String? shopLogoBase64;
  final bool showDigitalSignature;
  final String? digitalSignatureBase64;
  final bool showShopName;
  final bool showShopAddress;
  final bool showShopPhone;
  final bool showShopEmail;
  final bool showShopGstin;
  final bool showCustomerName;
  final bool showCustomerPhone;
  final bool showCustomerAddress;
  final bool showCustomerGstin;
  final bool showCustomerLegalName;
  final bool showCustomerTradeName;
  final bool showCustomerPlaceOfSupply;
  final bool showInvoiceNumber;
  final bool showInvoiceDate;
  final bool showInvoicePlaceOfSupply;
  final bool showInvoiceSupplyType;
  final bool showPaymentDetails;
  final bool showGstBreakdown;
  final bool showItemSerialColumn;
  final bool showItemNameColumn;
  final bool showHsnColumn;
  final bool showQuantityColumn;
  final bool showRateColumn;
  final bool showGstPercentColumn;
  final bool showGstAmountColumn;
  final bool showAmountColumn;
  final bool showSubtotal;
  final bool showDiscount;
  final bool showTaxableAmount;
  final bool showCgstSgstIgst;
  final bool showGstTotal;
  final bool showGrandTotal;
  final bool showFooterText;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  BillSettings({
    this.id,
    this.uuid = '',
    this.shopId = '',
    this.invoiceTitle = defaultInvoiceTitle,
    this.footerText = defaultFooterText,
    this.showInvoiceTitle = true,
    this.showShopLogo = true,
    this.shopLogoBase64,
    this.showDigitalSignature = false,
    this.digitalSignatureBase64,
    this.showShopName = true,
    this.showShopAddress = true,
    this.showShopPhone = true,
    this.showShopEmail = true,
    this.showShopGstin = true,
    this.showCustomerName = true,
    this.showCustomerPhone = true,
    this.showCustomerAddress = true,
    this.showCustomerGstin = true,
    this.showCustomerLegalName = true,
    this.showCustomerTradeName = true,
    this.showCustomerPlaceOfSupply = true,
    this.showInvoiceNumber = true,
    this.showInvoiceDate = true,
    this.showInvoicePlaceOfSupply = true,
    this.showInvoiceSupplyType = true,
    this.showPaymentDetails = true,
    this.showGstBreakdown = true,
    this.showItemSerialColumn = true,
    this.showItemNameColumn = true,
    this.showHsnColumn = true,
    this.showQuantityColumn = true,
    this.showRateColumn = true,
    this.showGstPercentColumn = true,
    this.showGstAmountColumn = true,
    this.showAmountColumn = true,
    this.showSubtotal = true,
    this.showDiscount = true,
    this.showTaxableAmount = true,
    this.showCgstSgstIgst = true,
    this.showGstTotal = true,
    this.showGrandTotal = true,
    this.showFooterText = true,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
       updatedAt =
           updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory BillSettings.fromMap(Map<String, dynamic> map) {
    return BillSettings(
      id: map['id'] as int?,
      uuid: map['uuid'] as String? ?? '',
      shopId: map['shop_id'] as String? ?? '',
      invoiceTitle:
          _cleanText(map['invoice_title']?.toString()) ?? defaultInvoiceTitle,
      footerText:
          _cleanText(map['footer_text']?.toString()) ?? defaultFooterText,
      showInvoiceTitle: _flag(map['show_invoice_title'], fallback: true),
      showShopLogo: _flag(map['show_shop_logo'], fallback: true),
      shopLogoBase64: _cleanText(map['shop_logo_base64']?.toString()),
      showDigitalSignature: _flag(map['show_digital_signature']),
      digitalSignatureBase64: _cleanText(
        map['digital_signature_base64']?.toString(),
      ),
      showShopName: _flag(map['show_shop_name'], fallback: true),
      showShopAddress: _flag(map['show_shop_address'], fallback: true),
      showShopPhone: _flag(map['show_shop_phone'], fallback: true),
      showShopEmail: _flag(map['show_shop_email'], fallback: true),
      showShopGstin: _flag(map['show_shop_gstin'], fallback: true),
      showCustomerName: _flag(map['show_customer_name'], fallback: true),
      showCustomerPhone: _flag(map['show_customer_phone'], fallback: true),
      showCustomerAddress: _flag(map['show_customer_address'], fallback: true),
      showCustomerGstin: _flag(map['show_customer_gstin'], fallback: true),
      showCustomerLegalName: _flag(
        map['show_customer_legal_name'],
        fallback: true,
      ),
      showCustomerTradeName: _flag(
        map['show_customer_trade_name'],
        fallback: true,
      ),
      showCustomerPlaceOfSupply: _flag(
        map['show_customer_place_of_supply'],
        fallback: true,
      ),
      showInvoiceNumber: _flag(map['show_invoice_number'], fallback: true),
      showInvoiceDate: _flag(map['show_invoice_date'], fallback: true),
      showInvoicePlaceOfSupply: _flag(
        map['show_invoice_place_of_supply'],
        fallback: true,
      ),
      showInvoiceSupplyType: _flag(
        map['show_invoice_supply_type'],
        fallback: true,
      ),
      showPaymentDetails: _flag(map['show_payment_details'], fallback: true),
      showGstBreakdown: _flag(map['show_gst_breakdown'], fallback: true),
      showItemSerialColumn: _flag(
        map['show_item_serial_column'],
        fallback: true,
      ),
      showItemNameColumn: _flag(map['show_item_name_column'], fallback: true),
      showHsnColumn: _flag(map['show_hsn_column'], fallback: true),
      showQuantityColumn: _flag(map['show_quantity_column'], fallback: true),
      showRateColumn: _flag(map['show_rate_column'], fallback: true),
      showGstPercentColumn: _flag(
        map['show_gst_percent_column'],
        fallback: true,
      ),
      showGstAmountColumn: _flag(map['show_gst_amount_column'], fallback: true),
      showAmountColumn: _flag(map['show_amount_column'], fallback: true),
      showSubtotal: _flag(map['show_subtotal'], fallback: true),
      showDiscount: _flag(map['show_discount'], fallback: true),
      showTaxableAmount: _flag(map['show_taxable_amount'], fallback: true),
      showCgstSgstIgst: _flag(map['show_cgst_sgst_igst'], fallback: true),
      showGstTotal: _flag(map['show_gst_total'], fallback: true),
      showGrandTotal: _flag(map['show_grand_total'], fallback: true),
      showFooterText: _flag(map['show_footer_text'], fallback: true),
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse(map['deleted_at'].toString()),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'uuid': uuid,
    'shop_id': shopId,
    'invoice_title': invoiceTitle.trim().isEmpty
        ? defaultInvoiceTitle
        : invoiceTitle.trim(),
    'footer_text': footerText.trim(),
    'show_invoice_title': showInvoiceTitle ? 1 : 0,
    'show_shop_logo': showShopLogo ? 1 : 0,
    'shop_logo_base64': _cleanText(shopLogoBase64),
    'show_digital_signature': showDigitalSignature ? 1 : 0,
    'digital_signature_base64': _cleanText(digitalSignatureBase64),
    'show_shop_name': showShopName ? 1 : 0,
    'show_shop_address': showShopAddress ? 1 : 0,
    'show_shop_phone': showShopPhone ? 1 : 0,
    'show_shop_email': showShopEmail ? 1 : 0,
    'show_shop_gstin': showShopGstin ? 1 : 0,
    'show_customer_name': showCustomerName ? 1 : 0,
    'show_customer_phone': showCustomerPhone ? 1 : 0,
    'show_customer_address': showCustomerAddress ? 1 : 0,
    'show_customer_gstin': showCustomerGstin ? 1 : 0,
    'show_customer_legal_name': showCustomerLegalName ? 1 : 0,
    'show_customer_trade_name': showCustomerTradeName ? 1 : 0,
    'show_customer_place_of_supply': showCustomerPlaceOfSupply ? 1 : 0,
    'show_invoice_number': showInvoiceNumber ? 1 : 0,
    'show_invoice_date': showInvoiceDate ? 1 : 0,
    'show_invoice_place_of_supply': showInvoicePlaceOfSupply ? 1 : 0,
    'show_invoice_supply_type': showInvoiceSupplyType ? 1 : 0,
    'show_payment_details': showPaymentDetails ? 1 : 0,
    'show_gst_breakdown': showGstBreakdown ? 1 : 0,
    'show_item_serial_column': showItemSerialColumn ? 1 : 0,
    'show_item_name_column': showItemNameColumn ? 1 : 0,
    'show_hsn_column': showHsnColumn ? 1 : 0,
    'show_quantity_column': showQuantityColumn ? 1 : 0,
    'show_rate_column': showRateColumn ? 1 : 0,
    'show_gst_percent_column': showGstPercentColumn ? 1 : 0,
    'show_gst_amount_column': showGstAmountColumn ? 1 : 0,
    'show_amount_column': showAmountColumn ? 1 : 0,
    'show_subtotal': showSubtotal ? 1 : 0,
    'show_discount': showDiscount ? 1 : 0,
    'show_taxable_amount': showTaxableAmount ? 1 : 0,
    'show_cgst_sgst_igst': showCgstSgstIgst ? 1 : 0,
    'show_gst_total': showGstTotal ? 1 : 0,
    'show_grand_total': showGrandTotal ? 1 : 0,
    'show_footer_text': showFooterText ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  BillSettings copyWith({
    int? id,
    String? uuid,
    String? shopId,
    String? invoiceTitle,
    String? footerText,
    bool? showInvoiceTitle,
    bool? showShopLogo,
    String? shopLogoBase64,
    bool clearShopLogo = false,
    bool? showDigitalSignature,
    String? digitalSignatureBase64,
    bool clearDigitalSignature = false,
    bool? showShopName,
    bool? showShopAddress,
    bool? showShopPhone,
    bool? showShopEmail,
    bool? showShopGstin,
    bool? showCustomerName,
    bool? showCustomerPhone,
    bool? showCustomerAddress,
    bool? showCustomerGstin,
    bool? showCustomerLegalName,
    bool? showCustomerTradeName,
    bool? showCustomerPlaceOfSupply,
    bool? showInvoiceNumber,
    bool? showInvoiceDate,
    bool? showInvoicePlaceOfSupply,
    bool? showInvoiceSupplyType,
    bool? showPaymentDetails,
    bool? showGstBreakdown,
    bool? showItemSerialColumn,
    bool? showItemNameColumn,
    bool? showHsnColumn,
    bool? showQuantityColumn,
    bool? showRateColumn,
    bool? showGstPercentColumn,
    bool? showGstAmountColumn,
    bool? showAmountColumn,
    bool? showSubtotal,
    bool? showDiscount,
    bool? showTaxableAmount,
    bool? showCgstSgstIgst,
    bool? showGstTotal,
    bool? showGrandTotal,
    bool? showFooterText,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return BillSettings(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      shopId: shopId ?? this.shopId,
      invoiceTitle: invoiceTitle ?? this.invoiceTitle,
      footerText: footerText ?? this.footerText,
      showInvoiceTitle: showInvoiceTitle ?? this.showInvoiceTitle,
      showShopLogo: showShopLogo ?? this.showShopLogo,
      shopLogoBase64: clearShopLogo
          ? null
          : shopLogoBase64 ?? this.shopLogoBase64,
      showDigitalSignature: showDigitalSignature ?? this.showDigitalSignature,
      digitalSignatureBase64: clearDigitalSignature
          ? null
          : digitalSignatureBase64 ?? this.digitalSignatureBase64,
      showShopName: showShopName ?? this.showShopName,
      showShopAddress: showShopAddress ?? this.showShopAddress,
      showShopPhone: showShopPhone ?? this.showShopPhone,
      showShopEmail: showShopEmail ?? this.showShopEmail,
      showShopGstin: showShopGstin ?? this.showShopGstin,
      showCustomerName: showCustomerName ?? this.showCustomerName,
      showCustomerPhone: showCustomerPhone ?? this.showCustomerPhone,
      showCustomerAddress: showCustomerAddress ?? this.showCustomerAddress,
      showCustomerGstin: showCustomerGstin ?? this.showCustomerGstin,
      showCustomerLegalName:
          showCustomerLegalName ?? this.showCustomerLegalName,
      showCustomerTradeName:
          showCustomerTradeName ?? this.showCustomerTradeName,
      showCustomerPlaceOfSupply:
          showCustomerPlaceOfSupply ?? this.showCustomerPlaceOfSupply,
      showInvoiceNumber: showInvoiceNumber ?? this.showInvoiceNumber,
      showInvoiceDate: showInvoiceDate ?? this.showInvoiceDate,
      showInvoicePlaceOfSupply:
          showInvoicePlaceOfSupply ?? this.showInvoicePlaceOfSupply,
      showInvoiceSupplyType:
          showInvoiceSupplyType ?? this.showInvoiceSupplyType,
      showPaymentDetails: showPaymentDetails ?? this.showPaymentDetails,
      showGstBreakdown: showGstBreakdown ?? this.showGstBreakdown,
      showItemSerialColumn: showItemSerialColumn ?? this.showItemSerialColumn,
      showItemNameColumn: showItemNameColumn ?? this.showItemNameColumn,
      showHsnColumn: showHsnColumn ?? this.showHsnColumn,
      showQuantityColumn: showQuantityColumn ?? this.showQuantityColumn,
      showRateColumn: showRateColumn ?? this.showRateColumn,
      showGstPercentColumn: showGstPercentColumn ?? this.showGstPercentColumn,
      showGstAmountColumn: showGstAmountColumn ?? this.showGstAmountColumn,
      showAmountColumn: showAmountColumn ?? this.showAmountColumn,
      showSubtotal: showSubtotal ?? this.showSubtotal,
      showDiscount: showDiscount ?? this.showDiscount,
      showTaxableAmount: showTaxableAmount ?? this.showTaxableAmount,
      showCgstSgstIgst: showCgstSgstIgst ?? this.showCgstSgstIgst,
      showGstTotal: showGstTotal ?? this.showGstTotal,
      showGrandTotal: showGrandTotal ?? this.showGrandTotal,
      showFooterText: showFooterText ?? this.showFooterText,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

class InvoiceSeriesSettings {
  final int? id;
  final String uuid;
  final String name;
  final String formatTemplate;
  final int sequencePadding;
  final String resetPeriod;
  final int nextSequence;

  const InvoiceSeriesSettings({
    this.id,
    this.uuid = '',
    this.name = 'Default',
    this.formatTemplate = 'INV-{YYYY}{MM}{DD}-{SEQ}',
    this.sequencePadding = 4,
    this.resetPeriod = 'daily',
    this.nextSequence = 1,
  });

  factory InvoiceSeriesSettings.fromMap(Map<String, dynamic> map) {
    return InvoiceSeriesSettings(
      id: map['id'] as int?,
      uuid: map['uuid'] as String? ?? '',
      name: _cleanText(map['name']?.toString()) ?? 'Default',
      formatTemplate:
          _cleanText(map['format_template']?.toString()) ??
          'INV-{YYYY}{MM}{DD}-{SEQ}',
      sequencePadding: ((map['sequence_padding'] as num?)?.toInt() ?? 4).clamp(
        1,
        8,
      ),
      resetPeriod: _cleanResetPeriod(map['reset_period']),
      nextSequence: ((map['next_sequence'] as num?)?.toInt() ?? 1).clamp(
        1,
        999999999,
      ),
    );
  }

  InvoiceSeriesSettings copyWith({
    String? name,
    String? formatTemplate,
    int? sequencePadding,
    String? resetPeriod,
    int? nextSequence,
  }) {
    return InvoiceSeriesSettings(
      id: id,
      uuid: uuid,
      name: name ?? this.name,
      formatTemplate: formatTemplate ?? this.formatTemplate,
      sequencePadding: sequencePadding ?? this.sequencePadding,
      resetPeriod: resetPeriod ?? this.resetPeriod,
      nextSequence: nextSequence ?? this.nextSequence,
    );
  }
}

bool _flag(Object? value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value.toString() == '1' || value.toString().toLowerCase() == 'true';
}

String? _cleanText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String _cleanResetPeriod(Object? value) {
  const allowed = {'daily', 'monthly', 'financial_year', 'never'};
  final text = value?.toString();
  return allowed.contains(text) ? text! : 'daily';
}

DateTime _date(Object? value) {
  return DateTime.tryParse(value?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
}
