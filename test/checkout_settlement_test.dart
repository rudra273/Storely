import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/checkout_settlement.dart';

void main() {
  BigInt paid(
    String? status,
    String text, {
    bool customer = true,
    bool consent = false,
  }) => checkoutPaidPaise(
    settlement: status,
    partialText: text,
    totalPaise: BigInt.from(10000),
    hasCustomer: customer,
    allowUnassignedCredit: consent,
  );
  test(
    'requires explicit settlement',
    () => expect(() => paid(null, ''), throwsFormatException),
  );
  for (final value in [
    '',
    'no',
    '-1',
    '0',
    '100',
    '101',
    '.5',
    '50.000',
    '1e1',
    '+5',
    'NaN',
  ]) {
    test(
      'partial rejects $value without clamping',
      () => expect(() => paid('partial', value), throwsFormatException),
    );
  }
  test('exact partial full and unpaid amounts', () {
    expect(paid('partial', ' 50.01 '), BigInt.from(5001));
    expect(paid('paid', ''), BigInt.from(10000));
    expect(paid('unpaid', ''), BigInt.zero);
  });
  test('unassigned credit needs explicit consent', () {
    expect(() => paid('partial', '50', customer: false), throwsFormatException);
    expect(() => paid('unpaid', '', customer: false), throwsFormatException);
    expect(paid('unpaid', '', customer: false, consent: true), BigInt.zero);
    expect(paid('paid', '', customer: false), BigInt.from(10000));
  });
}
