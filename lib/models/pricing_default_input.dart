/// Legacy settings accept ASCII Decimal syntax; calculations retain the existing
/// double boundary, while range and meaningful precision are checked exactly.
class PricingDefaultNumber {
  final double value;
  final String text;
  final int scale;
  const PricingDefaultNumber._(this.value, this.text, this.scale);

  static final _decimal = RegExp(
    r'^([+-]?)(?:([0-9]+)(?:\.([0-9]*))?|\.([0-9]+))(?:[eE]([+-]?[0-9]+))?$',
  );
  static final _leadingZeros = RegExp(r'^0+');
  static final _trailingZeros = RegExp(r'0+$');

  static PricingDefaultNumber? parse(String? raw, {required int maximum}) {
    if (raw == null) return null;
    final text = raw.trim();
    final match = _decimal.firstMatch(text);
    if (match == null) return null;
    final fraction = match.group(3) ?? match.group(4) ?? '';
    var digits = '${match.group(2) ?? ''}$fraction'.replaceFirst(
      _leadingZeros,
      '',
    );
    if (digits.isEmpty) return PricingDefaultNumber._(0, text, 0);
    if (match.group(1) == '-') return null;
    final withoutZeros = digits.replaceFirst(_trailingZeros, '');
    final removed = digits.length - withoutZeros.length;
    digits = withoutZeros;
    final exponent = BigInt.parse(match.group(5) ?? '0');
    final scale = BigInt.from(fraction.length - removed) - exponent;
    if (scale > BigInt.from(18)) return null;
    final integerDigits = BigInt.from(digits.length) - scale;
    if (integerDigits > BigInt.from(maximum.toString().length)) return null;
    // A nonzero bounded value can only need a small power after the checks above.
    final decimalScale = scale.toInt();
    final coefficient = BigInt.parse(digits);
    final valid = decimalScale >= 0
        ? coefficient <=
              BigInt.from(maximum) * BigInt.from(10).pow(decimalScale)
        : coefficient * BigInt.from(10).pow(-decimalScale) <=
              BigInt.from(maximum);
    if (!valid) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) return null;
    return PricingDefaultNumber._(
      value,
      text,
      decimalScale < 0 ? 0 : decimalScale,
    );
  }
}
