import '../utils/decimal_text.dart';

/// Canonical payment methods accepted across billing checkout and settlement.
const List<String> checkoutPaymentMethods = [
  'cash',
  'upi',
  'card',
  'bank',
  'online',
];

/// Human-readable label for a canonical billing payment method code.
String paymentMethodLabel(String method) => switch (method) {
  'cash' => 'Cash',
  'upi' => 'UPI',
  'card' => 'Card',
  'bank' => 'Bank transfer',
  'online' => 'Online',
  _ => method.isEmpty ? 'Cash' : method,
};

/// Normalizes persisted/raw payment method values to a canonical code.
String normalizeCheckoutPaymentMethod(Object? raw) =>
    raw is String && checkoutPaymentMethods.contains(raw) ? raw : 'cash';

/// Counter-only change due in paise when [cashText] parses as a valid
/// 2-decimal amount strictly above [totalPaise]; otherwise null.
BigInt? checkoutChangePaise({
  required String cashText,
  required BigInt totalPaise,
}) {
  final trimmed = cashText.trim();
  if (!RegExp(r'^\d{1,30}(?:\.\d{1,2})?$').hasMatch(trimmed)) return null;
  final cashPaise = decimalScaledInteger(trimmed, scale: 2);
  if (cashPaise <= totalPaise) return null;
  return cashPaise - totalPaise;
}

/// Exact paise validation shared by checkout's preview and save boundary.
BigInt checkoutPaidPaise({
  required String? settlement,
  required String partialText,
  required BigInt totalPaise,
  required bool hasCustomer,
  required bool allowUnassignedCredit,
}) {
  if (!{'paid', 'partial', 'unpaid'}.contains(settlement)) {
    throw const FormatException('Choose full, partial or unpaid settlement.');
  }
  if (totalPaise < BigInt.zero || totalPaise > BigInt.from(99999999900)) {
    throw const FormatException(
      'Checkout total is outside the supported amount range.',
    );
  }
  BigInt paid;
  if (settlement == 'paid') {
    paid = totalPaise;
  } else if (settlement == 'unpaid') {
    paid = BigInt.zero;
  } else {
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(partialText.trim())) {
      throw const FormatException(
        'Enter a valid partial amount with at most two decimal places.',
      );
    }
    try {
      paid = decimalScaledInteger(partialText, scale: 2);
    } on FormatException {
      throw const FormatException(
        'Enter a valid partial amount with at most two decimal places.',
      );
    }
    if (paid <= BigInt.zero || paid >= totalPaise) {
      throw const FormatException(
        'Partial amount must be greater than zero and less than the total.',
      );
    }
  }
  if (paid < totalPaise && !hasCustomer && !allowUnassignedCredit) {
    throw const FormatException(
      'Confirm keeping this balance unassigned or select a customer.',
    );
  }
  return paid;
}
