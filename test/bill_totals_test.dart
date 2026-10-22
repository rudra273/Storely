import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_totals.dart';

BillItem _item(double price, num qty, {double gst = 18}) => BillItem(
  productName: 'Item',
  sellingPriceSnapshot: price,
  gstPercentSnapshot: gst,
  quantity: qty,
);

BillTotals _totals(
  List<BillItem> items, {
  double discount = 0,
  bool registered = true,
  bool interState = false,
  bool roundOff = false,
}) => BillTotals.forCart(
  items,
  discountPercent: discount,
  gstRegistered: registered,
  interState: interState,
  roundOff: roundOff,
);

void main() {
  group('BillTotals GST math', () {
    test('Rs.100 incl. 18% x1: taxable + tax equals the price', () {
      final t = _totals([_item(100, 1)]);
      expect(t.taxableAmount, 84.75);
      expect(t.gstAmount, 15.25);
      expect(t.cgstAmount, 7.63);
      expect(t.sgstAmount, 7.62);
      expect(t.netAmount, 100);
      expect(t.grandTotal, 100);
    });

    test('Rs.100 incl. 18% x100: no per-unit rounding blow-up', () {
      // Old code rounded per unit then multiplied: CGST+SGST = 1526.00 and
      // taxable + tax = 10001.
      final t = _totals([_item(100, 100)]);
      expect(t.taxableAmount, 8474.58);
      expect(t.gstAmount, 1525.42);
      expect(t.cgstAmount + t.sgstAmount, closeTo(1525.42, 1e-9));
      expect(t.grandTotal, 10000);
    });

    test('discount applies before tax', () {
      final t = _totals([_item(100, 3)], discount: 10);
      expect(t.subtotal, 300);
      expect(t.discountAmount, 30);
      expect(t.netAmount, 270);
      expect(t.taxableAmount + t.gstAmount, closeTo(270, 1e-9));
    });

    test('inter-state supply uses IGST only', () {
      final t = _totals([_item(118, 2)], interState: true);
      expect(t.igstAmount, 36);
      expect(t.cgstAmount, 0);
      expect(t.sgstAmount, 0);
      expect(t.taxableAmount, 200);
    });

    test('unregistered shop charges no GST', () {
      final t = _totals([_item(100, 2)], registered: false);
      expect(t.gstAmount, 0);
      expect(t.taxableAmount, 200);
      expect(t.grandTotal, 200);
    });

    test('round-off to nearest rupee, both directions', () {
      final up = _totals([_item(58.6, 1)], roundOff: true);
      expect(up.roundOffAmount, 0.4);
      expect(up.grandTotal, 59);

      final down = _totals([_item(58.4, 1)], roundOff: true);
      expect(down.roundOffAmount, -0.4);
      expect(down.grandTotal, 58);

      final off = _totals([_item(58.4, 1)]);
      expect(off.roundOffAmount, 0);
      expect(off.grandTotal, 58.4);
    });

    test('random carts always reconcile to the paisa', () {
      final rng = Random(42);
      const rates = [0.0, 5, 18, 40];
      for (var run = 0; run < 500; run++) {
        final items = List.generate(
          1 + rng.nextInt(6),
          (_) => _item(
            (rng.nextInt(500000) + 1) / 100,
            rng.nextBool() ? 1 + rng.nextInt(50) : (rng.nextInt(5000) + 1) / 1000,
            gst: rates[rng.nextInt(rates.length)].toDouble(),
          ),
        );
        final t = _totals(
          items,
          discount: rng.nextInt(4) * 5.0,
          interState: rng.nextBool(),
          roundOff: rng.nextBool(),
        );
        final taxPlusTaxable =
            t.taxableAmount + t.cgstAmount + t.sgstAmount + t.igstAmount;
        expect(taxPlusTaxable, closeTo(t.netAmount, 1e-6), reason: '$run');
        expect(
          t.subtotal - t.discountAmount,
          closeTo(t.netAmount, 1e-6),
          reason: '$run',
        );
        expect(
          t.netAmount + t.roundOffAmount,
          closeTo(t.grandTotal, 1e-6),
          reason: '$run',
        );
        expect(t.roundOffAmount.abs(), lessThanOrEqualTo(0.5));
      }
    });
  });

  test('roundMoney rounds half-paise up despite float storage', () {
    expect(roundMoney(1.005), 1.01);
    expect(roundMoney(2.675), 2.68);
    expect(roundMoney(-1.005), -1.01);
  });
}
