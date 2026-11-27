import 'dart:convert';

import '../utils/decimal_text.dart';

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
  return normalizeDecimalText(value, scale: 4);
}

BigInt purchaseLineCents(String quantity, String cost) {
  final scaledQuantity = decimalScaledInteger(
    normalizePurchaseDecimal(quantity),
    scale: 4,
  );
  final scaledCost = decimalScaledInteger(
    normalizePurchaseDecimal(cost),
    scale: 4,
  );
  return (scaledQuantity * scaledCost + BigInt.from(500000)) ~/
      BigInt.from(1000000);
}

String purchaseCentsText(BigInt value) =>
    decimalTextFromScaled(value, scale: 2, fixed: true);

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

class PurchaseDocumentItem {
  final String uuid;
  final String movementUuid;
  final String productUuid;
  final String productName;
  final String? unitName;
  final String quantity;
  final String unitCost;
  final String amount;
  final String? batchNo;
  final String? expiryDate;
  final int? lineNumber;
  final String returnedQuantity;
  final String returnableQuantity;

  const PurchaseDocumentItem({
    required this.uuid,
    required this.movementUuid,
    required this.productUuid,
    required this.productName,
    this.unitName,
    required this.quantity,
    required this.unitCost,
    required this.amount,
    this.batchNo,
    this.expiryDate,
    this.lineNumber,
    this.returnedQuantity = '0',
    required this.returnableQuantity,
  });

  factory PurchaseDocumentItem.fromJson(Map<String, dynamic> json) {
    final quantity = json['quantity'] as String;
    final returned = json['returned_quantity']?.toString() ?? '0';
    final returnable = json['returnable_quantity']?.toString() ?? quantity;
    return PurchaseDocumentItem(
      uuid: json['uuid'] as String,
      movementUuid: json['movement_uuid'] as String,
      productUuid: json['product_uuid'] as String,
      productName: json['product_name'] as String,
      unitName: json['unit_name'] as String?,
      quantity: quantity,
      unitCost: json['unit_cost'] as String,
      amount: json['amount'] as String,
      batchNo: json['batch_no'] as String?,
      expiryDate: json['expiry_date'] as String?,
      lineNumber: (json['line_number'] as num?)?.toInt(),
      returnedQuantity: normalizePurchaseDecimal(returned),
      returnableQuantity: normalizePurchaseDecimal(returnable),
    );
  }

  bool get hasReturnedQuantity =>
      decimalScaledInteger(
        normalizePurchaseDecimal(returnedQuantity),
        scale: 4,
      ) >
      BigInt.zero;

  bool get hasReturnableQuantity =>
      decimalScaledInteger(
        normalizePurchaseDecimal(returnableQuantity),
        scale: 4,
      ) >
      BigInt.zero;
}

class PurchaseReturnItemRecord {
  final String uuid;
  final String purchaseItemUuid;
  final String productUuid;
  final String productName;
  final String? unitName;
  final String quantity;
  final String unitCost;
  final String amount;
  final String movementUuid;

  const PurchaseReturnItemRecord({
    required this.uuid,
    required this.purchaseItemUuid,
    required this.productUuid,
    required this.productName,
    this.unitName,
    required this.quantity,
    required this.unitCost,
    required this.amount,
    required this.movementUuid,
  });

  factory PurchaseReturnItemRecord.fromJson(Map<String, dynamic> json) =>
      PurchaseReturnItemRecord(
        uuid: json['uuid']?.toString() ?? '',
        purchaseItemUuid: json['purchase_item_uuid']?.toString() ?? '',
        productUuid: json['product_uuid']?.toString() ?? '',
        productName: json['product_name']?.toString() ?? '',
        unitName: json['unit_name']?.toString(),
        quantity: normalizePurchaseDecimal(
          json['quantity']?.toString() ?? '0',
        ),
        unitCost: normalizePurchaseDecimal(
          json['unit_cost']?.toString() ?? '0',
        ),
        amount: normalizePurchaseDecimal(json['amount']?.toString() ?? '0'),
        movementUuid: json['movement_uuid']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'purchase_item_uuid': purchaseItemUuid,
    'product_uuid': productUuid,
    'product_name': productName,
    'unit_name': unitName,
    'quantity': quantity,
    'unit_cost': unitCost,
    'amount': amount,
    'movement_uuid': movementUuid,
  };
}

class PurchaseReturnRecord {
  final String uuid;
  final String purchaseUuid;
  final String? supplierUuid;
  final String? supplierName;
  final String returnNumber;
  final String returnDate;
  final String reason;
  final String subtotal;
  final String taxAmount;
  final String total;
  final String payableCredit;
  final String refundAmount;
  final String? refundMethod;
  final String createdAt;
  final List<PurchaseReturnItemRecord> items;

  const PurchaseReturnRecord({
    required this.uuid,
    required this.purchaseUuid,
    this.supplierUuid,
    this.supplierName,
    required this.returnNumber,
    required this.returnDate,
    required this.reason,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.payableCredit,
    required this.refundAmount,
    this.refundMethod,
    required this.createdAt,
    this.items = const [],
  });

  factory PurchaseReturnRecord.fromJson(Map<String, dynamic> json) =>
      PurchaseReturnRecord(
        uuid: json['uuid']?.toString() ?? '',
        purchaseUuid: json['purchase_uuid']?.toString() ?? '',
        supplierUuid: json['supplier_uuid']?.toString(),
        supplierName: json['supplier_name']?.toString(),
        returnNumber: json['return_number']?.toString() ?? '',
        returnDate: json['return_date']?.toString() ?? '',
        reason: json['reason']?.toString() ?? '',
        subtotal: normalizePurchaseDecimal(
          json['subtotal']?.toString() ?? '0',
        ),
        taxAmount: normalizePurchaseDecimal(
          json['tax_amount']?.toString() ?? '0',
        ),
        total: normalizePurchaseDecimal(json['total']?.toString() ?? '0'),
        payableCredit: normalizePurchaseDecimal(
          json['payable_credit']?.toString() ?? '0',
        ),
        refundAmount: normalizePurchaseDecimal(
          json['refund_amount']?.toString() ?? '0',
        ),
        refundMethod: json['refund_method']?.toString(),
        createdAt: json['created_at']?.toString() ?? '',
        items: [
          for (final row in json['items'] as List? ?? const [])
            PurchaseReturnItemRecord.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
        ],
      );

  Map<String, dynamic> toJson() => {
    'uuid': uuid,
    'purchase_uuid': purchaseUuid,
    'supplier_uuid': supplierUuid,
    'supplier_name': supplierName,
    'return_number': returnNumber,
    'return_date': returnDate,
    'reason': reason,
    'subtotal': subtotal,
    'tax_amount': taxAmount,
    'total': total,
    'payable_credit': payableCredit,
    'refund_amount': refundAmount,
    'refund_method': refundMethod,
    'created_at': createdAt,
    'items': [for (final item in items) item.toJson()],
  };
}

class SupplierBalanceSummary {
  final String confirmedBalance;
  final String pendingPaymentsTotal;
  final int failedPaymentsCount;
  final String projectedBalance;
  final int unrecordedReceiptsCount;
  final DateTime? lastSyncedAt;

  const SupplierBalanceSummary({
    required this.confirmedBalance,
    required this.pendingPaymentsTotal,
    required this.failedPaymentsCount,
    required this.projectedBalance,
    required this.unrecordedReceiptsCount,
    this.lastSyncedAt,
  });

  bool get hasPendingPayments =>
      decimalScaledInteger(pendingPaymentsTotal, scale: 2) > BigInt.zero;
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
      if (line['returned_quantity'] != null) {
        normalizePurchaseDecimal(line['returned_quantity'].toString());
      }
      if (line['returnable_quantity'] != null) {
        normalizePurchaseDecimal(line['returnable_quantity'].toString());
      }
    }
  }

  String get uuid => _json['uuid'] as String;
  String get date => _json['purchase_date'] as String;
  String get createdAt => _json['created_at'] as String;
  String get subtotal => _json['subtotal'] as String;
  String get paymentStatus =>
      _json['payment_status'] as String? ?? 'not_recorded';
  String? get total => _json['total'] as String?;
  String? get paidAmount => _json['paid_amount'] as String?;
  String? get balanceDue => _json['balance_due'] as String?;
  String get taxAmount => _json['tax_amount'] as String? ?? '0';
  String get chargesAmount => _json['charges_amount'] as String? ?? '0';
  String get discountAmount => _json['discount_amount'] as String? ?? '0';
  String? get dueDate => _json['due_date'] as String?;
  String? get invoiceNumber => _json['invoice_number'] as String?;
  String? get notes => _json['notes'] as String?;
  String? get supplierUuid => _json['supplier_uuid'] as String?;
  String? get reversedAt => _json['reversed_at'] as String?;
  String? get reversalReason => _json['reversal_reason'] as String?;
  String get returnedTotal => _json['returned_total']?.toString() ?? '0.00';
  List<PurchaseReturnRecord> get returns => [
    for (final row in _json['returns'] as List? ?? const [])
      PurchaseReturnRecord.fromJson(Map<String, dynamic>.from(row as Map)),
  ];
  List<Map<String, dynamic>> get payments => [
    for (final row in _json['payments'] as List? ?? [])
      Map<String, dynamic>.from(row as Map),
  ];
  String get origin => _json['origin']?.toString() ?? 'web';
  String? get supplier => _json['supplier_name'] as String?;
  int get sequence => (_json['change_sequence'] as num?)?.toInt() ?? 0;
  List<Map<String, dynamic>> get items => [
    for (final row in _json['items'] as List)
      Map<String, dynamic>.from(row as Map),
  ];
  List<PurchaseDocumentItem> get lineItems => [
    for (final row in items) PurchaseDocumentItem.fromJson(row),
  ];

  bool get isReversed => reversedAt != null && reversedAt!.trim().isNotEmpty;
  bool get isNotRecorded => paymentStatus == 'not_recorded';
  bool get hasReturnableItems =>
      !isReversed && lineItems.any((item) => item.hasReturnableQuantity);
  bool get canReverse => !isReversed;
  bool get canRecordPaymentTerms =>
      !isReversed &&
      isNotRecorded &&
      supplierUuid != null &&
      supplierUuid!.trim().isNotEmpty;
  bool get hasBalanceDue =>
      balanceDue != null &&
      decimalScaledInteger(
            normalizePurchaseDecimal(balanceDue!),
            scale: 4,
          ) >
          BigInt.zero;
  bool get canPaySupplier =>
      !isReversed &&
      supplierUuid != null &&
      supplierUuid!.trim().isNotEmpty &&
      hasBalanceDue;
  bool get hasReturnedTotal =>
      decimalScaledInteger(
        normalizePurchaseDecimal(returnedTotal),
        scale: 4,
      ) >
      BigInt.zero;
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
