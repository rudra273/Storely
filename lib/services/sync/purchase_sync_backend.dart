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
