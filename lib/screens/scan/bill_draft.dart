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
  final double paidAmount;
  final String paymentMethod;
  final String? transactionReference;

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
    'paidAmount': paidAmount,
    'paymentMethod': paymentMethod,
    'transactionReference': transactionReference,
  };
  factory _BillDraft.fromMap(Map<String, dynamic> map) => _BillDraft(
    customerName: map['customerName'] as String,
    customerPhone: map['customerPhone'] as String?,
    billType: map['billType'] as String,
    customerGstin: map['customerGstin'] as String?,
    customerGstLegalName: map['customerGstLegalName'] as String?,
    customerGstTradeName: map['customerGstTradeName'] as String?,
    customerAddress: map['customerAddress'] as String?,
    placeOfSupplyStateCode: map['placeOfSupplyStateCode'] as String?,
    discountPercent: (map['discountPercent'] as num).toDouble(),
    paidAmount: (map['paidAmount'] as num).toDouble(),
    paymentMethod: map['paymentMethod'] as String,
    transactionReference: map['transactionReference'] as String?,
  );

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
    required this.paidAmount,
    required this.paymentMethod,
    this.transactionReference,
  });
}
