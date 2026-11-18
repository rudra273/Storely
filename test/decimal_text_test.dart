import 'package:flutter_test/flutter_test.dart';
import 'package:storely/utils/decimal_text.dart';

void main() {
  test('scaled decimals preserve exact value without binary conversion', () {
    final cases = [
      ('9007199254740993.01', 2, '900719925474099301', '9007199254740993.01'),
      (' -0.00 ', 2, '0', '0'),
      ('1.2300', 2, '123', '1.23'),
      ('00012.3400', 4, '123400', '12.34'),
      ('-1.0000', 0, '-1', '-1'),
      ('0.0001', 4, '1', '0.0001'),
    ];
    for (final (input, scale, scaled, canonical) in cases) {
      final result = decimalScaledInteger(input, scale: scale);
      expect(result, BigInt.parse(scaled), reason: input);
      expect(normalizeDecimalText(input, scale: scale), canonical);
      expect(decimalTextFromScaled(result, scale: scale), canonical);
    }
    expect(
      decimalTextFromScaled(BigInt.from(-1), scale: 2, fixed: true),
      '-0.01',
    );
    expect(decimalTextFromScaled(BigInt.zero, scale: 2, fixed: true), '0.00');
  });

  test(
    'decimal boundary rejects malformed or inexact values instead of rounding',
    () {
      for (final input in [
        '.5',
        '1.',
        '+1',
        '1e2',
        'NaN',
        'Infinity',
        '1,000',
        '--1',
        '',
        '1.005',
      ]) {
        expect(
          () => decimalScaledInteger(input, scale: 2),
          throwsFormatException,
          reason: input,
        );
      }
      expect(() => decimalScaledInteger('1', scale: -1), throwsArgumentError);
      expect(
        () => decimalTextFromScaled(BigInt.one, scale: -1),
        throwsArgumentError,
      );
    },
  );
}
