part of '../bills_screen.dart';

String _paymentStatusLabel(String status) => switch (status) {
  Bill.statusPaid => 'Paid',
  Bill.statusPartial => 'Partial',
  _ => 'Unpaid',
};

String _paymentMethodLabel(String method) => switch (method) {
  'cash' => 'Cash',
  'upi' => 'UPI',
  'card' => 'Card',
  'bank' => 'Bank transfer',
  'online' => 'Online',
  _ => method.isEmpty ? 'Cash' : method,
};

String _billDisplayId(Bill bill) {
  if (bill.billNumber.isEmpty) return 'Bill #${bill.id}';
  return bill.billNumber.replaceFirst(RegExp(r'^SHOP-LOCAL-local-'), 'INV-');
}
