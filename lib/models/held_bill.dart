import 'dart:convert';

import 'bill.dart';

/// A cart parked with "Hold" (or the auto-saved cart in progress).
class HeldBill {
  final int id;
  final String uuid;
  final bool readOnly;
  final String label;
  final List<BillItem> items;
  final DateTime createdAt;

  const HeldBill({
    required this.id,
    this.uuid = '',
    this.readOnly = false,
    required this.label,
    required this.items,
    required this.createdAt,
  });

  double get total => items.fold(0, (sum, item) => sum + item.subtotal);

  static String encodeItems(List<BillItem> items) =>
      jsonEncode([for (final item in items) item.toMap(0)]);

  static List<BillItem> decodeItems(String json) => [
    for (final map in jsonDecode(json) as List)
      BillItem.fromMap(Map<String, dynamic>.from(map as Map)),
  ];

  factory HeldBill.fromMap(Map<String, Object?> map) => HeldBill(
    id: map['id'] as int,
    uuid: map['uuid'] as String? ?? '',
    readOnly: map['read_only'] == 1,
    label: map['label'] as String,
    items: decodeItems(map['items_json'] as String),
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
