import '../../db/database_helper.dart';

abstract interface class NativeSaleSyncBackend {
  Future<bool> supportsNativeSale(CheckoutScope scope);

  Future<Map<String, dynamic>> postNativeSale(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  );

  Future<Map<String, dynamic>> inspectNativeSaleReconciliation(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  );

  Future<Map<String, dynamic>> reconcileNativeSale(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request, {
    required bool allowStockShortage,
    required bool acceptRecordedSnapshot,
    required String reason,
  });
}
