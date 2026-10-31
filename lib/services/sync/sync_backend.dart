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
