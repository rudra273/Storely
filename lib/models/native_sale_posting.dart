import 'dart:convert';

import '../utils/decimal_text.dart';
import 'bill.dart';

/// Maps only a supported immutable checkout capture. Null leaves the capture
/// untouched for explicit review; this never consults or reprices the catalog.
Map<String, dynamic>? nativeSaleRequest(String snapshot) {
  try {
    return _request(jsonDecode(snapshot));
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  } on ArgumentError {
    return null;
  }
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
Never _unsupported() => throw const FormatException('Unsupported native sale');
Map<String, dynamic> _map(dynamic value) =>
    value is Map<String, dynamic> ? value : _unsupported();
List<Map<String, dynamic>> _rows(dynamic value) =>
    value is List ? value.map(_map).toList() : _unsupported();
String _text(dynamic value, int max) =>
    value is String && value.isNotEmpty && value.length <= max
    ? value
    : _unsupported();
String _uuid(dynamic value) {
  final text = _text(value, 36);
  if (!_uuidPattern.hasMatch(text)) _unsupported();
  return text;
}

BigInt _scaled(dynamic value, int scale, {BigInt? max, bool signed = false}) {
  if (value is! num && value is! String) _unsupported();
  final scaled = decimalScaledInteger(value.toString(), scale: scale);
  if ((!signed && scaled.isNegative) || (max != null && scaled.abs() > max)) {
    _unsupported();
  }
  return scaled;
}

String _money(BigInt value) =>
    decimalTextFromScaled(value, scale: 2, fixed: true);
BigInt _amount(dynamic value) =>
    _scaled(value, 2, max: BigInt.from(10).pow(20) - BigInt.one);
String? _optional(dynamic value, int max) =>
    value == null ? null : _text(value, max);
String? _snapshotText(Map<String, dynamic> row, String field, int max) {
  if (!row.containsKey(field)) _unsupported();
  final value = row[field];
  if (value == null) return null;
  if (value is! String || value.isEmpty || value.runes.length > max) {
    _unsupported();
  }
  return value;
}

/// Round SQLite REAL values from their shortest decimal spelling so binary
/// residue does not flip a decimal half tie.
String _snapshotDecimal(dynamic value, {bool signed = false}) {
  if (value is! num ||
      !value.isFinite ||
      value.abs() > 999999999 ||
      (!signed && value < 0)) {
    _unsupported();
  }
  final parts = RegExp(
    r'^(-?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$',
  ).firstMatch(value.toString());
  if (parts == null) _unsupported();
  final fraction = parts.group(3) ?? '';
  final magnitude = BigInt.parse('${parts.group(2)}$fraction');
  final shift = 9 + int.parse(parts.group(4) ?? '0') - fraction.length;
  BigInt rounded;
  if (shift >= 0) {
    rounded = magnitude * BigInt.from(10).pow(shift);
  } else {
    final divisor = BigInt.from(10).pow(-shift);
    rounded = magnitude ~/ divisor;
    if ((magnitude % divisor) * BigInt.two >= divisor) rounded += BigInt.one;
  }
  if (parts.group(1) == '-') rounded = -rounded;
  return decimalTextFromScaled(rounded, scale: 9, fixed: true);
}

Map<String, dynamic> _lineSnapshot(Map<String, dynamic> row) => {
  'hsn_code_snapshot': _snapshotText(row, 'hsn_code_snapshot', 20),
  'hsn_type_snapshot': _snapshotText(row, 'hsn_type_snapshot', 20),
  'unit_name': _snapshotText(row, 'unit_name', 30),
  'purchase_price_snapshot': _snapshotDecimal(row['purchase_price_snapshot']),
  'cost_snapshot': _snapshotDecimal(row['cost_snapshot']),
  'profit_snapshot': _snapshotDecimal(row['profit_snapshot'], signed: true),
};

void _sameRow(Map<String, dynamic> row, String shop) {
  if (row['shop_id'] != shop || row['deleted_at'] != null) _unsupported();
}

Map<String, dynamic> _request(dynamic decoded) {
  final capture = _map(decoded);
  if (capture['version'] != 1) _unsupported();
  final invoice = _map(capture['invoice']);
  final shop = _text(invoice['shop_id'], 128);
  _sameRow(invoice, shop);
  final invoiceUuid = _uuid(invoice['uuid']);
  final identities = <String>{invoiceUuid.toLowerCase()};
  String identity(dynamic value) {
    final uuid = _uuid(value);
    if (!identities.add(uuid.toLowerCase())) _unsupported();
    return uuid;
  }

  final device = _text(capture['device_id'], 64);
  if (device.length < 8 ||
      (invoice['device_id'] != null && invoice['device_id'] != device) ||
      invoice['document_type'] != 'invoice' ||
      invoice['lifecycle_status'] != 'finalized' ||
      invoice['cancelled_at'] != null ||
      invoice['original_bill_uuid'] != null ||
      invoice['duplicated_from_bill_uuid'] != null ||
      _amount(invoice['profit_commission_percent']) != BigInt.zero) {
    _unsupported();
  }
  final created = _text(invoice['created_at'], 40);
  if (!RegExp(
        r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?$',
      ).hasMatch(created) ||
      DateTime.tryParse(created) == null ||
      DateTime.parse(created).toIso8601String().substring(0, 19) !=
          created.substring(0, 19)) {
    _unsupported();
  }
  final items = _rows(capture['items']);
  final movements = _rows(capture['movements']);
  final payments = _rows(capture['payments']);
  if (items.isEmpty || items.length > 200 || movements.length != items.length) {
    _unsupported();
  }
  final movementByProduct = <String, Map<String, dynamic>>{};
  for (final movement in movements) {
    _sameRow(movement, shop);
    final product = _uuid(movement['product_uuid']);
    if (movementByProduct.containsKey(product) ||
        movement['source_document_uuid'] != invoiceUuid ||
        movement['source_document_type'] != 'bill' ||
        movement['source_type'] != 'bill' ||
        movement['movement_type'] != 'sale') {
      _unsupported();
    }
    movementByProduct[product] = movement;
  }
  final billDiscountMode = invoice['discount_mode'] ?? 'percent';
  if (billDiscountMode != 'percent' && billDiscountMode != 'amount') {
    _unsupported();
  }
  final billTaxMode = invoice['tax_mode'] ?? 'inclusive';
  if (billTaxMode != 'inclusive' && billTaxMode != 'exclusive') {
    _unsupported();
  }
  final roundOffMode = invoice['round_off_mode'] ?? 'nearest';
  if (!{'none', 'nearest', 'up', 'down'}.contains(roundOffMode)) {
    _unsupported();
  }
  final roundOffIncrement = invoice['round_off_increment'] == null
      ? BigInt.from(100)
      : _scaled(invoice['round_off_increment'], 2, max: BigInt.from(1000));
  if (!{
    BigInt.from(50),
    BigInt.from(100),
    BigInt.from(500),
    BigInt.from(1000),
  }.contains(roundOffIncrement)) {
    _unsupported();
  }
  var subtotal = BigInt.zero;
  var taxable = BigInt.zero;
  var tax = BigInt.zero;
  var exclusiveGst = BigInt.zero;
  var net = BigInt.zero;
  final products = <String>{};
  final cartItems = <Map<String, dynamic>>[];
  final lines = <Map<String, dynamic>>[];
  for (final row in items) {
    _sameRow(row, shop);
    final product = _uuid(row['product_uuid']);
    if (!products.add(product) ||
        row['bill_uuid'] != invoiceUuid ||
        row['original_item_uuid'] != null ||
        _amount(row['commission_snapshot']) != BigInt.zero) {
      _unsupported();
    }
    final quantity = _scaled(row['quantity'], 3, max: BigInt.from(1000000000));
    if (quantity == BigInt.zero) _unsupported();
    final lineDiscountMode = row['discount_mode'] ?? 'percent';
    if (lineDiscountMode != 'percent' && lineDiscountMode != 'amount') {
      _unsupported();
    }
    final lineDiscountValue = row['discount_value'] == null
        ? BigInt.zero
        : _scaled(
            row['discount_value'],
            2,
            max: lineDiscountMode == 'percent'
                ? BigInt.from(10000)
                : BigInt.from(10).pow(20) - BigInt.one,
          );
    if (row['discount_amount'] != null) {
      _amount(row['discount_amount']);
    }
    final lineTaxMode = row['tax_mode'];
    if (lineTaxMode != null &&
        lineTaxMode != 'inclusive' &&
        lineTaxMode != 'exclusive') {
      _unsupported();
    }
    for (final field in [
      'selling_price_snapshot',
      'taxable_value_snapshot',
      'gst_snapshot',
    ]) {
      final value = row[field];
      if (value is! num || !value.isFinite || value < 0) _unsupported();
    }
    final item = BillItem.fromMap(row);
    final lineSubtotal = _amount(item.subtotal);
    if (_amount(row['subtotal']) != lineSubtotal) _unsupported();
    final lineTaxable = _amount(item.totalTaxableValue);
    final lineTotal = _amount(item.lineAmount);
    final lineTax = _amount(item.totalGst);
    final movement = movementByProduct.remove(product);
    if (movement == null ||
        _scaled(movement['quantity_delta'], 3, signed: true) != -quantity) {
      _unsupported();
    }
    final effectiveLineTaxMode = (lineTaxMode as String?) ?? billTaxMode;
    subtotal += lineSubtotal;
    taxable += lineTaxable;
    tax += lineTax;
    if (effectiveLineTaxMode == 'exclusive') {
      exclusiveGst += lineTax;
    }
    net += lineTotal;
    cartItems.add({
      'product_uuid': product,
      'quantity': decimalTextFromScaled(quantity, scale: 3),
      if (lineDiscountMode != 'percent' || lineDiscountValue > BigInt.zero) ...{
        'discount_mode': lineDiscountMode,
        'discount_value': decimalTextFromScaled(lineDiscountValue, scale: 2),
      },
      'tax_mode': ?lineTaxMode,
    });
    lines.add({
      'line_uuid': identity(row['uuid']),
      'movement_uuid': identity(movement['uuid']),
      'product_uuid': product,
      'name': _text(row['product_name'], 200),
      'quantity': decimalTextFromScaled(quantity, scale: 3),
      'subtotal': _money(lineSubtotal),
      'taxable_amount': _money(lineTaxable),
      'tax_amount': _money(lineTax),
      'total_amount': _money(lineTotal),
      'snapshot': _lineSnapshot(row),
    });
  }
  if (movementByProduct.isNotEmpty) _unsupported();
  final header = <String, BigInt>{
    for (final field in [
      'discount_amount',
      'taxable_amount',
      'cgst_amount',
      'sgst_amount',
      'igst_amount',
      'total_amount',
      'paid_amount',
      'balance_due',
    ])
      field: _amount(invoice[field]),
    'subtotal': _amount(invoice['subtotal_amount']),
    'round_off_amount': _scaled(
      invoice['round_off_amount'],
      2,
      max: BigInt.from(1000),
      signed: true,
    ),
  };
  final roundOffAmount = header['round_off_amount']!;
  if (roundOffMode == 'none' && roundOffAmount != BigInt.zero) {
    _unsupported();
  }
  if (roundOffAmount.abs() > roundOffIncrement) {
    _unsupported();
  }
  if (roundOffMode == 'nearest' &&
      roundOffAmount.abs() * BigInt.two > roundOffIncrement) {
    _unsupported();
  }
  final discount = _scaled(
    invoice['discount_percent'],
    2,
    max: BigInt.from(10000),
  );
  final discountValue = invoice['discount_value'] == null
      ? (billDiscountMode == 'percent' ? discount : BigInt.zero)
      : _scaled(
          invoice['discount_value'],
          2,
          max: billDiscountMode == 'percent'
              ? BigInt.from(10000)
              : BigInt.from(10).pow(20) - BigInt.one,
        );
  if (subtotal != header['subtotal'] ||
      taxable != header['taxable_amount'] ||
      tax !=
          header['cgst_amount']! +
              header['sgst_amount']! +
              header['igst_amount']! ||
      subtotal - header['discount_amount']! != net - exclusiveGst ||
      taxable + tax != net ||
      net + header['round_off_amount']! != header['total_amount'] ||
      header['paid_amount']! + header['balance_due']! !=
          header['total_amount']) {
    _unsupported();
  }
  final paid = header['paid_amount']!;
  final balance = header['balance_due']!;
  final phone = _optional(invoice['customer_phone'], 20);
  final digits = phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  if (balance > BigInt.zero &&
      (invoice['customer_uuid'] == null ||
          !_uuidPattern.hasMatch(invoice['customer_uuid'] as String) ||
          digits.isEmpty ||
          digits == '91')) {
    _unsupported();
  }
  if (payments.length != (paid > BigInt.zero ? 1 : 0)) _unsupported();
  final method = _text(invoice['payment_method'], 20);
  if (!{'cash', 'upi', 'card', 'bank', 'online'}.contains(method)) {
    _unsupported();
  }
  String? paymentUuid;
  String? reference;
  if (payments.isNotEmpty) {
    final payment = payments.single;
    _sameRow(payment, shop);
    if (payment['bill_uuid'] != invoiceUuid ||
        _amount(payment['amount']) != paid ||
        payment['payment_method'] != method ||
        payment['notes'] != null ||
        payment['received_at'] != created) {
      _unsupported();
    }
    paymentUuid = identity(payment['uuid']);
    reference = _optional(payment['payment_reference'], 100);
    if (method == 'cash' && reference != null) _unsupported();
  }
  if (paid > BigInt.from(99999999900)) _unsupported();
  final billType = invoice['bill_type'];
  if (billType != 'b2c' && billType != 'b2b') _unsupported();
  final gstin = _optional(invoice['customer_gstin'], 15);
  final supplyState = _optional(invoice['place_of_supply_state_code'], 2);
  if ((gstin != null && !RegExp(r'^[0-9]{2}[A-Z0-9]{13}$').hasMatch(gstin)) ||
      (supplyState != null && !RegExp(r'^[0-9]{2}$').hasMatch(supplyState))) {
    _unsupported();
  }
  final cart = <String, dynamic>{
    'items': cartItems,
    'discount_percent': decimalTextFromScaled(discount, scale: 2),
    'discount_mode': billDiscountMode,
    'discount_value': decimalTextFromScaled(discountValue, scale: 2),
    'tax_mode': billTaxMode,
    'round_off_mode': roundOffMode,
    'round_off_increment': _money(roundOffIncrement),
    'bill_type': billType,
    'customer_name': _optional(invoice['customer_name'], 120),
    'customer_phone': phone,
    'customer_gstin': gstin,
    'customer_gst_legal_name': _optional(
      invoice['customer_gst_legal_name'],
      150,
    ),
    'customer_gst_trade_name': _optional(
      invoice['customer_gst_trade_name'],
      150,
    ),
    'customer_address': _optional(invoice['customer_address_snapshot'], 300),
    'place_of_supply_state_code': supplyState,
  };
  return {
    'invoice_uuid': invoiceUuid,
    'invoice_number': _text(invoice['bill_number'], 128),
    'device_id': device,
    'created_at': created,
    'cart': cart,
    'lines': lines,
    for (final entry in header.entries) entry.key: _money(entry.value),
    'payment_uuid': paymentUuid,
    'payment': {
      'amount': _money(paid),
      'method': method,
      'reference': reference,
    },
    'settlement_choice': balance == BigInt.zero
        ? 'full'
        : paid == BigInt.zero
        ? 'unpaid'
        : 'partial',
    'allow_unassigned_credit': false,
  };
}
