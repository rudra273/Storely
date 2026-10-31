// Writes the shared test vectors that pin the web's billing maths to the phone's.
//
//   STORELY_VECTORS_OUT=../storelyapi/tests/fixtures/billing_vectors.json \
//     flutter test test/billing_vectors_test.dart
//
// (`make vectors` in the storelyapi repo does this; `make vectors-check` regenerates and
// fails when the committed file differs, i.e. when the phone's rules changed.) Without the
// variable the test only checks that the generator itself is sane.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_totals.dart';
import 'package:storely/models/invoice_numbering.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/product.dart';

Map<String, dynamic> _item(BillItem i) => {
  'gst_snapshot': i.gstSnapshot,
  'taxable_value_snapshot': i.taxableValueSnapshot,
  'cgst_amount_snapshot': i.cgstAmountSnapshot,
  'sgst_amount_snapshot': i.sgstAmountSnapshot,
  'igst_amount_snapshot': i.igstAmountSnapshot,
  'subtotal': i.subtotal,
  'line_amount': i.lineAmount,
  'total_taxable_value': i.totalTaxableValue,
  'total_gst': i.totalGst,
  'total_cgst': i.totalCgst,
  'total_sgst': i.totalSgst,
  'total_igst': i.totalIgst,
};

List<Map<String, dynamic>> _totalsVectors() {
  final rng = Random(2026);
  const rates = [null, 0.0, 0.25, 3.0, 5.0, 12.0, 18.0, 28.0, 40.0];
  const prices = [
    1.0,
    1.005,
    9.99,
    10.0,
    12.5,
    33.33,
    99.0,
    100.0,
    149.95,
    250.0,
    1234.56,
    99999.99,
  ];
  const qtys = [1.0, 2.0, 3.0, 0.5, 1.5, 2.25, 7.0, 12.0, 0.125];
  const discounts = [0.0, 0.0, 5.0, 10.0, 12.5, 33.0, 100.0];
  final out = <Map<String, dynamic>>[];
  for (var n = 0; n < 91; n++) {
    final count = 1 + rng.nextInt(5);
    final lines = n == 90
        ? [(price: 105.0, qty: -0.125, rate: 5.0)]
        : [
            for (var i = 0; i < count; i++)
              (
                price: prices[rng.nextInt(prices.length)],
                qty: qtys[rng.nextInt(qtys.length)],
                rate: rates[rng.nextInt(rates.length)],
              ),
          ];
    final discount = n == 90 ? 12.5 : discounts[rng.nextInt(discounts.length)];
    final registered = n == 90 || rng.nextBool() || n % 3 == 0;
    final inter = n == 90 || rng.nextBool();
    final roundOff = n == 90 || rng.nextBool();
    final items = [
      for (final l in lines)
        BillItem(
          productName: 'Item',
          sellingPriceSnapshot: l.price,
          gstPercentSnapshot: l.rate,
          quantity: l.qty,
        ),
    ];
    final taxed = [
      for (final item in items)
        BillTotals.taxedItem(
          item,
          discountPercent: discount,
          gstRegistered: registered,
          interState: inter,
        ),
    ];
    final t = BillTotals.fromTaxedItems(taxed, roundOff: roundOff);
    out.add({
      'items': [
        for (final l in lines)
          {'selling_price': l.price, 'quantity': l.qty, 'gst_percent': l.rate},
      ],
      'discount_percent': discount,
      'gst_registered': registered,
      'inter_state': inter,
      'round_off': roundOff,
      'taxed_items': taxed.map(_item).toList(),
      'totals': {
        'subtotal': t.subtotal,
        'discount_amount': t.discountAmount,
        'taxable_amount': t.taxableAmount,
        'cgst_amount': t.cgstAmount,
        'sgst_amount': t.sgstAmount,
        'igst_amount': t.igstAmount,
        'net_amount': t.netAmount,
        'round_off_amount': t.roundOffAmount,
        'grand_total': t.grandTotal,
      },
    });
  }
  return out;
}

List<Map<String, dynamic>> _pricingVectors() {
  final rng = Random(7);
  double? maybe(double v) => rng.nextInt(3) == 0 ? null : v;
  final out = <Map<String, dynamic>>[];
  for (var n = 0; n < 80; n++) {
    final purchase = [10.0, 45.5, 99.0, 100.0, 250.75, 1000.0][rng.nextInt(6)];
    final product = Product(
      name: 'P$n',
      mrp: 0,
      purchasePrice: purchase,
      quantity: 1,
      gstPercent: maybe([5.0, 12.0, 18.0][rng.nextInt(3)]),
      overheadCost: maybe([0.0, 2.5, 10.0][rng.nextInt(3)]),
      profitMarginPercent: maybe([0.0, 15.0, 20.5, 50.0][rng.nextInt(4)]),
      directPriceToggle: rng.nextInt(3) == 0,
      manualPrice: maybe([55.0, 120.0, 333.33][rng.nextInt(3)]),
    );
    final global = GlobalPricingSettings(
      defaultGstPercent: [0.0, 5.0, 18.0][rng.nextInt(3)],
      defaultOverheadCost: [0.0, 3.0][rng.nextInt(2)],
      defaultProfitMarginPercent: [0.0, 10.0, 30.0][rng.nextInt(3)],
      gstRegistered: rng.nextBool(),
    );
    final category = rng.nextBool()
        ? null
        : CategoryPricingSettings(
            name: 'C',
            gstPercent: maybe(12.0),
            overheadCost: maybe(1.5),
            profitMarginPercent: maybe(25.0),
          );
    final b = PricingCalculator.resolveProductPrice(product, global, category);
    out.add({
      'product': {
        'purchase_price': product.purchasePrice,
        'gst_percent': product.gstPercent,
        'overhead_cost': product.overheadCost,
        'profit_margin_percent': product.profitMarginPercent,
        'direct_price_toggle': product.directPriceToggle,
        'manual_price': product.manualPrice,
        'mrp': product.mrp,
      },
      'global': {
        'default_gst_percent': global.defaultGstPercent,
        'default_overhead_cost': global.defaultOverheadCost,
        'default_profit_margin_percent': global.defaultProfitMarginPercent,
        'gst_registered': global.gstRegistered,
      },
      'category': category == null
          ? null
          : {
              'gst_percent': category.gstPercent,
              'overhead_cost': category.overheadCost,
              'profit_margin_percent': category.profitMarginPercent,
            },
      'result': {
        'selling_price': b.sellingPrice,
        'pre_gst_selling_price': b.preGstSellingPrice,
        'output_gst_amount': b.outputGstAmount,
        'total_cost': b.totalCost,
        'profit_amount': b.profitAmount,
        'gst_percent': b.gstPercent,
        'was_direct_price': b.wasDirectPrice,
        'gst_registered': b.gstRegistered,
      },
    });
  }
  return out;
}

Map<String, dynamic> _numberingVectors() {
  final templates = [
    InvoiceNumbering.defaultTemplate,
    'INV-{YYYY}{MM}{DD}-{SEQ}',
    'B{YY}/{MM}/{SEQ}',
    '{DEVICE}{FY}-{SEQ}',
    'S{SEQ}',
    'INV/{FY}/{SEQ}{DEVICE}',
    'CN/{FY}/{SEQ}',
  ];
  final dates = [
    DateTime(2026, 3, 31),
    DateTime(2026, 4, 1),
    DateTime(2026, 10, 25),
    DateTime(2027, 1, 1),
    DateTime(2028, 2, 29),
    DateTime(2030, 12, 31),
  ];
  final formats = <Map<String, dynamic>>[];
  for (final t in templates) {
    for (final d in dates) {
      for (final (seq, pad, dev) in [
        (1, 4, ''),
        (37, 4, 'B'),
        (12345, 4, 'AB'),
        (9, 6, 'C'),
      ]) {
        formats.add({
          'template': t,
          'date': d.toIso8601String().substring(0, 10),
          'sequence': seq,
          'padding': pad,
          'device': dev,
          'number': InvoiceNumbering.format(
            template: t,
            date: d,
            sequence: seq,
            padding: pad,
            deviceCode: dev,
          ),
        });
      }
    }
  }
  final resets = <Map<String, dynamic>>[];
  for (final period in [
    'daily',
    'monthly',
    'financial_year',
    'never',
    null,
    'bogus',
  ]) {
    for (final d in dates) {
      resets.add({
        'period': period,
        'date': d.toIso8601String().substring(0, 10),
        'key': InvoiceNumbering.resetKey(d, period),
      });
    }
  }
  final validations = <Map<String, dynamic>>[];
  for (final t in [
    ...templates,
    'NOSEQ',
    'INV/{FY}/{SEQ}/{BAD}',
    'IN V/{FY}/{SEQ}',
    'LONGLONGPREFIX/{FY}/{SEQ}',
    '{SEQ}',
  ]) {
    for (final period in ['daily', 'monthly', 'financial_year', 'never']) {
      for (final pad in [3, 4, 8]) {
        validations.add({
          'template': t,
          'padding': pad,
          'reset_period': period,
          'problem': InvoiceNumbering.validate(
            template: t,
            padding: pad,
            resetPeriod: period,
          ),
        });
      }
    }
  }
  return {'formats': formats, 'resets': resets, 'validations': validations};
}

Map<String, dynamic> _roundingVectors() => {
  'values': [
    for (final v in [
      0.0,
      0.004,
      0.005,
      0.006,
      1.005,
      1.015,
      2.675,
      -1.005,
      -0.005,
      19.995,
      100.5,
      0.125,
      33.335,
      99999.995,
      -2.675,
    ])
      {'value': v, 'rounded': roundMoney(v)},
  ],
};

void main() {
  test('writes the shared billing vectors', () {
    final data = {
      'totals': _totalsVectors(),
      'pricing': _pricingVectors(),
      'numbering': _numberingVectors(),
      'rounding': _roundingVectors(),
    };
    expect((data['totals'] as List).length, 91);
    final out = Platform.environment['STORELY_VECTORS_OUT'];
    if (out == null) return;
    File(
      out,
    ).writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(data)}\n');
  });
}
