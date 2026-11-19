import 'api_client.dart';

/// Service versions only. Neither advertised features nor the returned role
/// authorize a command; each endpoint still checks current membership/access.
class ServerCapabilities {
  final Map<String, int> _features;

  ServerCapabilities._(this._features);

  bool get supportsSupplierPaymentProof {
    final proof = _features['supplier_payment_proof'] ?? 0;
    if (proof == 0) return false;
    final binding = _features['supplier_payment_binding'] ?? 0;
    if (proof != 1 || !{1, 2}.contains(binding)) {
      throw const FormatException('Unsupported supplier payment capability');
    }
    return true;
  }

  /// Fetches fresh support metadata for this call. A missing route on an older
  /// server returns null so existing exact-body proof probing can continue.
  static Future<ServerCapabilities?> load(ApiClient api, String shopId) async {
    final actor = api.user?.id;
    Map<String, dynamic> data;
    try {
      data = await api.getJson('/v1/shops/$shopId/capabilities');
    } on ApiException catch (error) {
      if ((error.status == 404 && error.code == 'http_404') ||
          (error.status == 405 && error.code == 'http_405')) {
        return null;
      }
      rethrow;
    }
    if (api.user?.id != actor) {
      throw StateError(
        'The account changed while checking service support. Retry sync.',
      );
    }
    if (data['contract_version'] is! int ||
        data['contract_version'] != 1 ||
        data['shop_id'] != shopId ||
        !{'owner', 'admin', 'staff'}.contains(data['role']) ||
        data['features'] is! Map) {
      throw const FormatException('Invalid service capability contract');
    }
    final features = <String, int>{};
    for (final entry in (data['features'] as Map).entries) {
      if (entry.key is! String || entry.value is! int || entry.value < 0) {
        throw const FormatException('Invalid service feature version');
      }
      features[entry.key as String] = entry.value as int;
    }
    return ServerCapabilities._(features);
  }
}
