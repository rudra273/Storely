import '../sync/sync_backend.dart';
import 'api_client.dart';

/// [SyncBackend] for the Storely API. Same contract the sync engine had with
/// the sync engine: server-clock cursors, per-row rejections, idempotent uploads.
class ApiSyncBackend implements SyncBackend {
  ApiSyncBackend(this.api, {this.preferredShopId});

  final Future<String> Function()? preferredShopId;

  final ApiClient api;

  @override
  Future<String?> resolveMembershipShopId() async {
    // 1. Already a member? The server lists the oldest membership first, so the
    //    answer is stable for people who belong to more than one shop.
    final shops = await api.getJson('/v1/shops');
    final mine = shops['value'];
    if (mine is List && mine.isNotEmpty) {
      final preferred = await preferredShopId?.call();
      for (final row in mine) {
        if ((row as Map)['shop_id'] == preferred) {
          return _requireCloudAccess(preferred!);
        }
      }
      return _requireCloudAccess((mine.first as Map)['shop_id'].toString());
    }

    // 2. Invited somewhere? Accept it and join. Errors propagate, so an invited
    //    person is never told to "register your shop" by mistake.
    final pending = (await api.getJson('/v1/invites/pending'))['value'];
    if (pending is List && pending.isNotEmpty) {
      final shopId = (pending.first as Map)['shop_id'].toString();
      final result = await api.postJson('/v1/invites/accept', {
        'shop_id': shopId,
      });
      final status = result['status'];
      if (status == 'joined' || status == 'already_member') {
        return _requireCloudAccess(shopId);
      }
    }
    return null;
  }

  Future<String> _requireCloudAccess(String shopId) async {
    final entitlement = await api.getJson('/v1/shops/$shopId/entitlement');
    if (entitlement['cloud_sync'] != true) {
      final status = entitlement['effective_status'];
      final label =
          const {'free', 'expired', 'suspended', 'scheduled'}.contains(status)
          ? status.toString()
          : 'unavailable';
      throw ApiException(
        403,
        'premium_required',
        'Cloud sync paused: subscription $label. Your local records are kept. '
            'Contact the Storely team for activation or renewal.',
      );
    }
    return shopId;
  }

  /// Throws when the role cannot be determined: guessing "not admin" would
  /// silently skip uploads.
  @override
  Future<bool> isShopAdmin(String shopId) async {
    try {
      final role = (await api.getJson('/v1/shops/$shopId/role'))['role'];
      return role == 'owner' || role == 'admin';
    } on ApiException catch (error) {
      if (error.status == 404) return false; // not a member of that shop
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> pullPage(
    String table, {
    required String shopId,
    required DateTime afterTs,
    required String afterKey,
    required int limit,
  }) async {
    final data = await api.postJson('/v1/shops/$shopId/sync/pull', {
      'table': table,
      'after_ts': afterTs.toUtc().toIso8601String(),
      'after_key': afterKey,
      'limit': limit,
    });
    return [
      for (final row in data['rows'] as List)
        Map<String, dynamic>.from(row as Map),
    ];
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final shopId = _shopIdOf(table, rows.first);
    final data = await api.postJson('/v1/shops/$shopId/sync/push', {
      'table': table,
      'rows': rows,
    });
    final rejected = data['rejected'];
    if (rejected is List && rejected.isNotEmpty) {
      // Rows the server accepted are kept (re-sending is harmless); the engine
      // retries one row at a time to find which ones to report.
      throw SyncRowRejected((rejected.first as Map)['message'].toString());
    }
  }

  @override
  Future<String> registerDevice(String shopId, String deviceId) async {
    final data = await api.postJson('/v1/devices/register', {
      'shop_id': shopId,
      'device_id': deviceId,
    });
    return data['code']?.toString() ?? '';
  }

  static String _shopIdOf(String table, Map<String, dynamic> row) =>
      (table == 'shops' ? row['uuid'] : row['shop_id']).toString();
}
