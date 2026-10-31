import '../sync/purchase_sync_backend.dart';
import '../sync/sync_backend.dart';
import 'api_client.dart';
import 'api_sync_backend.dart';

/// Preserves existing row sync; publishes document metadata only after stock upload.
class PurchaseApiSyncBackend extends ApiSyncBackend
    implements PurchaseSyncBackend {
  PurchaseApiSyncBackend(super.api, {super.preferredShopId});

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
