import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storely/screens/shared/record_payment_dialog.dart';
import 'package:storely/utils/test_keys.dart';
import 'package:storely/utils/money.dart';
import 'package:storely/models/checkout_settlement.dart';

void main() {
  test('large counter change keeps exact paise and Indian grouping', () {
    final change = checkoutChangePaise(
      cashText: '123456789012345678901234567890.99',
      totalPaise: BigInt.from(11800),
    )!;
    expect(
      rupeesFromPaise(change),
      '₹1,23,45,67,89,01,23,45,67,89,01,23,45,67,772.99',
    );
    expect(rupeesFromPaise(BigInt.from(1)), '₹0.01');
    expect(rupeesFromPaise(BigInt.from(-12345678)), '-₹1,23,456.78');
    expect(
      checkoutChangePaise(cashText: '1' * 31, totalPaise: BigInt.zero),
      isNull,
    );
  });
  testWidgets(
    'record payment rejects nonfinite exponent precision and malformed grouping without closing',
    (tester) async {
      PaymentEntry? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<PaymentEntry>(
                  context: context,
                  builder: (_) =>
                      const RecordPaymentDialog(balanceDue: 123456.78),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final amount = find.byKey(const ValueKey('payment-amount'));
      for (final input in [
        'NaN',
        'Infinity',
        '1e2',
        '-1',
        '0',
        '1.001',
        '1.000',
        '1,,000',
        '123456.79',
      ]) {
        await tester.enterText(amount, input);
        await tester.tap(find.bySemanticsIdentifier(TestKeys.saveBtn));
        await tester.pumpAndSettle();
        expect(result, isNull, reason: input);
        expect(find.byType(RecordPaymentDialog), findsOneWidget, reason: input);
        expect(tester.widget<TextField>(amount).controller!.text, input);
      }
      await tester.enterText(amount, '1,23,456.78');
      await tester.tap(find.bySemanticsIdentifier(TestKeys.saveBtn));
      await tester.pumpAndSettle();
      expect(result!.amount, 123456.78);
    },
  );
}
