import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_totals.dart';

/// Verifies all 12 v1 + 14 v2 independent financial contract oracle cases
/// with 0.00 tolerance (exact paisa parity with Python Decimal).
void main() {
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

  String money(double value) {
    final formatted = value.toStringAsFixed(2);
    return formatted == '-0.00' ? '0.00' : formatted;
  }

  Map<String, String> asMap(BillTotals t) => {
    'subtotal': money(t.subtotal),
    'discount_amount': money(t.discountAmount),
    'taxable_amount': money(t.taxableAmount),
    'cgst_amount': money(t.cgstAmount),
    'sgst_amount': money(t.sgstAmount),
    'igst_amount': money(t.igstAmount),
    'net_amount': money(t.netAmount),
    'round_off_amount': money(t.roundOffAmount),
    'grand_total': money(t.grandTotal),
  };

  group('financial_contract_v1 (12 oracle cases)', () {
    final fixture =
        jsonDecode(
              File('test/fixtures/financial_contract_v1.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

    test('fixture v1 metadata and completeness', () {
      expect(fixture['fixture_version'], 1);
      expect(cases.length, 12);
      for (final row in cases) {
        final expected = row['expected'] as Map<String, dynamic>;
        expect(expected.keys.toSet(), moneyFields, reason: row['id'] as String);
      }
    });

    for (final row in cases) {
      test('v1 oracle: ${row['id']}', () {
        final input = row['input'] as Map<String, dynamic>;
        final items = [
          for (final line
              in (input['lines'] as List).cast<Map<String, dynamic>>())
            BillItem(
              productName: 'Fixture item',
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
        expect(asMap(totals), row['expected'], reason: row['rationale'] as String);
      });
    }
  });

  group('financial_contract_v2 (14 oracle cases)', () {
    final fixture =
        jsonDecode(
              File('test/fixtures/financial_contract_v2.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

    test('fixture v2 metadata and completeness', () {
      expect(fixture['fixture_version'], 2);
      expect(cases.length, 14);
      expect(cases.map((r) => r['id']).toSet().length, 14);
      for (final row in cases) {
        final expected = row['expected'] as Map<String, dynamic>;
        expect(expected.keys.toSet(), moneyFields, reason: row['id'] as String);
        for (final value in expected.values) {
          expect(value, matches(r'^-?[0-9]+\.[0-9]{2}$'));
        }
      }
    });

    for (final row in cases) {
      test('v2 oracle: ${row['id']}', () {
        final input = row['input'] as Map<String, dynamic>;
        final items = [
          for (final line
              in (input['lines'] as List).cast<Map<String, dynamic>>())
            BillItem(
              productName: 'Fixture v2 item',
              sellingPriceSnapshot: double.parse(line['selling_price'] as String),
              quantity: double.parse(line['quantity'] as String),
              gstPercentSnapshot: double.parse(line['gst_percent'] as String),
              discountMode:
                  line['line_discount_mode'] as String? ??
                  Bill.discountModePercent,
              discountValue: double.parse(
                (line['line_discount_value'] as String?) ?? '0',
              ),
              taxMode: line['tax_mode'] as String?,
            ),
        ];
        final calculated = BillTotals.calculate(
          items,
          discountMode:
              input['discount_mode'] as String? ?? Bill.discountModePercent,
          discountValue: double.parse(
            (input['discount_value'] as String?) ?? '0',
          ),
          taxMode: input['tax_mode'] as String? ?? Bill.taxModeInclusive,
          gstRegistered: input['gst_registered'] as bool,
          interState: input['inter_state'] as bool,
          roundOffMode:
              input['round_off_mode'] as String? ?? Bill.roundOffNearest,
          roundOffIncrement: double.parse(
            (input['round_off_increment'] as String?) ?? '1.00',
          ),
        );
        expect(
          asMap(calculated.totals),
          row['expected'],
          reason: row['rationale'] as String,
        );
      });
    }
  });
}
