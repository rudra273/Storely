part of '../bills_screen.dart';

String _paymentStatusLabel(String status) => switch (status) {
  Bill.statusPaid => 'Paid',
  Bill.statusPartial => 'Partial',
  _ => 'Unpaid',
};

String _paymentMethodLabel(String method) =>
    method == 'online' ? 'Online' : 'Cash';

String _billDisplayId(Bill bill) {
  if (bill.billNumber.isEmpty) return 'Bill #${bill.id}';
  return bill.billNumber.replaceFirst(RegExp(r'^SHOP-LOCAL-local-'), 'INV-');
}
