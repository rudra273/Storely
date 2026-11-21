/// Creation prefill is intentionally narrower than existing catalog lookup.
/// JSON labels and internal identifiers must never become new barcodes.
String? checkoutBarcodeCandidate(String raw) {
  if (RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(raw)) return null;
  final value = raw.trim();
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(value)) {
    return null;
  }
  if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value) ||
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    return null;
  }
  return value;
}
