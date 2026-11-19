import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_totals.dart';

/// These expectations are manually derived and reviewed in the shared fixture.
/// This test deliberately cannot regenerate them from Storely's calculators.
void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/financial_contract_v1.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
  const moneyFields = {
    'subtotal',
    'discount_amount',
    'taxable_amount',
    'cgst_amount',
    'sgst_amount',
    'igst_amount',
    'net_amount',
    'round_off_amount',
    'grand_total',
  };

  test('independent financial fixture has versioned complete expectations', () {
    expect(fixture['fixture_version'], 1);
    expect(fixture['provenance'], isNotNull);
    expect(cases, isNotEmpty);
    expect(cases.map((row) => row['id']).toSet().length, cases.length);
    for (final row in cases) {
      expect(row['rationale'], isA<String>());
      final expected = row['expected'] as Map<String, dynamic>;
      expect(expected.keys.toSet(), moneyFields, reason: row['id'] as String);
      for (final value in expected.values) {
        expect(value, matches(r'^-?[0-9]+\.[0-9]{2}$'));
      }
    }
  });

  String money(double value) {
    // The legacy calculator uses doubles internally. Assert exact final paise,
    // with only display-negative-zero normalization; no tolerance hides a paisa.
    final formatted = value.toStringAsFixed(2);
    return formatted == '-0.00' ? '0.00' : formatted;
  }

  for (final row in cases) {
    test('independent money contract: ${row['id']}', () {
      final input = row['input'] as Map<String, dynamic>;
      final items = [
        for (final line
            in (input['lines'] as List).cast<Map<String, dynamic>>())
          BillItem(
            productName: 'Reviewed fixture item',
            sellingPriceSnapshot: double.parse(line['selling_price'] as String),
            quantity: double.parse(line['quantity'] as String),
            gstPercentSnapshot: double.parse(line['gst_percent'] as String),
          ),
      ];
      final totals = BillTotals.forCart(
        items,
        discountPercent: double.parse(input['discount_percent'] as String),
        gstRegistered: input['gst_registered'] as bool,
        interState: input['inter_state'] as bool,
        roundOff: input['round_off'] as bool,
      );
      expect(
        {
          'subtotal': money(totals.subtotal),
          'discount_amount': money(totals.discountAmount),
          'taxable_amount': money(totals.taxableAmount),
          'cgst_amount': money(totals.cgstAmount),
          'sgst_amount': money(totals.sgstAmount),
          'igst_amount': money(totals.igstAmount),
          'net_amount': money(totals.netAmount),
          'round_off_amount': money(totals.roundOffAmount),
          'grand_total': money(totals.grandTotal),
        },
        row['expected'],
        reason: row['rationale'] as String,
      );
    });
  }
}
