/// Separate from row sync: whole receipt snapshots are transferred atomically.
abstract interface class PurchaseSyncBackend {
  Future<Map<String, dynamic>> publishNativePurchase(
    String shopId,
    Map<String, dynamic> receipt,
  );
  Future<List<Map<String, dynamic>>> pullPurchaseDocuments(
    String shopId, {
    required int afterSequence,
    required int limit,
  });
}

/// Optional capability, separate so existing purchase-only backends stay compatible.
abstract interface class SupplierPaymentSyncBackend {
  Future<Map<String, dynamic>> publishSupplierPayment(
    String shopId,
    String supplierId,
    Map<String, dynamic> payment,
  );
}

/// Optional proof of an existing payment, using the same immutable request.
/// A key-only operation lookup cannot verify supplier/body binding.
abstract interface class SupplierPaymentRecoveryBackend {
  Future<SupplierPaymentRecovery> recoverSupplierPayment(
    String shopId,
    String supplierId,
    Map<String, dynamic> payment,
  );
}

/// Optional online purchase/supplier operations (reversals, payment terms,
/// debit-note returns, supplier statements).
abstract interface class PurchaseOperationsBackend {
  Future<Map<String, dynamic>> reversePurchase(
    String shopId,
    String receiptUuid, {
    required String reason,
  });

  Future<Map<String, dynamic>> recordPaymentTerms(
    String shopId,
    String receiptUuid,
    Map<String, Object?> payload,
  );

  Future<Map<String, dynamic>> previewPurchaseTerms(
    String shopId,
    Map<String, Object?> payload,
  );

  Future<Map<String, dynamic>> createPurchaseReturn(
    String shopId,
    String receiptUuid,
    Map<String, Object?> payload,
  );

  Future<Map<String, dynamic>> reverseSupplierPayment(
    String shopId,
    String supplierUuid,
    String paymentUuid, {
    required String reason,
  });

  Future<Map<String, dynamic>> fetchSupplierStatement(
    String shopId,
    String supplierUuid,
  );
}

enum SupplierPaymentRecoveryStatus { committed, notFound, unsupported }

class SupplierPaymentRecovery {
  final SupplierPaymentRecoveryStatus status;
  final String? uuid;

  const SupplierPaymentRecovery.committed(String this.uuid)
    : status = SupplierPaymentRecoveryStatus.committed;
  const SupplierPaymentRecovery.notFound()
    : status = SupplierPaymentRecoveryStatus.notFound,
      uuid = null;
  const SupplierPaymentRecovery.unsupported()
    : status = SupplierPaymentRecoveryStatus.unsupported,
      uuid = null;
}
