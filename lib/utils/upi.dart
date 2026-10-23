/// UPI payment links (NPCI deep-link format) for invoice QR codes:
/// `upi://pay?pa=<vpa>&pn=<payee>&am=<amount>&cu=INR&tn=<note>&tr=<ref>`
class Upi {
  static final _vpa = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z][a-zA-Z0-9]{1,63}$');

  /// True for a well-formed UPI id such as sharmakirana@okicici.
  static bool isValidId(String value) => _vpa.hasMatch(value.trim());

  /// Payment link for [amount] (2 decimals). Every value is URL-encoded, so
  /// spaces or '&' in a shop name or note cannot break the link.
  static String paymentLink({
    required String upiId,
    required String payeeName,
    required double amount,
    String? note,
    String? reference,
  }) {
    final params = <String, String>{
      'pa': upiId.trim(),
      'pn': payeeName.trim().isEmpty ? upiId.trim() : payeeName.trim(),
      'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      if (note != null && note.trim().isNotEmpty) 'tn': note.trim(),
      if (reference != null && reference.trim().isNotEmpty)
        'tr': reference.trim(),
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'upi://pay?$query';
  }
}
