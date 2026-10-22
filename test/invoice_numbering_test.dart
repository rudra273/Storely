import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/invoice_numbering.dart';

String? _check(String template, {String reset = 'financial_year', int pad = 4}) =>
    InvoiceNumbering.validate(
      template: template,
      padding: pad,
      resetPeriod: reset,
    );

void main() {
  test('financial year token follows April-March', () {
    expect(InvoiceNumbering.financialYear(DateTime(2026, 3, 31)), '2526');
    expect(InvoiceNumbering.financialYear(DateTime(2026, 4, 1)), '2627');
    expect(InvoiceNumbering.financialYear(DateTime(2099, 12, 1)), '9900');
  });

  test('default pattern formats within the GST limit', () {
    final number = InvoiceNumbering.format(
      template: InvoiceNumbering.defaultTemplate,
      date: DateTime(2026, 10, 23),
      sequence: 42,
      padding: InvoiceNumbering.defaultPadding,
      deviceId: 'local',
    );
    expect(number, 'INV/2627/0042');
    expect(_check(InvoiceNumbering.defaultTemplate), isNull);
  });

  test('legacy default is rejected as too long', () {
    expect(
      _check(InvoiceNumbering.legacyTemplate, reset: 'daily'),
      contains('Too long'),
    );
  });

  test('pattern must repeat-proof the reset period', () {
    expect(_check('INV-{SEQ}', reset: 'daily'), contains('needs'));
    expect(_check('INV/{YY}/{SEQ}'), contains('{FY}'));
    expect(_check('{YY}{MM}-{SEQ}', reset: 'monthly'), isNull);
    expect(_check('INV-{SEQ}', reset: 'never'), isNull);
  });

  test('rejects unknown tokens and characters GST does not allow', () {
    expect(_check('INV/{FY}/{SEQ}/{X}'), contains('Unknown token'));
    expect(_check('INV {FY}{SEQ}'), contains('letters'));
    expect(_check('INV#{FY}{SEQ}'), contains('letters'));
    expect(_check('INV/{FY}'), contains('{SEQ}'));
  });
}
