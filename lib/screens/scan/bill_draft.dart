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
