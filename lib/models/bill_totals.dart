import 'bill.dart';

/// Rounds a rupee amount to paise. The tiny nudge keeps values like 1.005
/// (stored as 1.00499999...) rounding up the way a person would expect.
double roundMoney(double value) {
  final nudge = value >= 0 ? 1e-9 : -1e-9;
  return (value * 100 + nudge).roundToDouble() / 100;
}

/// GST + discount math for one bill, shared by the checkout preview and the
/// saved bill so the two can never disagree.
///
/// Rules (Indian GST practice):
/// - Discount is applied to the selling price before tax.
/// - Per-unit tax snapshots are stored at full precision; every amount is
///   computed per *line* (unit x qty) and rounded to paise once.
/// - Line GST = line amount - line taxable value, so taxable + GST always
///   equals the line amount exactly. CGST = GST / 2, SGST = GST - CGST.
/// - Bill totals are sums of rounded line values. The grand total is
///   optionally rounded to the nearest rupee with an explicit round-off.
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

  double get gstAmount => roundMoney(cgstAmount + sgstAmount + igstAmount);

  /// Totals for [taxedItems] (items already passed through [taxedItem]).
  factory BillTotals.fromTaxedItems(
    List<BillItem> taxedItems, {
    required bool roundOff,
  }) {
    var subtotal = 0.0;
    var net = 0.0;
    var taxable = 0.0;
    var intraGst = 0.0;
    var igst = 0.0;
    for (final item in taxedItems) {
      subtotal += item.subtotal;
      net += item.lineAmount;
      taxable += item.totalTaxableValue;
      if (item.totalIgst > 0) {
        igst += item.totalIgst;
      } else {
        intraGst += item.totalGst;
      }
    }
    // Split intra-state GST once for the bill, so CGST and SGST are equal
    // (or 1 paisa apart) instead of drifting by a paisa per line.
    final cgst = roundMoney(intraGst / 2);
    final sgst = roundMoney(intraGst - cgst);
    subtotal = roundMoney(subtotal);
    net = roundMoney(net);
    final roundOffAmount = roundOff
        ? roundMoney(net.roundToDouble() - net)
        : 0.0;
    return BillTotals(
      subtotal: subtotal,
      discountAmount: roundMoney(subtotal - net),
      taxableAmount: roundMoney(taxable),
      cgstAmount: cgst,
      sgstAmount: sgst,
      igstAmount: roundMoney(igst),
      netAmount: net,
      roundOffAmount: roundOffAmount,
      grandTotal: roundMoney(net + roundOffAmount),
    );
  }

  /// Convenience: tax every cart item, then total them.
  factory BillTotals.forCart(
    List<BillItem> items, {
    required double discountPercent,
    required bool gstRegistered,
    required bool interState,
    required bool roundOff,
  }) {
    return BillTotals.fromTaxedItems(
      items
          .map(
            (item) => taxedItem(
              item,
              discountPercent: discountPercent,
              gstRegistered: gstRegistered,
              interState: interState,
            ),
          )
          .toList(),
      roundOff: roundOff,
    );
  }

  /// Copy of a cart [item] with discounted, full-precision per-unit tax
  /// snapshots. GST is treated as included in the selling price.
  static BillItem taxedItem(
    BillItem item, {
    required double discountPercent,
    required bool gstRegistered,
    required bool interState,
  }) {
    final gstPercent = item.gstPercentSnapshot ?? 0.0;
    final discountFactor = (1 - discountPercent / 100).clamp(0.0, 1.0);
    final discountedUnitGross = item.sellingPriceSnapshot * discountFactor;
    final charged = gstRegistered && gstPercent > 0;
    final taxableUnit = charged
        ? discountedUnitGross / (1 + gstPercent / 100)
        : discountedUnitGross;
    final gstUnit = charged ? discountedUnitGross - taxableUnit : 0.0;
    final intraState = charged && !interState;

    return BillItem(
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
      gstSnapshot: gstUnit,
      gstPercentSnapshot: item.gstPercentSnapshot,
      taxableValueSnapshot: taxableUnit,
      cgstAmountSnapshot: intraState ? gstUnit / 2 : 0,
      sgstAmountSnapshot: intraState ? gstUnit / 2 : 0,
      igstAmountSnapshot: charged && interState ? gstUnit : 0,
      wasDirectPrice: item.wasDirectPrice,
      quantity: item.quantity,
      mrpSnapshot: item.mrpSnapshot,
    );
  }
}
