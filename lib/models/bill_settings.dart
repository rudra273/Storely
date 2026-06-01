class BillSettings {
  static const defaultInvoiceTitle = 'TAX INVOICE';
  static const defaultFooterText = 'Thank you for your business.';

  final int? id;
  final String uuid;
  final String shopId;
  final String invoiceTitle;
  final String footerText;
  final bool showShopLogo;
  final String? shopLogoBase64;
  final bool showDigitalSignature;
  final String? digitalSignatureBase64;
  final bool showShopAddress;
  final bool showShopPhone;
  final bool showShopEmail;
  final bool showShopGstin;
  final bool showCustomerPhone;
  final bool showCustomerAddress;
  final bool showPaymentDetails;
  final bool showGstBreakdown;
  final bool showHsnColumn;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  BillSettings({
    this.id,
    this.uuid = '',
    this.shopId = '',
    this.invoiceTitle = defaultInvoiceTitle,
    this.footerText = defaultFooterText,
    this.showShopLogo = true,
    this.shopLogoBase64,
    this.showDigitalSignature = false,
    this.digitalSignatureBase64,
    this.showShopAddress = true,
    this.showShopPhone = true,
    this.showShopEmail = true,
    this.showShopGstin = true,
    this.showCustomerPhone = true,
    this.showCustomerAddress = true,
    this.showPaymentDetails = true,
    this.showGstBreakdown = true,
    this.showHsnColumn = true,
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
      showShopLogo: _flag(map['show_shop_logo'], fallback: true),
      shopLogoBase64: _cleanText(map['shop_logo_base64']?.toString()),
      showDigitalSignature: _flag(map['show_digital_signature']),
      digitalSignatureBase64: _cleanText(
        map['digital_signature_base64']?.toString(),
      ),
      showShopAddress: _flag(map['show_shop_address'], fallback: true),
      showShopPhone: _flag(map['show_shop_phone'], fallback: true),
      showShopEmail: _flag(map['show_shop_email'], fallback: true),
      showShopGstin: _flag(map['show_shop_gstin'], fallback: true),
      showCustomerPhone: _flag(map['show_customer_phone'], fallback: true),
      showCustomerAddress: _flag(map['show_customer_address'], fallback: true),
      showPaymentDetails: _flag(map['show_payment_details'], fallback: true),
      showGstBreakdown: _flag(map['show_gst_breakdown'], fallback: true),
      showHsnColumn: _flag(map['show_hsn_column'], fallback: true),
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
    'show_shop_logo': showShopLogo ? 1 : 0,
    'shop_logo_base64': _cleanText(shopLogoBase64),
    'show_digital_signature': showDigitalSignature ? 1 : 0,
    'digital_signature_base64': _cleanText(digitalSignatureBase64),
    'show_shop_address': showShopAddress ? 1 : 0,
    'show_shop_phone': showShopPhone ? 1 : 0,
    'show_shop_email': showShopEmail ? 1 : 0,
    'show_shop_gstin': showShopGstin ? 1 : 0,
    'show_customer_phone': showCustomerPhone ? 1 : 0,
    'show_customer_address': showCustomerAddress ? 1 : 0,
    'show_payment_details': showPaymentDetails ? 1 : 0,
    'show_gst_breakdown': showGstBreakdown ? 1 : 0,
    'show_hsn_column': showHsnColumn ? 1 : 0,
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
    bool? showShopLogo,
    String? shopLogoBase64,
    bool clearShopLogo = false,
    bool? showDigitalSignature,
    String? digitalSignatureBase64,
    bool clearDigitalSignature = false,
    bool? showShopAddress,
    bool? showShopPhone,
    bool? showShopEmail,
    bool? showShopGstin,
    bool? showCustomerPhone,
    bool? showCustomerAddress,
    bool? showPaymentDetails,
    bool? showGstBreakdown,
    bool? showHsnColumn,
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
      showShopLogo: showShopLogo ?? this.showShopLogo,
      shopLogoBase64: clearShopLogo
          ? null
          : shopLogoBase64 ?? this.shopLogoBase64,
      showDigitalSignature: showDigitalSignature ?? this.showDigitalSignature,
      digitalSignatureBase64: clearDigitalSignature
          ? null
          : digitalSignatureBase64 ?? this.digitalSignatureBase64,
      showShopAddress: showShopAddress ?? this.showShopAddress,
      showShopPhone: showShopPhone ?? this.showShopPhone,
      showShopEmail: showShopEmail ?? this.showShopEmail,
      showShopGstin: showShopGstin ?? this.showShopGstin,
      showCustomerPhone: showCustomerPhone ?? this.showCustomerPhone,
      showCustomerAddress: showCustomerAddress ?? this.showCustomerAddress,
      showPaymentDetails: showPaymentDetails ?? this.showPaymentDetails,
      showGstBreakdown: showGstBreakdown ?? this.showGstBreakdown,
      showHsnColumn: showHsnColumn ?? this.showHsnColumn,
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
