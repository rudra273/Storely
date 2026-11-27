import '../utils/exact_decimal.dart';
import 'bill.dart';

/// Rounds a rupee amount to paise using exact decimal half-away-from-zero.
double roundMoney(double value) {
  if (!value.isFinite) return value;
  return ExactDecimal.fromNum(value).toMoneyDouble();
}

/// GST + discount + round-off math for one bill, shared by the checkout
/// preview and the saved bill so the two can never disagree.
///
/// All intermediate arithmetic runs in exact [ExactDecimal] rationals backed by
/// [BigInt], eliminating binary floating-point drift and matching the server's
/// `decimal.Decimal` calculations to the exact paisa.
class BillTotals {
  final double subtotal;
  final double discountAmount;
  final double taxableAmount;
  final double cgstAmount;
  final double sgstAmount;
  final double igstAmount;

  /// Sum of line amounts after discount, including tax, before round-off.
  final double netAmount;
  final double roundOffAmount;
  final double grandTotal;

  const BillTotals({
    required this.subtotal,
    required this.discountAmount,
    required this.taxableAmount,
    required this.cgstAmount,
    required this.sgstAmount,
    required this.igstAmount,
    required this.netAmount,
    required this.roundOffAmount,
    required this.grandTotal,
  });

  double get gstAmount =>
      (ExactDecimal.fromNum(cgstAmount) +
              ExactDecimal.fromNum(sgstAmount) +
              ExactDecimal.fromNum(igstAmount))
          .toMoneyDouble();

  /// Totals for [taxedItems] (items already passed through [taxedItem] or
  /// [calculate]).
  factory BillTotals.fromTaxedItems(
    List<BillItem> taxedItems, {
    required bool roundOff,
    String? roundOffMode,
    double roundOffIncrement = 1.0,
    String billTaxMode = Bill.taxModeInclusive,
  }) {
    var subtotal = ExactDecimal.zero;
    var net = ExactDecimal.zero;
    var afterDocBase = ExactDecimal.zero;
    var taxable = ExactDecimal.zero;
    var intraGst = ExactDecimal.zero;
    var igst = ExactDecimal.zero;
    for (final item in taxedItems) {
      final lineSub = ExactDecimal.fromNum(item.subtotal);
      final lineNet = ExactDecimal.fromNum(item.lineAmount);
      final lineTaxable = ExactDecimal.fromNum(item.totalTaxableValue);
      subtotal += lineSub;
      net += lineNet;
      taxable += lineTaxable;
      final effTaxMode = item.taxMode ?? billTaxMode;
      afterDocBase += effTaxMode == Bill.taxModeExclusive
          ? lineTaxable
          : lineNet;
      if (item.igstAmountSnapshot > 0) {
        igst += ExactDecimal.fromNum(item.totalIgst);
      } else {
        intraGst += ExactDecimal.fromNum(item.totalGst);
      }
    }
    // Split intra-state GST once for the bill, so CGST and SGST are equal
    // (or 1 paisa apart) instead of drifting by a paisa per line.
    final cgst = (intraGst / ExactDecimal.fromInt(2)).roundMoney();
    final sgst = (intraGst - cgst).roundMoney();
    subtotal = subtotal.roundMoney();
    net = net.roundMoney();
    final discountAmount = (subtotal - afterDocBase).roundMoney();
    final effectiveMode =
        roundOffMode ?? (roundOff ? Bill.roundOffNearest : Bill.roundOffNone);
    final inc = ExactDecimal.fromNum(roundOffIncrement);
    final target = _applyRoundOff(net, mode: effectiveMode, increment: inc);
    final roundOffAmount = (target - net).roundMoney();
    return BillTotals(
      subtotal: subtotal.toMoneyDouble(),
      discountAmount: discountAmount.toMoneyDouble(),
      taxableAmount: taxable.toMoneyDouble(),
      cgstAmount: cgst.toMoneyDouble(),
      sgstAmount: sgst.toMoneyDouble(),
      igstAmount: igst.toMoneyDouble(),
      netAmount: net.toMoneyDouble(),
      roundOffAmount: roundOffAmount.toMoneyDouble(),
      grandTotal: (net + roundOffAmount).toMoneyDouble(),
    );
  }

  /// Full exact calculation of both taxed [BillItem] snapshots and [BillTotals]
  /// for a cart with per-line discounts, document percent/amount discount,
  /// inclusive/exclusive/mixed tax modes, and configurable round-off.
  static ({List<BillItem> items, BillTotals totals}) calculate(
    List<BillItem> items, {
    double discountPercent = 0,
    String discountMode = Bill.discountModePercent,
    double? discountValue,
    String taxMode = Bill.taxModeInclusive,
    required bool gstRegistered,
    required bool interState,
    bool roundOff = false,
    String? roundOffMode,
    double roundOffIncrement = 1.0,
  }) {
    final effectiveDocMode = discountMode == Bill.discountModeAmount
        ? Bill.discountModeAmount
        : Bill.discountModePercent;
    final rawDocValue =
        discountValue ??
        (effectiveDocMode == Bill.discountModePercent ? discountPercent : 0.0);
    final effectiveBillTaxMode = taxMode == Bill.taxModeExclusive
        ? Bill.taxModeExclusive
        : Bill.taxModeInclusive;
    final effectiveRoundOffMode =
        roundOffMode ?? (roundOff ? Bill.roundOffNearest : Bill.roundOffNone);
    final inc = ExactDecimal.fromNum(roundOffIncrement);

    // Stage 1: Per-line pre-document-discount stage.
    final lineSubtotals = <ExactDecimal>[];
    final lineDiscountAmounts = <ExactDecimal>[];
    final afterLineBases = <ExactDecimal>[];
    final afterLineUnits = <ExactDecimal>[];
    final quantities = <ExactDecimal>[];

    for (final item in items) {
      final price = ExactDecimal.fromNum(item.sellingPriceSnapshot);
      final qty = ExactDecimal.fromNum(item.quantity);
      quantities.add(qty);

      final sub = (price * qty).roundMoney();
      lineSubtotals.add(sub);

      final lineMode = item.discountMode == Bill.discountModeAmount
          ? Bill.discountModeAmount
          : Bill.discountModePercent;
      final lineVal = ExactDecimal.fromNum(item.discountValue);

      if (lineMode == Bill.discountModePercent) {
        final clamped = lineVal.clamp(ExactDecimal.zero, ExactDecimal.hundred);
        final factor = ExactDecimal.one - (clamped / ExactDecimal.hundred);
        final afterUnit = price * factor;
        final afterBase = (afterUnit * qty).roundMoney();
        final lineDisc = (sub - afterBase).roundMoney();
        lineDiscountAmounts.add(lineDisc);
        afterLineBases.add(afterBase);
        afterLineUnits.add(afterUnit);
      } else {
        if (lineVal.isNegative || lineVal > sub.abs()) {
          throw ArgumentError(
            'Line discount (${lineVal.toFixed(2)}) cannot exceed line subtotal (${sub.abs().toFixed(2)}).',
          );
        }
        final signedDisc = qty.isNegative ? -lineVal : lineVal;
        final lineDisc = signedDisc.roundMoney();
        final afterBase = (sub - lineDisc).roundMoney();
        final afterUnit = qty.isZero ? ExactDecimal.zero : afterBase / qty;
        lineDiscountAmounts.add(lineDisc);
        afterLineBases.add(afterBase);
        afterLineUnits.add(afterUnit);
      }
    }

    // Stage 2: Document discount stage.
    var totalAfterLineBase = ExactDecimal.zero;
    for (final base in afterLineBases) {
      totalAfterLineBase += base;
    }

    final afterDocBases = <ExactDecimal>[];
    final discountedUnits = <ExactDecimal>[];

    if (effectiveDocMode == Bill.discountModePercent) {
      final clamped = ExactDecimal.fromNum(
        rawDocValue,
      ).clamp(ExactDecimal.zero, ExactDecimal.hundred);
      final docFactor = ExactDecimal.one - (clamped / ExactDecimal.hundred);
      for (var i = 0; i < items.length; i++) {
        final unit = afterLineUnits[i] * docFactor;
        final base = (unit * quantities[i]).roundMoney();
        discountedUnits.add(unit);
        afterDocBases.add(base);
      }
    } else {
      final docDisc = ExactDecimal.fromNum(rawDocValue);
      if (docDisc.isNegative || docDisc > totalAfterLineBase.abs()) {
        throw ArgumentError(
          'Document discount (${docDisc.toFixed(2)}) cannot exceed subtotal (${totalAfterLineBase.abs().toFixed(2)}).',
        );
      }
      final signedDocDisc = totalAfterLineBase.isNegative ? -docDisc : docDisc;
      final eligible = <int>[
        for (var i = 0; i < items.length; i++)
          if (!afterLineBases[i].isZero) i,
      ];
      final prorated = List<ExactDecimal>.filled(
        items.length,
        ExactDecimal.zero,
      );
      if (eligible.isNotEmpty) {
        var allocated = ExactDecimal.zero;
        for (var k = 0; k < eligible.length - 1; k++) {
          final idx = eligible[k];
          final share = (signedDocDisc * afterLineBases[idx] / totalAfterLineBase)
              .roundMoney();
          prorated[idx] = share;
          allocated += share;
        }
        final lastIdx = eligible.last;
        prorated[lastIdx] = (signedDocDisc - allocated).roundMoney();
      }
      for (var i = 0; i < items.length; i++) {
        final base = (afterLineBases[i] - prorated[i]).roundMoney();
        final unit = quantities[i].isZero
            ? ExactDecimal.zero
            : base / quantities[i];
        afterDocBases.add(base);
        discountedUnits.add(unit);
      }
    }

    // Stage 3: Tax extraction / addition stage.
    final taxedItems = <BillItem>[];
    var subtotal = ExactDecimal.zero;
    var totalAfterDocBase = ExactDecimal.zero;
    var taxableAmount = ExactDecimal.zero;
    var netAmount = ExactDecimal.zero;
    var intraGst = ExactDecimal.zero;
    var igstAmount = ExactDecimal.zero;

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final qty = quantities[i];
      final effMode = item.taxMode ?? effectiveBillTaxMode;
      final gstPct = ExactDecimal.fromNum(item.gstPercentSnapshot ?? 0.0);
      final charged = gstRegistered && gstPct.isPositive;
      final discountedUnit = discountedUnits[i];
      final afterDocBase = afterDocBases[i];

      late final ExactDecimal taxableUnit;
      late final ExactDecimal gstUnit;
      late final ExactDecimal totalTaxableValue;
      late final ExactDecimal totalGst;
      late final ExactDecimal lineAmount;

      if (effMode == Bill.taxModeExclusive) {
        taxableUnit = discountedUnit;
        gstUnit = charged
            ? discountedUnit * (gstPct / ExactDecimal.hundred)
            : ExactDecimal.zero;
        totalTaxableValue = afterDocBase;
        totalGst = (gstUnit * qty).roundMoney();
        lineAmount = (totalTaxableValue + totalGst).roundMoney();
      } else {
        taxableUnit = charged
            ? discountedUnit /
                  (ExactDecimal.one + (gstPct / ExactDecimal.hundred))
            : discountedUnit;
        gstUnit = charged ? discountedUnit - taxableUnit : ExactDecimal.zero;
        lineAmount = afterDocBase;
        totalTaxableValue = (taxableUnit * qty).roundMoney();
        totalGst = (lineAmount - totalTaxableValue).roundMoney();
      }

      final intraState = charged && !interState;
      final halfGstUnit = gstUnit / ExactDecimal.fromInt(2);

      subtotal += lineSubtotals[i];
      totalAfterDocBase += afterDocBase;
      taxableAmount += totalTaxableValue;
      netAmount += lineAmount;
      if (charged && interState) {
        igstAmount += totalGst;
      } else {
        intraGst += totalGst;
      }

      taxedItems.add(
        BillItem(
          uuid: item.uuid,
          shopId: item.shopId,
          productId: item.productId,
          productUuid: item.productUuid,
          productName: item.productName,
          hsnCodeSnapshot: item.hsnCodeSnapshot,
          hsnTypeSnapshot: item.hsnTypeSnapshot,
          mrp: item.mrp,
          unit: item.unit,
          purchasePriceSnapshot: item.purchasePriceSnapshot,
          sellingPriceSnapshot: item.sellingPriceSnapshot,
          costSnapshot: item.costSnapshot,
          profitSnapshot: item.profitSnapshot,
          commissionSnapshot: item.commissionSnapshot,
          gstSnapshot: gstUnit.toDouble(),
          gstPercentSnapshot: item.gstPercentSnapshot,
          taxableValueSnapshot: taxableUnit.toDouble(),
          cgstAmountSnapshot: intraState ? halfGstUnit.toDouble() : 0,
          sgstAmountSnapshot: intraState ? halfGstUnit.toDouble() : 0,
          igstAmountSnapshot: charged && interState ? gstUnit.toDouble() : 0,
          wasDirectPrice: item.wasDirectPrice,
          quantity: item.quantity,
          discountMode: item.discountMode,
          discountValue: item.discountValue,
          discountAmount: lineDiscountAmounts[i].toMoneyDouble(),
          taxMode: item.taxMode,
          originalItemUuid: item.originalItemUuid,
          mrpSnapshot: item.mrpSnapshot,
        ),
      );
    }

    // Stage 4: Invoice totals & round-off stage.
    subtotal = subtotal.roundMoney();
    totalAfterDocBase = totalAfterDocBase.roundMoney();
    final discountAmount = (subtotal - totalAfterDocBase).roundMoney();
    taxableAmount = taxableAmount.roundMoney();
    netAmount = netAmount.roundMoney();
    final cgstAmount = (intraGst / ExactDecimal.fromInt(2)).roundMoney();
    final sgstAmount = (intraGst - cgstAmount).roundMoney();
    igstAmount = igstAmount.roundMoney();

    final target = _applyRoundOff(
      netAmount,
      mode: effectiveRoundOffMode,
      increment: inc,
    );
    final roundOffAmount = (target - netAmount).roundMoney();
    final grandTotal = (netAmount + roundOffAmount).roundMoney();

    return (
      items: taxedItems,
      totals: BillTotals(
        subtotal: subtotal.toMoneyDouble(),
        discountAmount: discountAmount.toMoneyDouble(),
        taxableAmount: taxableAmount.toMoneyDouble(),
        cgstAmount: cgstAmount.toMoneyDouble(),
        sgstAmount: sgstAmount.toMoneyDouble(),
        igstAmount: igstAmount.toMoneyDouble(),
        netAmount: netAmount.toMoneyDouble(),
        roundOffAmount: roundOffAmount.toMoneyDouble(),
        grandTotal: grandTotal.toMoneyDouble(),
      ),
    );
  }

  /// Convenience: tax every cart item, then total them.
  factory BillTotals.forCart(
    List<BillItem> items, {
    double discountPercent = 0,
    String discountMode = Bill.discountModePercent,
    double? discountValue,
    String taxMode = Bill.taxModeInclusive,
    required bool gstRegistered,
    required bool interState,
    bool roundOff = false,
    String? roundOffMode,
    double roundOffIncrement = 1.0,
  }) {
    return calculate(
      items,
      discountPercent: discountPercent,
      discountMode: discountMode,
      discountValue: discountValue,
      taxMode: taxMode,
      gstRegistered: gstRegistered,
      interState: interState,
      roundOff: roundOff,
      roundOffMode: roundOffMode,
      roundOffIncrement: roundOffIncrement,
    ).totals;
  }

  /// Copy of a single cart [item] with discounted, full-precision per-unit tax
  /// snapshots.
  static BillItem taxedItem(
    BillItem item, {
    required double discountPercent,
    required bool gstRegistered,
    required bool interState,
    String taxMode = Bill.taxModeInclusive,
  }) {
    return calculate(
      [item],
      discountPercent: discountPercent,
      taxMode: taxMode,
      gstRegistered: gstRegistered,
      interState: interState,
      roundOffMode: Bill.roundOffNone,
    ).items.single;
  }

  static ExactDecimal _applyRoundOff(
    ExactDecimal netAmount, {
    required String mode,
    required ExactDecimal increment,
  }) {
    return switch (mode) {
      Bill.roundOffNone => netAmount,
      Bill.roundOffUp => netAmount.roundUpToMultiple(increment),
      Bill.roundOffDown => netAmount.roundDownToMultiple(increment),
      _ => netAmount.roundNearestToMultiple(increment),
    };
  }
}
