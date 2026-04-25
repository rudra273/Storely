class ProductPurchaseEntry {
  final int? id;
  final int productId;
  final DateTime purchaseDate;
  final int quantityAdded;
  final double purchasePrice;
  final String? supplier;
  final String? importBatchKey;
  final String source;
  final DateTime createdAt;

  const ProductPurchaseEntry({
    this.id,
    required this.productId,
    required this.purchaseDate,
    required this.quantityAdded,
    required this.purchasePrice,
    this.supplier,
    this.importBatchKey,
    required this.source,
    required this.createdAt,
  });

  factory ProductPurchaseEntry.fromMap(Map<String, dynamic> map) {
    return ProductPurchaseEntry(
      id: map['id'] as int?,
      productId: map['product_id'] as int,
      purchaseDate: DateTime.parse(map['purchase_date'] as String),
      quantityAdded: map['quantity_added'] as int,
      purchasePrice: (map['purchase_price'] as num).toDouble(),
      supplier: map['supplier'] as String?,
      importBatchKey: map['import_batch_key'] as String?,
      source: map['source'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class ProductPurchaseSummary {
  final int productId;
  final DateTime? lastPurchaseDate;
  final double? lastPurchasePrice;
  final int totalPurchased;

  const ProductPurchaseSummary({
    required this.productId,
    required this.lastPurchaseDate,
    required this.lastPurchasePrice,
    required this.totalPurchased,
  });
}

class ProductImportResult {
  final int added;
  final int updated;
  final bool possibleDuplicate;
  final bool duplicateOnDifferentDate;

  const ProductImportResult({
    required this.added,
    required this.updated,
    required this.possibleDuplicate,
    this.duplicateOnDifferentDate = false,
  });
}
