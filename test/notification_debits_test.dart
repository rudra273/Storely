import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/screens/notifications_screen.dart';

void main() {
  test('customer debit rows use remaining balance for partial bills', () {
    final rows = buildCustomerDebitRows([
      Bill(
        customerName: 'Asha',
        customerPhone: '9123456789',
        totalAmount: 1000,
        itemCount: 1,
        isPaid: false,
        paidAmount: 400,
      ),
      Bill(
        customerName: 'Asha',
        customerPhone: '9123456789',
        totalAmount: 50,
        itemCount: 1,
        isPaid: false,
      ),
    ]);

    expect(rows, hasLength(1));
    expect(rows.single['name'], 'Asha');
    expect(rows.single['amount'], 650);
  });
}
