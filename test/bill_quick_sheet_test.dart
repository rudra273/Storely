import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/screens/shared/bill_quick_sheet.dart';

void main() {
  testWidgets('unpaid bill sheet shows balance and follow-up actions', (
    tester,
  ) async {
    final bill = Bill(
      id: 1,
      billNumber: 'INV/2627/0002',
      customerName: 'Asha',
      customerPhone: '9876543210',
      totalAmount: 1250,
      paidAmount: 250,
      itemCount: 1,
      createdAt: DateTime.now().subtract(const Duration(days: 12)),
      items: [
        BillItem(
          productName: 'Ghee 1L',
          quantity: 1,
          sellingPriceSnapshot: 1250,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBillQuickSheet(context, bill),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(find.textContaining('12 days ago'), findsOneWidget);
    expect(find.text('Ghee 1L × 1'), findsOneWidget);
    expect(find.text('₹1,000.00'), findsOneWidget);
    expect(find.text('Record payment'), findsOneWidget);
    expect(find.text('Remind'), findsOneWidget);
    expect(find.text('Share bill'), findsOneWidget);
  });
}
