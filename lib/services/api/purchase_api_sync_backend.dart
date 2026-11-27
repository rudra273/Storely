import '../sync/purchase_sync_backend.dart';
import '../sync/sync_backend.dart';
import 'api_client.dart';
import 'api_sync_backend.dart';
import 'server_capabilities.dart';

/// Preserves existing row sync; publishes document metadata only after stock upload.
class PurchaseApiSyncBackend extends ApiSyncBackend
    implements
        PurchaseSyncBackend,
        SupplierPaymentSyncBackend,
        SupplierPaymentRecoveryBackend,
        PurchaseOperationsBackend {
  PurchaseApiSyncBackend(super.api, {super.preferredShopId});

  @override
  Future<SupplierPaymentRecovery> recoverSupplierPayment(
    String shopId,
    String supplierId,
    Map<String, dynamic> payment,
  ) async {
    final capabilities = await ServerCapabilities.load(api, shopId);
    if (capabilities != null && !capabilities.supportsSupplierPaymentProof) {
      return const SupplierPaymentRecovery.unsupported();
    }
    Map<String, dynamic> result;
    try {
      result = await api.postJson(
        '/v1/shops/$shopId/suppliers/$supplierId/payments/recover',
        payment,
      );
    } on ApiException catch (error) {
      // Only a missing route/method on an older server permits exact replay.
      // A tenant/resource 404 or permission denial does not prove noncommit.
      if ((error.status == 404 && error.code == 'http_404') ||
          (error.status == 405 && error.code == 'http_405')) {
        return const SupplierPaymentRecovery.unsupported();
      }
      rethrow;
    }
    if (result['contract_version'] is! int ||
        result['contract_version'] != 1 ||
        !result.containsKey('uuid') ||
        !result.containsKey('request_binding_version')) {
      throw const FormatException('Unsupported payment recovery contract');
    }
    if (result['status'] == 'committed' &&
        result['uuid'] is String &&
        (result['uuid'] as String).trim().isNotEmpty &&
        result['uuid'] == (result['uuid'] as String).trim() &&
        result['request_binding_version'] is int &&
        {1, 2}.contains(result['request_binding_version'])) {
      return SupplierPaymentRecovery.committed(result['uuid'] as String);
    }
    if (result['status'] == 'not_found' &&
        result['uuid'] == null &&
        result['request_binding_version'] == null) {
      return const SupplierPaymentRecovery.notFound();
    }
    throw const FormatException('Invalid payment recovery proof');
  }

  @override
  Future<Map<String, dynamic>> publishSupplierPayment(
    String shopId,
    String supplierId,
    Map<String, dynamic> payment,
  ) async {
    final body = <String, dynamic>{
      ...payment,
      if (payment['purchase_uuid'] != null)
        'purchase_uuid': payment['purchase_uuid'],
      if (payment.containsKey('reference')) 'reference': payment['reference'],
      if (payment.containsKey('notes')) 'notes': payment['notes'],
    };
    try {
      return await api.postJson(
        '/v1/shops/$shopId/suppliers/$supplierId/payments',
        body,
      );
    } on ApiException catch (error) {
      if (error.status >= 400 &&
          error.status < 500 &&
          error.status != 408 &&
          error.status != 429) {
        throw SyncRowRejected(error.message, isConflict: error.status == 409);
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> reversePurchase(
    String shopId,
    String receiptUuid, {
    required String reason,
  }) => api.postJson(
    '/v1/shops/$shopId/purchase-receipts/$receiptUuid/reverse',
    {'reason': reason.trim()},
  );

  @override
  Future<Map<String, dynamic>> recordPaymentTerms(
    String shopId,
    String receiptUuid,
    Map<String, Object?> payload,
  ) => api.postJson(
    '/v1/shops/$shopId/purchase-receipts/$receiptUuid/payment-terms',
    payload,
  );

  @override
  Future<Map<String, dynamic>> previewPurchaseTerms(
    String shopId,
    Map<String, Object?> payload,
  ) => api.postJson('/v1/shops/$shopId/purchase-receipts/preview', payload);

  @override
  Future<Map<String, dynamic>> createPurchaseReturn(
    String shopId,
    String receiptUuid,
    Map<String, Object?> payload,
  ) => api.postJson(
    '/v1/shops/$shopId/purchase-receipts/$receiptUuid/returns',
    payload,
  );

  @override
  Future<Map<String, dynamic>> reverseSupplierPayment(
    String shopId,
    String supplierUuid,
    String paymentUuid, {
    required String reason,
  }) => api.postJson(
    '/v1/shops/$shopId/suppliers/$supplierUuid/payments/$paymentUuid/reverse',
    {'reason': reason.trim()},
  );

  @override
  Future<Map<String, dynamic>> fetchSupplierStatement(
    String shopId,
    String supplierUuid,
  ) => api.getJson('/v1/shops/$shopId/suppliers/$supplierUuid/statement');

  @override
  Future<Map<String, dynamic>> publishNativePurchase(
    String shopId,
    Map<String, dynamic> receipt,
  ) async {
    final body = {
      for (final key in [
        'uuid',
        'purchase_date',
        'supplier_uuid',
        'supplier_name',
        'invoice_number',
        'notes',
        'created_at',
        'subtotal',
        'payment_status',
        'origin',
        'items',
      ])
        key: receipt[key],
    };
    try {
      return await api.postJson(
        '/v1/shops/$shopId/purchase-receipts/native',
        body,
      );
    } on ApiException catch (error) {
      if (error.status >= 400 &&
          error.status < 500 &&
          error.status != 408 &&
          error.status != 429) {
        throw SyncRowRejected(error.message);
      }
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pullPurchaseDocuments(
    String shopId, {
    required int afterSequence,
    required int limit,
  }) async {
    final query = Uri(
      queryParameters: {'after_sequence': '$afterSequence', 'limit': '$limit'},
    ).query;
    final result = await api.getJson(
      '/v1/shops/$shopId/purchase-receipts/changes?$query',
    );
    return [
      for (final row in result['value'] as List)
        Map<String, dynamic>.from(row as Map),
    ];
  }
}
