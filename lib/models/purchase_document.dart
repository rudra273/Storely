import 'dart:convert';

/// Four-place stock decimals, allowing only insignificant double representation drift.
String purchaseDecimal(num value) {
  if (!value.isFinite || value < 0 || value > 9999999999.9999) {
    throw ArgumentError(
      'Purchase values must be non-negative finite decimals.',
    );
  }
  if (value == 0) return '0';
  final fixed = value.toStringAsFixed(4);
  if ((value - double.parse(fixed)).abs() > 0.0000001) {
    throw ArgumentError(
      'Use up to four decimal places for purchase quantities and costs.',
    );
  }
  return normalizePurchaseDecimal(fixed);
}

String normalizePurchaseDecimal(String value) {
  if (!RegExp(r'^\d+(\.\d{1,4})?$').hasMatch(value)) {
    throw const FormatException('Invalid purchase decimal');
  }
  final parts = value.split('.');
  final whole = BigInt.parse(parts[0]).toString();
  final fraction = parts.length == 1
      ? ''
      : parts[1].replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

BigInt purchaseLineCents(String quantity, String cost) {
  BigInt scaled(String text) {
    final parts = normalizePurchaseDecimal(text).split('.');
    return BigInt.parse(parts[0]) * BigInt.from(10000) +
        BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(4, '0'));
  }

  return (scaled(quantity) * scaled(cost) + BigInt.from(500000)) ~/
      BigInt.from(1000000);
}

String purchaseCentsText(BigInt value) =>
    '${value ~/ BigInt.from(100)}.${(value % BigInt.from(100)).toString().padLeft(2, '0')}';

String purchaseMoney(String value) {
  final normalized = normalizePurchaseDecimal(value).split('.');
  var whole = normalized[0];
  final groups = <String>[];
  if (whole.length > 3) {
    groups.insert(0, whole.substring(whole.length - 3));
    whole = whole.substring(0, whole.length - 3);
    while (whole.length > 2) {
      groups.insert(0, whole.substring(whole.length - 2));
      whole = whole.substring(0, whole.length - 2);
    }
  }
  groups.insert(0, whole);
  return '₹${groups.join(',')}.${(normalized.length == 1 ? '' : normalized[1]).padRight(2, '0')}';
}

/// Immutable document snapshot. Applying one never creates stock movements.
class PurchaseDocument {
  final Map<String, dynamic> _json;
  final String syncState;
  final String? syncError;

  PurchaseDocument.fromJson(
    Map<String, dynamic> value, {
    this.syncState = 'synced',
    this.syncError,
  }) : _json = Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map) {
    for (final key in ['uuid', 'purchase_date', 'created_at', 'subtotal']) {
      if (_json[key] is! String) throw FormatException('Missing purchase $key');
    }
    if (_json['items'] is! List || (_json['items'] as List).isEmpty) {
      throw const FormatException('Purchase needs line snapshots');
    }
    normalizePurchaseDecimal(subtotal);
    for (final line in items) {
      for (final key in [
        'uuid',
        'movement_uuid',
        'product_uuid',
        'product_name',
        'quantity',
        'unit_cost',
        'amount',
      ]) {
        if (line[key] is! String) {
          throw FormatException('Missing purchase line $key');
        }
      }
      normalizePurchaseDecimal(line['quantity'] as String);
      normalizePurchaseDecimal(line['unit_cost'] as String);
      normalizePurchaseDecimal(line['amount'] as String);
    }
  }

  String get uuid => _json['uuid'] as String;
  String get date => _json['purchase_date'] as String;
  String get createdAt => _json['created_at'] as String;
  String get subtotal => _json['subtotal'] as String;
  String get origin => _json['origin']?.toString() ?? 'web';
  String? get supplier => _json['supplier_name'] as String?;
  int get sequence => (_json['change_sequence'] as num?)?.toInt() ?? 0;
  List<Map<String, dynamic>> get items => [
    for (final row in _json['items'] as List)
      Map<String, dynamic>.from(row as Map),
  ];
  Map<String, dynamic> toJson() =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(_json)) as Map);

  bool sameBusinessContent(PurchaseDocument other) {
    Map<String, dynamic> canonical(PurchaseDocument document) {
      final raw = document.toJson();
      return {
        for (final key in [
          'uuid',
          'purchase_date',
          'supplier_uuid',
          'supplier_name',
          'invoice_number',
          'notes',
          'origin',
        ])
          key: raw[key],
        'device_created_at': DateTime.parse(
          (raw['device_created_at'] ?? raw['created_at']) as String,
        ).toUtc().toIso8601String(),
        'subtotal': normalizePurchaseDecimal(document.subtotal),
        'items': [
          for (final row in document.items)
            {
              for (final key in [
                'uuid',
                'movement_uuid',
                'product_uuid',
                'product_name',
                'unit_name',
                'batch_no',
                'expiry_date',
                'line_number',
              ])
                key: row[key],
              for (final key in ['quantity', 'unit_cost', 'amount'])
                key: normalizePurchaseDecimal(row[key] as String),
            },
        ],
      };
    }

    return jsonEncode(canonical(this)) == jsonEncode(canonical(other));
  }
}
