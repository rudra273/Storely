import 'product.dart';

class StockMovementType {
  static const purchase = 'purchase';
  static const sale = 'sale';
  static const adjustment = 'adjustment';
  static const returnIn = 'return';
  static const voidSale = 'void';
  static const stocktake = 'stocktake';
}

class StockMovement {
  final int? id;
  final String uuid;
  final String shopId;
  final int productId;
  final String productUuid;
  final String movementType;
  final double quantityDelta;
  final double? unitCost;
  final String? sourceType;
  final int? supplierId;
  final String? supplierUuid;
  final String? sourceDocumentType;
  final int? sourceDocumentId;
  final String? sourceDocumentUuid;
  final String? importBatchKey;
  final int? importRowNumber;
  final String? notes;
  final String? deviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const StockMovement({
    this.id,
    required this.uuid,
    required this.shopId,
    required this.productId,
    required this.productUuid,
    required this.movementType,
    required this.quantityDelta,
    this.unitCost,
    this.sourceType,
    this.supplierId,
    this.supplierUuid,
    this.sourceDocumentType,
    this.sourceDocumentId,
    this.sourceDocumentUuid,
    this.importBatchKey,
    this.importRowNumber,
    this.notes,
    this.deviceId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    final createdAt = DateTime.parse(map['created_at'] as String);
    return StockMovement(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      shopId: map['shop_id'] as String,
      productId: map['product_id'] as int,
      productUuid: map['product_uuid'] as String,
      movementType: map['movement_type'] as String,
      quantityDelta: (map['quantity_delta'] as num).toDouble(),
      unitCost: (map['unit_cost'] as num?)?.toDouble(),
      sourceType: map['source_type'] as String?,
      supplierId: map['supplier_id'] as int?,
      supplierUuid: map['supplier_uuid'] as String?,
      sourceDocumentType: map['source_document_type'] as String?,
      sourceDocumentId: map['source_document_id'] as int?,
      sourceDocumentUuid: map['source_document_uuid'] as String?,
      importBatchKey: map['import_batch_key'] as String?,
      importRowNumber: map['import_row_number'] as int?,
      notes: map['notes'] as String?,
      deviceId: map['device_id'] as String?,
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? createdAt,
      deletedAt: map['deleted_at'] == null
          ? null
          : DateTime.tryParse(map['deleted_at'] as String),
    );
  }
}

class ProductPurchaseSummary {
  final int productId;
  final DateTime? lastPurchaseDate;
  final double? lastPurchasePrice;
  final double totalPurchased;

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

class ProductPurchaseCommit {
  final Product product;
  final double quantityAdded;
  final Product? restockTarget;

  const ProductPurchaseCommit({
    required this.product,
    required this.quantityAdded,
    this.restockTarget,
  });
}
