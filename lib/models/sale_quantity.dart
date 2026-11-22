import '../utils/decimal_text.dart';

const saleQuantityGuidance =
    'Enter a quantity from 0.001 to 1,000,000 with up to three decimal places.';

final _saleQuantityPattern = RegExp(r'^\d+(?:\.\d+)?$');
final _maxSaleQuantity = BigInt.from(1000000000);

/// Returns thousandths for a new sale quantity, without rounding the input.
BigInt? saleQuantityThousandths(String raw) {
  final text = raw.trim();
  if (!_saleQuantityPattern.hasMatch(text)) return null;
  try {
    final amount = decimalScaledInteger(text, scale: 3);
    return amount > BigInt.zero && amount <= _maxSaleQuantity ? amount : null;
  } on FormatException {
    return null;
  }
}

double? saleQuantityValue(String raw) {
  final amount = saleQuantityThousandths(raw);
  return amount == null ? null : amount.toDouble() / 1000;
}

double? adjustSaleQuantity(double current, int units) {
  final quantity = saleQuantityThousandths(current.toString());
  if (quantity == null) return null;
  final next = quantity + BigInt.from(units) * BigInt.from(1000);
  if (next > _maxSaleQuantity) return null;
  return next <= BigInt.zero ? 0 : next.toDouble() / 1000;
}
