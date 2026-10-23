import 'package:intl/intl.dart';

import '../models/bill.dart';
import '../utils/money.dart';

/// WhatsApp payment reminders for customer dues (udhaar).
class DuesReminder {
  /// The reminder text, sent from the shop's own WhatsApp.
  static String message({
    required String customerName,
    required String shopName,
    required List<Bill> unpaidBills,
    String upiId = '',
  }) {
    final due = unpaidBills.fold<double>(0, (sum, b) => sum + b.balanceDue);
    final oldest = unpaidBills.isEmpty
        ? null
        : unpaidBills
              .map((b) => b.createdAt)
              .reduce((a, b) => a.isBefore(b) ? a : b);
    final count = unpaidBills.length;
    final buffer = StringBuffer()
      ..writeln('Namaste $customerName,')
      ..writeln()
      ..write('This is a gentle reminder from $shopName. ')
      ..write('Your pending amount is ${rupees(due)}')
      ..write(' on $count bill${count == 1 ? '' : 's'}');
    if (oldest != null) {
      buffer.write(' (since ${DateFormat('dd MMM yyyy').format(oldest)})');
    }
    buffer.writeln('.');
    if (upiId.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Pay by UPI: ${upiId.trim()}');
    }
    buffer
      ..writeln()
      ..write('Thank you!');
    return buffer.toString();
  }

  /// wa.me link for an Indian number (adds 91 to 10-digit numbers), or null
  /// when there is no usable phone number.
  static Uri? whatsAppLink(String? phone, String text) {
    final digits = phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    if (digits.isEmpty || digits == '91') return null;
    final number = digits.length == 10 ? '91$digits' : digits;
    return Uri.https('wa.me', '/$number', {'text': text});
  }
}
