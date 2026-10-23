import 'package:intl/intl.dart';

final _rupees2 = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);
final _rupees0 = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 0,
);

/// Indian rupee amount with lakh/crore grouping: ₹1,23,456.00.
/// [decimals] is 2 (default) or 0 for compact lists.
String rupees(num value, {int decimals = 2}) {
  final format = decimals == 0 ? _rupees0 : _rupees2;
  final text = format.format(value.abs());
  // Avoid "-₹0.00" for values that round to zero.
  final isNegative = value < 0 && text != format.format(0);
  return isNegative ? '-$text' : text;
}

/// "+₹0.40" / "-₹0.40" for small signed adjustments like round-off.
String signedRupees(num value) =>
    '${value < 0 ? '-' : '+'}${rupees(value.abs())}';

const _ones = [
  '',
  'One',
  'Two',
  'Three',
  'Four',
  'Five',
  'Six',
  'Seven',
  'Eight',
  'Nine',
  'Ten',
  'Eleven',
  'Twelve',
  'Thirteen',
  'Fourteen',
  'Fifteen',
  'Sixteen',
  'Seventeen',
  'Eighteen',
  'Nineteen',
];
const _tens = [
  '',
  '',
  'Twenty',
  'Thirty',
  'Forty',
  'Fifty',
  'Sixty',
  'Seventy',
  'Eighty',
  'Ninety',
];

String _belowHundred(int n) {
  if (n < 20) return _ones[n];
  final rest = n % 10;
  return rest == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]} ${_ones[rest]}';
}

String _belowThousand(int n) {
  final hundreds = n ~/ 100;
  final rest = n % 100;
  return [
    if (hundreds > 0) '${_ones[hundreds]} Hundred',
    if (rest > 0) _belowHundred(rest),
  ].join(' ');
}

/// Whole number in the Indian system: crore, lakh, thousand, hundred.
String _indianWords(int n) {
  if (n == 0) return 'Zero';
  final parts = <String>[];
  final crore = n ~/ 10000000;
  n %= 10000000;
  final lakh = n ~/ 100000;
  n %= 100000;
  final thousand = n ~/ 1000;
  n %= 1000;
  if (crore > 0) parts.add('${_indianWords(crore)} Crore');
  if (lakh > 0) parts.add('${_belowHundred(lakh)} Lakh');
  if (thousand > 0) parts.add('${_belowHundred(thousand)} Thousand');
  if (n > 0) parts.add(_belowThousand(n));
  return parts.join(' ');
}

/// Invoice "amount in words": Rupees One Lakh Twenty Thousand and Fifty
/// Paise Only.
String amountInWords(num amount) {
  final paiseTotal = (amount.abs() * 100).round();
  final rupeesPart = paiseTotal ~/ 100;
  final paise = paiseTotal % 100;
  final words = StringBuffer('Rupees ${_indianWords(rupeesPart)}');
  if (paise > 0) words.write(' and ${_belowHundred(paise)} Paise');
  words.write(' Only');
  return words.toString();
}
