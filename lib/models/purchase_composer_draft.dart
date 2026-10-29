import 'product.dart';
import 'purchase_document.dart';

/// A complete local snapshot; UUID, never a SQLite row ID, identifies a restock.
class PurchaseDraftLine {
  final Product product;
  final double quantityAdded;
  final Product? restockTarget;
  const PurchaseDraftLine({
    required this.product,
    required this.quantityAdded,
    this.restockTarget,
  });
  String get name => product.name;
  bool get isRestock => restockTarget != null;

  static Map<String, dynamic> productJson(Product p) => {
    ...p.toMap(),
    'category': p.category,
    'supplier': p.supplier,
    'unit': p.unit,
    'purchase_batch_no': p.purchaseBatchNo,
    'purchase_expiry': p.purchaseExpiry?.toIso8601String(),
  };
  static Product productFromJson(Map<String, dynamic> p) =>
      Product.fromMap(p).copyWith(
        purchaseBatchNo: p['purchase_batch_no'] as String?,
        purchaseExpiry: DateTime.tryParse(
          p['purchase_expiry']?.toString() ?? '',
        ),
      );
  Map<String, dynamic> toJson() => {
    'product': productJson(product),
    'quantity_added': purchaseDecimal(quantityAdded),
    'restock_target': restockTarget == null
        ? null
        : productJson(restockTarget!),
  };
  factory PurchaseDraftLine.fromJson(Map<String, dynamic> json) =>
      PurchaseDraftLine(
        product: productFromJson(
          Map<String, dynamic>.from(json['product'] as Map),
        ),
        quantityAdded: double.parse(json['quantity_added'] as String),
        restockTarget: json['restock_target'] == null
            ? null
            : productFromJson(
                Map<String, dynamic>.from(json['restock_target'] as Map),
              ),
      );
}

class PurchaseComposerDraft {
  final String uuid;
  final String shopId;
  final int revision;
  final DateTime date;
  final String? supplier;
  final List<PurchaseDraftLine> lines;
  final List<Product> importedRows;
  const PurchaseComposerDraft({
    required this.uuid,
    required this.shopId,
    required this.revision,
    required this.date,
    this.supplier,
    this.lines = const [],
    this.importedRows = const [],
  });
  PurchaseComposerDraft copyWith({
    int? revision,
    DateTime? date,
    String? supplier,
    bool clearSupplier = false,
    List<PurchaseDraftLine>? lines,
    List<Product>? importedRows,
  }) => PurchaseComposerDraft(
    uuid: uuid,
    shopId: shopId,
    revision: revision ?? this.revision,
    date: date ?? this.date,
    supplier: clearSupplier ? null : supplier ?? this.supplier,
    lines: lines ?? this.lines,
    importedRows: importedRows ?? this.importedRows,
  );
  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'supplier': supplier,
    'lines': [for (final line in lines) line.toJson()],
    'imported_rows': [
      for (final row in importedRows) PurchaseDraftLine.productJson(row),
    ],
  };
  factory PurchaseComposerDraft.fromRow(
    Map<String, dynamic> row,
    Map<String, dynamic> payload,
  ) => PurchaseComposerDraft(
    uuid: row['uuid'] as String,
    shopId: row['shop_id'] as String,
    revision: row['revision'] as int,
    date: DateTime.parse(payload['date'] as String),
    supplier: payload['supplier'] as String?,
    lines: [
      for (final line in payload['lines'] as List)
        PurchaseDraftLine.fromJson(Map<String, dynamic>.from(line as Map)),
    ],
    importedRows: [
      for (final p in payload['imported_rows'] as List)
        PurchaseDraftLine.productFromJson(Map<String, dynamic>.from(p as Map)),
    ],
  );
}
