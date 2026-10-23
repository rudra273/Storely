/// Bill-number patterns, shared by the allocator (DB) and Bill Settings so a
/// pattern that saves is a pattern that allocates.
///
/// GST (CGST Rule 46(b)): an invoice number is at most 16 characters of
/// letters, digits, hyphen and slash, consecutive and unique within a
/// financial year (April-March).
class InvoiceNumbering {
  static const defaultTemplate = 'INV/{FY}/{SEQ}';
  static const defaultResetPeriod = 'financial_year';
  static const defaultPadding = 4;

  /// The pre-2.0 default (17 chars, daily reset). Shops still on it are moved
  /// to [defaultTemplate].
  static const legacyTemplate = 'INV-{YYYY}{MM}{DD}-{SEQ}';

  static const maxLength = 16;
  static const tokens = [
    '{FY}',
    '{YYYY}',
    '{YY}',
    '{MM}',
    '{DD}',
    '{SEQ}',
    '{DEVICE}',
  ];

  /// Financial year of [date] as "2526" for April 2025 - March 2026.
  static String financialYear(DateTime date) {
    final start = date.month >= 4 ? date.year : date.year - 1;
    final yy = (start % 100).toString().padLeft(2, '0');
    final next = ((start + 1) % 100).toString().padLeft(2, '0');
    return '$yy$next';
  }

  /// Worst-case device letter length assumed when checking pattern length.
  static const _longestDeviceCode = 'BB';

  /// [deviceCode] is this device's bill-number letter ('' for the shop's
  /// first device or a shop without cloud sync). Patterns without {DEVICE}
  /// get it right before the sequence, so two phones billing offline can
  /// never issue the same number: INV/2627/0001 vs INV/2627/B0001.
  static String format({
    required String template,
    required DateTime date,
    required int sequence,
    required int padding,
    required String deviceCode,
  }) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final withDevice = template.contains('{DEVICE}')
        ? template
        : template.replaceFirst('{SEQ}', '{DEVICE}{SEQ}');
    return withDevice
        .replaceAll('{DEVICE}', deviceCode)
        .replaceAll('{FY}', financialYear(date))
        .replaceAll('{YYYY}', year)
        .replaceAll('{YY}', year.substring(2))
        .replaceAll('{MM}', month)
        .replaceAll('{DD}', day)
        .replaceAll('{SEQ}', sequence.toString().padLeft(padding, '0'));
  }

  /// Sequence restarts whenever this key changes.
  static String resetKey(DateTime date, String? resetPeriod) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    switch (resetPeriod) {
      case 'never':
        return 'all';
      case 'monthly':
        return '$year$month';
      case 'financial_year':
        return 'FY${financialYear(date)}';
      case 'daily':
      default:
        return '$year$month$day';
    }
  }

  /// Returns a user-facing problem with the pattern, or null when it is
  /// valid. Length is checked with the longest device letter a shop can get.
  static String? validate({
    required String template,
    required int padding,
    required String resetPeriod,
    DateTime? sampleDate,
  }) {
    if (!template.contains('{SEQ}')) {
      return 'Pattern must include {SEQ}';
    }
    var literal = template;
    for (final token in tokens) {
      literal = literal.replaceAll(token, '');
    }
    if (literal.contains('{') || literal.contains('}')) {
      return 'Unknown token. Use ${tokens.join(', ')}';
    }
    if (!RegExp(r'^[A-Za-z0-9/-]*$').hasMatch(literal)) {
      return 'Use only letters, numbers, "-" and "/"';
    }

    bool has(String token) => template.contains(token);
    final hasYear = has('{YYYY}') || has('{YY}');
    final periodOk = switch (resetPeriod) {
      'daily' => has('{DD}') && has('{MM}') && (hasYear || has('{FY}')),
      'monthly' => has('{MM}') && (hasYear || has('{FY}')),
      'financial_year' => has('{FY}') || (has('{MM}') && hasYear),
      _ => true,
    };
    if (!periodOk) {
      final needs = switch (resetPeriod) {
        'daily' => '{DD}, {MM} and a year ({FY} or {YYYY})',
        'monthly' => '{MM} and a year ({FY} or {YYYY})',
        _ => '{FY}',
      };
      return 'With this reset the pattern needs $needs, '
          'otherwise numbers repeat';
    }

    // Longest number this pattern can produce at the configured padding.
    final sample = format(
      template: template,
      date: sampleDate ?? DateTime(2026, 12, 31),
      sequence: 1,
      padding: padding,
      deviceCode: _longestDeviceCode,
    );
    if (sample.length > maxLength) {
      return 'Too long: ${sample.length} characters (GST allows $maxLength)';
    }
    return null;
  }
}
