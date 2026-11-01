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
