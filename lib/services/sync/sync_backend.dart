import 'package:supabase_flutter/supabase_flutter.dart';

/// The cloud a device syncs with. [SupabaseSyncBackend] is the real one;
/// tests use an in-memory fake with the same server rules.
abstract class SyncBackend {
  /// The shop the signed-in user belongs to (redeeming a pending invite if
  /// needed), or null when they belong to none yet.
  Future<String?> resolveMembershipShopId();

  /// Throws when the role cannot be determined: guessing "not admin" would
  /// silently skip uploads.
  Future<bool> isShopAdmin(String shopId);

  /// One page of rows of [table] changed after (afterTs, afterKey) by the
  /// server clock, oldest first. Each row includes `server_updated_at`.
  Future<List<Map<String, dynamic>>> pullPage(
    String table, {
    required String shopId,
    required DateTime afterTs,
    required String afterKey,
    required int limit,
  });

  /// Inserts or updates rows. Throws [SyncRowRejected] when the server
  /// refuses them (constraint, permission); other errors (network) propagate.
  Future<void> upsert(String table, List<Map<String, dynamic>> rows);

  /// Short per-install code used in bill numbers ('' for the shop's first
  /// device, then 'B', 'C', ...). Registers [deviceId] on first call.
  Future<String> registerDevice(String shopId, String deviceId);
}

/// The server refused a write. The rows stay queued and are reported as a
/// sync conflict; they do not block other rows.
class SyncRowRejected implements Exception {
  final String message;

  const SyncRowRejected(this.message);

  @override
  String toString() => message;
}

class SupabaseSyncBackend implements SyncBackend {
  final SupabaseClient client;

  SupabaseSyncBackend(this.client);

  @override
  Future<String?> resolveMembershipShopId() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    // 1. Already a member? Oldest membership first, so the answer is stable
    //    for users who belong to more than one shop.
    final rows = await client
        .from('shop_members')
        .select('shop_id')
        .eq('user_id', user.id)
        .order('created_at', ascending: true)
        .limit(1);
    if ((rows as List).isNotEmpty) {
      final value = rows.first['shop_id']?.toString();
      if (value != null && value.isNotEmpty) return value;
    }

    // 2. Invited somewhere? Redeem the invite and join. Errors propagate so
    //    an invited user is never shown "register your shop" by mistake.
    final invited = (await client.rpc('my_pending_invite_shop'))?.toString();
    if (invited != null && invited.isNotEmpty) {
      final result = await client.rpc(
        'accept_invite',
        params: {'target_shop_id': invited},
      );
      if (result == 'joined' || result == 'already_member') return invited;
    }
    return null;
  }

  @override
  Future<bool> isShopAdmin(String shopId) async {
    final result = await client.rpc(
      'is_shop_admin',
      params: {'target_shop_id': shopId},
    );
    return result == true;
  }

  @override
  Future<List<Map<String, dynamic>>> pullPage(
    String table, {
    required String shopId,
    required DateTime afterTs,
    required String afterKey,
    required int limit,
  }) async {
    final response = await client.rpc(
      'sync_pull',
      params: {
        'p_table': table,
        'p_shop_id': shopId,
        'p_after_ts': afterTs.toUtc().toIso8601String(),
        'p_after_key': afterKey,
        'p_limit': limit,
      },
    );
    return [
      for (final row in response as List) Map<String, dynamic>.from(row as Map),
    ];
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    try {
      await client
          .from(table)
          .upsert(
            rows,
            onConflict: table == 'app_settings' ? 'shop_id,key' : 'uuid',
          );
    } on PostgrestException catch (error) {
      throw SyncRowRejected(error.message);
    }
  }

  @override
  Future<String> registerDevice(String shopId, String deviceId) async {
    final result = await client.rpc(
      'register_device',
      params: {'target_shop_id': shopId, 'device_uuid': deviceId},
    );
    return result?.toString() ?? '';
  }
}
