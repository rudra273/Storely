part of '../bills_screen.dart';

String _paymentMethodLabel(String method) => paymentMethodLabel(method);

String _billDisplayId(Bill bill) {
  if (bill.billNumber.isEmpty) return 'Bill #${bill.id}';
  return bill.billNumber.replaceFirst(RegExp(r'^SHOP-LOCAL-local-'), 'INV-');
}
