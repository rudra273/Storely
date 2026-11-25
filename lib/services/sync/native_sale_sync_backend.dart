import '../../db/database_helper.dart';

abstract interface class NativeSaleSyncBackend {
  Future<bool> supportsNativeSale(CheckoutScope scope);

  Future<Map<String, dynamic>> postNativeSale(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  );
}
