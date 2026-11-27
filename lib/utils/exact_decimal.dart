/// Pure Dart exact rational decimal arithmetic backed by [BigInt].
///
/// Eliminates IEEE-754 binary floating-point drift in billing, GST, discount,
/// and round-off calculations so mobile matches Python's `decimal.Decimal`
/// to the exact paisa.
class ExactDecimal implements Comparable<ExactDecimal> {
  final BigInt numerator;
  final BigInt denominator;

  static final ExactDecimal zero = ExactDecimal._raw(BigInt.zero, BigInt.one);
  static final ExactDecimal one = ExactDecimal._raw(BigInt.one, BigInt.one);
  static final ExactDecimal hundred = ExactDecimal._raw(
    BigInt.from(100),
    BigInt.one,
  );

  const ExactDecimal._raw(this.numerator, this.denominator);

  factory ExactDecimal(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw ArgumentError('Denominator cannot be zero');
    }
    if (numerator == BigInt.zero) return zero;
    var n = numerator;
    var d = denominator;
    if (d.isNegative) {
      n = -n;
      d = -d;
    }
    final g = n.abs().gcd(d);
    if (g > BigInt.one) {
      n = n ~/ g;
      d = d ~/ g;
    }
    return ExactDecimal._raw(n, d);
  }

  factory ExactDecimal.fromInt(int value) =>
      value == 0 ? zero : ExactDecimal._raw(BigInt.from(value), BigInt.one);

  factory ExactDecimal.fromBigInt(BigInt value) =>
      value == BigInt.zero ? zero : ExactDecimal._raw(value, BigInt.one);

  /// Parses a decimal string (including optional sign and scientific notation).
  factory ExactDecimal.parse(String input) {
    final trimmed = input.trim();
    final match = RegExp(
      r'^([+-]?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$',
    ).firstMatch(trimmed);
    if (match == null) {
      throw FormatException('Invalid decimal: $input');
    }
    final negative = match.group(1) == '-';
    final intPart = match.group(2)!;
    final fracPart = match.group(3) ?? '';
    final exp = int.parse(match.group(4) ?? '0');

    var digits = BigInt.parse('$intPart$fracPart');
    if (digits == BigInt.zero) return zero;
    if (negative) digits = -digits;

    final shift = exp - fracPart.length;
    if (shift >= 0) {
      return ExactDecimal(digits * BigInt.from(10).pow(shift), BigInt.one);
    } else {
      return ExactDecimal(digits, BigInt.from(10).pow(-shift));
    }
  }

  /// Converts a finite [num] via its shortest exact decimal string spelling.
  factory ExactDecimal.fromNum(num value) {
    if (value is int) return ExactDecimal.fromInt(value);
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Must be finite');
    }
    if (value == 0) return zero;
    return ExactDecimal.parse(value.toString());
  }

  bool get isZero => numerator == BigInt.zero;
  bool get isNegative => numerator.isNegative;
  bool get isPositive => numerator > BigInt.zero;

  ExactDecimal abs() =>
      isNegative ? ExactDecimal._raw(-numerator, denominator) : this;

  ExactDecimal operator -() =>
      isZero ? zero : ExactDecimal._raw(-numerator, denominator);

  ExactDecimal operator +(ExactDecimal other) {
    if (isZero) return other;
    if (other.isZero) return this;
    if (denominator == other.denominator) {
      return ExactDecimal(numerator + other.numerator, denominator);
    }
    return ExactDecimal(
      numerator * other.denominator + other.numerator * denominator,
      denominator * other.denominator,
    );
  }

  ExactDecimal operator -(ExactDecimal other) {
    if (other.isZero) return this;
    if (isZero) return -other;
    if (denominator == other.denominator) {
      return ExactDecimal(numerator - other.numerator, denominator);
    }
    return ExactDecimal(
      numerator * other.denominator - other.numerator * denominator,
      denominator * other.denominator,
    );
  }

  ExactDecimal operator *(ExactDecimal other) {
    if (isZero || other.isZero) return zero;
    return ExactDecimal(
      numerator * other.numerator,
      denominator * other.denominator,
    );
  }

  ExactDecimal operator /(ExactDecimal other) {
    if (other.isZero) throw ArgumentError('Division by zero');
    if (isZero) return zero;
    return ExactDecimal(
      numerator * other.denominator,
      denominator * other.numerator,
    );
  }

  @override
  int compareTo(ExactDecimal other) {
    if (denominator == other.denominator) {
      return numerator.compareTo(other.numerator);
    }
    return (numerator * other.denominator).compareTo(
      other.numerator * denominator,
    );
  }

  bool operator <(ExactDecimal other) => compareTo(other) < 0;
  bool operator <=(ExactDecimal other) => compareTo(other) <= 0;
  bool operator >(ExactDecimal other) => compareTo(other) > 0;
  bool operator >=(ExactDecimal other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is ExactDecimal &&
      numerator == other.numerator &&
      denominator == other.denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  ExactDecimal clamp(ExactDecimal min, ExactDecimal max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }

  /// Rounds to an integer using ROUND_HALF_UP (half away from zero).
  BigInt roundHalfAwayInt() {
    if (isZero) return BigInt.zero;
    final absN = numerator.abs();
    var q = absN ~/ denominator;
    final r = absN % denominator;
    if (r * BigInt.two >= denominator) {
      q += BigInt.one;
    }
    return isNegative ? -q : q;
  }

  /// Rounds to [scale] decimal places using ROUND_HALF_UP (half away from zero).
  ExactDecimal roundHalfAway({int scale = 2}) {
    if (scale < 0) {
      throw ArgumentError.value(scale, 'scale', 'Must be non-negative');
    }
    if (isZero) return zero;
    final factor = BigInt.from(10).pow(scale);
    final scaled = ExactDecimal(numerator * factor, denominator);
    final rounded = scaled.roundHalfAwayInt();
    return ExactDecimal(rounded, factor);
  }

  /// Rounds to 2 decimal places (paise) using ROUND_HALF_UP.
  ExactDecimal roundMoney() => roundHalfAway(scale: 2);

  /// Rounds to the nearest multiple of [increment] (half away from zero).
  ExactDecimal roundNearestToMultiple(ExactDecimal increment) {
    if (!increment.isPositive) {
      throw ArgumentError.value(increment, 'increment', 'Must be positive');
    }
    if (isZero) return zero;
    final q = (this / increment).roundHalfAwayInt();
    return ExactDecimal.fromBigInt(q) * increment;
  }

  /// Rounds magnitude away from zero to a multiple of [increment]
  /// (exact multiples unchanged), preserving sign.
  ExactDecimal roundUpToMultiple(ExactDecimal increment) {
    if (!increment.isPositive) {
      throw ArgumentError.value(increment, 'increment', 'Must be positive');
    }
    if (isZero) return zero;
    final ratio = this / increment;
    final absN = ratio.numerator.abs();
    var q = absN ~/ ratio.denominator;
    final r = absN % ratio.denominator;
    if (r > BigInt.zero) {
      q += BigInt.one;
    }
    final signedQ = ratio.isNegative ? -q : q;
    return ExactDecimal.fromBigInt(signedQ) * increment;
  }

  /// Rounds magnitude toward zero to a multiple of [increment]
  /// (exact multiples unchanged), preserving sign.
  ExactDecimal roundDownToMultiple(ExactDecimal increment) {
    if (!increment.isPositive) {
      throw ArgumentError.value(increment, 'increment', 'Must be positive');
    }
    if (isZero) return zero;
    final ratio = this / increment;
    final absN = ratio.numerator.abs();
    final q = absN ~/ ratio.denominator;
    final signedQ = ratio.isNegative ? -q : q;
    return ExactDecimal.fromBigInt(signedQ) * increment;
  }

  /// Exact integer paise (rounded half away from zero to 2 decimal places).
  BigInt toPaise() {
    if (isZero) return BigInt.zero;
    final scaled = ExactDecimal(numerator * BigInt.from(100), denominator);
    return scaled.roundHalfAwayInt();
  }

  /// Fixed-scale decimal string (never produces `-0.00`).
  String toFixed(int scale) {
    if (scale < 0) {
      throw ArgumentError.value(scale, 'scale', 'Must be non-negative');
    }
    final factor = BigInt.from(10).pow(scale);
    final scaled = ExactDecimal(numerator * factor, denominator);
    final rounded = scaled.roundHalfAwayInt();
    if (rounded == BigInt.zero) {
      return scale == 0 ? '0' : '0.${'0' * scale}';
    }
    final sign = rounded.isNegative ? '-' : '';
    final mag = rounded.abs();
    if (scale == 0) return '$sign$mag';
    final whole = mag ~/ factor;
    final frac = (mag % factor).toString().padLeft(scale, '0');
    return '$sign$whole.$frac';
  }

  /// Rounded money value as a `double` (parsed from exact 2-decimal string so
  /// it is the closest IEEE-754 representation to the exact decimal).
  double toMoneyDouble() => double.parse(toFixed(2));

  /// Full-precision double approximation of this rational.
  double toDouble() {
    if (isZero) return 0.0;
    return numerator / denominator;
  }

  @override
  String toString() =>
      denominator == BigInt.one ? '$numerator' : '$numerator/$denominator';
}
