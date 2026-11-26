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

abstract interface class NativeBillingCommandSyncBackend {
  Future<bool> supportsNativeBillingCommands(CheckoutScope scope);

  Future<Map<String, dynamic>> postNativePayment(
    CheckoutScope scope,
    String commandId,
    String billUuid,
    Map<String, dynamic> request,
  );

  Future<Map<String, dynamic>> postNativeCancel(
    CheckoutScope scope,
    String commandId,
    String billUuid,
    Map<String, dynamic> request,
  );

  Future<Map<String, dynamic>> postNativeCreditNote(
    CheckoutScope scope,
    String commandId,
    String billUuid,
    Map<String, dynamic> request,
  );
}
