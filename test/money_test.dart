import 'package:flutter_test/flutter_test.dart';
import 'package:storely/utils/money.dart';

void main() {
  test('rupees uses Indian lakh/crore grouping', () {
    expect(rupees(0), '₹0.00');
    expect(rupees(1234.5), '₹1,234.50');
    expect(rupees(123456), '₹1,23,456.00');
    expect(rupees(12345678.9), '₹1,23,45,678.90');
    expect(rupees(1999.6, decimals: 0), '₹2,000');
    expect(rupees(-8.85), '-₹8.85');
    expect(rupees(-0.001), '₹0.00');
    expect(signedRupees(0.4), '+₹0.40');
    expect(signedRupees(-0.15), '-₹0.15');
  });

  test('amount in words follows the Indian system', () {
    expect(amountInWords(0), 'Rupees Zero Only');
    expect(amountInWords(177), 'Rupees One Hundred Seventy Seven Only');
    expect(amountInWords(1846), 'Rupees One Thousand Eight Hundred Forty Six Only');
    expect(
      amountInWords(125000.5),
      'Rupees One Lakh Twenty Five Thousand and Fifty Paise Only',
    );
    expect(
      amountInWords(23456789.05),
      'Rupees Two Crore Thirty Four Lakh Fifty Six Thousand Seven Hundred '
      'Eighty Nine and Five Paise Only',
    );
    expect(amountInWords(1000000000), 'Rupees One Hundred Crore Only');
  });
}
