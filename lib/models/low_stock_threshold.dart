import '../utils/decimal_text.dart';

/// Shared shop warning threshold. Raw invalid entries stay in their editor;
/// only this exact plain-decimal policy reaches persistence.
class LowStockThreshold {
  final double value;
  final String text;
  const LowStockThreshold._(this.value, this.text);
  static final _edges = RegExp(r'^[ \t\r\n]+|[ \t\r\n]+$');
  static final _plain = RegExp(r'^[0-9]+(?:\.[0-9]+)?$');
  static final _maximum = BigInt.from(999999999) * BigInt.from(10000);

  static LowStockThreshold? parse(String? raw) {
    if (raw == null) return null;
    final text = raw.replaceAll(_edges, '');
    if (!_plain.hasMatch(text)) return null;
    try {
      final scaled = decimalScaledInteger(text, scale: 4);
      if (scaled > _maximum) return null;
      return LowStockThreshold._(
        scaled.toDouble() / 10000,
        decimalTextFromScaled(scaled, scale: 4),
      );
    } on FormatException {
      return null;
    }
  }
}

String lowStockThresholdText(num value) =>
    LowStockThreshold.parse(value.toString())?.text ?? '5';
