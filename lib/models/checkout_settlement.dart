import '../utils/decimal_text.dart';

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
