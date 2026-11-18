/// Exact plain-decimal boundaries for new command contracts. Values never pass
/// through double; callers retain their own range and sign/business validation.
BigInt decimalScaledInteger(String value, {required int scale}) {
  if (scale < 0) {
    throw ArgumentError.value(scale, 'scale', 'Must be non-negative');
  }
  final text = value.trim();
  final match = RegExp(r'^(-?)([0-9]+)(?:\.([0-9]+))?$').firstMatch(text);
  if (match == null) throw const FormatException('Invalid plain decimal');
  final fraction = match.group(3) ?? '';
  if (fraction.length > scale &&
      fraction.substring(scale).contains(RegExp(r'[1-9]'))) {
    throw FormatException('Decimal exceeds $scale fractional places');
  }
  final kept = fraction.length > scale
      ? fraction.substring(0, scale)
      : fraction;
  final factor = BigInt.from(10).pow(scale);
  final magnitude =
      BigInt.parse(match.group(2)!) * factor +
      (scale == 0 ? BigInt.zero : BigInt.parse(kept.padRight(scale, '0')));
  return match.group(1) == '-' ? -magnitude : magnitude;
}

/// Formats a scaled integer exactly. Fixed output retains all scale places;
/// canonical output removes fractional trailing zeros, including negative zero.
String decimalTextFromScaled(
  BigInt value, {
  required int scale,
  bool fixed = false,
}) {
  if (scale < 0) {
    throw ArgumentError.value(scale, 'scale', 'Must be non-negative');
  }
  final magnitude = value.abs();
  final factor = BigInt.from(10).pow(scale);
  final whole = (magnitude ~/ factor).toString();
  var fraction = scale == 0
      ? ''
      : (magnitude % factor).toString().padLeft(scale, '0');
  if (!fixed) fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  final sign = value.isNegative ? '-' : '';
  return '$sign$whole${fraction.isEmpty ? '' : '.$fraction'}';
}

String normalizeDecimalText(String value, {required int scale}) =>
    decimalTextFromScaled(
      decimalScaledInteger(value, scale: scale),
      scale: scale,
    );
