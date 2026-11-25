import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/customer.dart';
import '../models/product.dart';

/// Home's literal search contract; phone punctuation is special only when the
/// entire query is phone-shaped, never for text containing a few digits.
class HomeSearchQuery {
  final String text;
  final String? phoneDigits;
  HomeSearchQuery._(this.text, this.phoneDigits);
  factory HomeSearchQuery(String raw) {
    final normalized = String.fromCharCodes(raw.trim().runes.take(60));
    return HomeSearchQuery._(normalized.toLowerCase(), _phone(normalized));
  }

  static String? _phone(String value) =>
      RegExp(r'^[+0-9 ()\.\-]+$').hasMatch(value) &&
          RegExp(r'[0-9]').hasMatch(value)
      ? value.replaceAll(RegExp(r'[^0-9]'), '')
      : null;

  bool _contains(String? value) =>
      text.isNotEmpty && (value?.toLowerCase().contains(text) ?? false);
  bool _phoneMatches(String? value) =>
      phoneDigits != null &&
      (value?.replaceAll(RegExp(r'[^0-9]'), '').contains(phoneDigits!) ??
          false);

  bool product(Product product, {bool allowSupplier = true}) =>
      _contains(product.name) ||
      _contains(product.itemCode) ||
      _contains(product.barcode) ||
      _contains(product.category) ||
      (allowSupplier && _contains(product.supplier));
  bool bill(Bill bill) =>
      _contains(bill.billNumber) ||
      _contains(
        bill.billNumber.replaceFirst(RegExp(r'^SHOP-LOCAL-local-'), 'INV-'),
      ) ||
      _contains(bill.customerName) ||
      _contains(bill.customerPhone) ||
      _phoneMatches(bill.customerPhone);
  bool customer(Customer customer) =>
      _contains(customer.name) ||
      _contains(customer.phone) ||
      _phoneMatches(customer.phone) ||
      _contains(customer.gstin) ||
      _contains(customer.address);
}

Future<bool> isCurrentHomeSearchScope(CheckoutScope expected) async {
  final current = await DatabaseHelper.instance.captureCheckoutScope();
  return current.shopId == expected.shopId &&
      current.owner == expected.owner &&
      current.deviceId == expected.deviceId;
}
