part of '../scan_screen.dart';

String _formatQuantityInput(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _BillDraft {
  final String customerName;
  final String? customerPhone;
  final String billType;
  final String? customerGstin;
  final String? customerGstLegalName;
  final String? customerGstTradeName;
  final String? customerAddress;
  final String? placeOfSupplyStateCode;
  final double discountPercent;
  final String discountMode;
  final double discountValue;
  final String taxMode;
  final String roundOffMode;
  final double roundOffIncrement;
  final double paidAmount;
  final String paymentMethod;
  final String? transactionReference;
  final DateTime? billDate;
  final String? notes;

  Map<String, dynamic> toMap() => {
    'customerName': customerName,
    'customerPhone': customerPhone,
    'billType': billType,
    'customerGstin': customerGstin,
    'customerGstLegalName': customerGstLegalName,
    'customerGstTradeName': customerGstTradeName,
    'customerAddress': customerAddress,
    'placeOfSupplyStateCode': placeOfSupplyStateCode,
    'discountPercent': discountPercent,
    'discountMode': discountMode,
    'discountValue': discountValue,
    'taxMode': taxMode,
    'roundOffMode': roundOffMode,
    'roundOffIncrement': roundOffIncrement,
    'paidAmount': paidAmount,
    'paymentMethod': paymentMethod,
    'transactionReference': transactionReference,
    'billDate': billDate?.toIso8601String(),
    'notes': notes,
  };
  factory _BillDraft.fromMap(Map<String, dynamic> map) {
    final discountPercent = (map['discountPercent'] as num?)?.toDouble() ?? 0;
    final discountMode = map['discountMode'] == Bill.discountModeAmount
        ? Bill.discountModeAmount
        : Bill.discountModePercent;
    return _BillDraft(
      customerName: map['customerName'] as String,
      customerPhone: map['customerPhone'] as String?,
      billType: map['billType'] as String,
      customerGstin: map['customerGstin'] as String?,
      customerGstLegalName: map['customerGstLegalName'] as String?,
      customerGstTradeName: map['customerGstTradeName'] as String?,
      customerAddress: map['customerAddress'] as String?,
      placeOfSupplyStateCode: map['placeOfSupplyStateCode'] as String?,
      discountPercent: discountPercent,
      discountMode: discountMode,
      discountValue:
          (map['discountValue'] as num?)?.toDouble() ??
          (discountMode == Bill.discountModePercent ? discountPercent : 0),
      taxMode: map['taxMode'] == Bill.taxModeExclusive
          ? Bill.taxModeExclusive
          : Bill.taxModeInclusive,
      roundOffMode:
          const {
            Bill.roundOffNone,
            Bill.roundOffNearest,
            Bill.roundOffUp,
            Bill.roundOffDown,
          }.contains(map['roundOffMode'])
          ? map['roundOffMode'] as String
          : Bill.roundOffNearest,
      roundOffIncrement: (map['roundOffIncrement'] as num?)?.toDouble() ?? 1.0,
      paidAmount: (map['paidAmount'] as num).toDouble(),
      paymentMethod: map['paymentMethod'] as String,
      transactionReference: map['transactionReference'] as String?,
      billDate: map['billDate'] is String
          ? DateTime.tryParse(map['billDate'] as String)
          : null,
      notes: map['notes'] as String?,
    );
  }

  const _BillDraft({
    required this.customerName,
    required this.customerPhone,
    required this.billType,
    required this.customerGstin,
    required this.customerGstLegalName,
    required this.customerGstTradeName,
    required this.customerAddress,
    required this.placeOfSupplyStateCode,
    required this.discountPercent,
    this.discountMode = Bill.discountModePercent,
    this.discountValue = 0,
    this.taxMode = Bill.taxModeInclusive,
    this.roundOffMode = Bill.roundOffNearest,
    this.roundOffIncrement = 1.0,
    required this.paidAmount,
    required this.paymentMethod,
    this.transactionReference,
    this.billDate,
    this.notes,
  });
}
