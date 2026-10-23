import '../../db/database_helper.dart';
import 'sync_backend.dart';

/// How a device's existing local data is handled on its first sync.
enum FirstSyncMode { uploadExisting, startFresh }

/// Outcome of a sync attempt.
///
/// [syncedAt] is non-null only when a real sync ran. [needsRegistration] means
/// the user belongs to no shop yet. [needsFirstSyncChoice] means this is the
/// first sync and the device has existing local data, so the user must choose
/// whether to upload it or start fresh. [conflicts] are rows that could not be
/// applied or uploaded; everything else synced.
class CloudSyncResult {
  final DateTime? syncedAt;
  final bool needsRegistration;
  final bool needsFirstSyncChoice;
  final List<SyncConflict> conflicts;

  const CloudSyncResult.synced(
    DateTime this.syncedAt, {
    this.conflicts = const [],
  }) : needsRegistration = false,
       needsFirstSyncChoice = false;
  const CloudSyncResult.needsRegistration()
    : syncedAt = null,
      needsRegistration = true,
      needsFirstSyncChoice = false,
      conflicts = const [];
  const CloudSyncResult.needsFirstSyncChoice()
    : syncedAt = null,
      needsRegistration = false,
      needsFirstSyncChoice = true,
      conflicts = const [];
}

/// Two-way sync between the local database and the cloud.
///
/// Pull: per table, pages of rows changed after a cursor on the *server*
/// clock (server_updated_at), re-reading a short overlap so rows from
/// transactions that commit slightly out of order are never skipped. Pulled
/// rows are applied idempotently, so re-reading is harmless.
///
/// Push: exactly the rows marked changed on this device (sync_dirty), in
/// parent-before-child table order and in chunks. A chunk the server refuses
/// is retried row by row so one bad row is reported as a conflict instead of
/// blocking the table. Conflict rules (latest edit wins, deletions win) are
/// enforced by the server, so pull-before-push races cannot lose data.
class CloudSyncEngine {
  final SyncBackend backend;
  final DatabaseHelper database;

  /// Locally-known admin status (e.g. right after registering a shop), which
  /// skips the is_shop_admin round-trip that can lag behind registration.
  final bool? knownIsAdmin;

  /// Rows per pull page (smaller in tests to exercise paging).
  final int pageSize;

  CloudSyncEngine({
    required this.backend,
    required this.database,
    this.knownIsAdmin,
    this.pageSize = defaultPageSize,
  });

  static const lastSyncStateKey = 'last_successful_cloud_sync_at';
  static const defaultPageSize = 500;
  static const pushChunkSize = 200;
  static const pullOverlap = Duration(minutes: 2);

  static const _adminManagedTables = {
    'shops',
    'app_settings',
    'bill_settings',
    'categories',
    'units',
    'suppliers',
    'products',
    'invoice_series',
  };

  static const syncedTables = ['shops', ...storelyCloudTables];

  static String _cursorKey(String table) => 'pull_cursor:$table';

  /// Forget sync progress so the next sync is a first sync again.
  static Future<void> resetProgress(DatabaseHelper database) async {
    await database.clearCloudSyncState(lastSyncStateKey);
    for (final table in syncedTables) {
      await database.clearCloudSyncState(_cursorKey(table));
    }
    await database.saveSyncConflicts(const []);
  }

  Future<CloudSyncResult> sync({FirstSyncMode? firstSyncMode}) async {
    var shopId = await database.currentShopId();

    // Resolve which shop (if any) this user belongs to. Joining a shop the
    // user was invited to also happens here.
    final memberShopId = await backend.resolveMembershipShopId();
    if (memberShopId == null) {
      return const CloudSyncResult.needsRegistration();
    }
    if (memberShopId != shopId) {
      if (await database.hasLocalBusinessDataForCloud()) {
        throw StateError(
          'This user belongs to a different cloud shop, but this device '
          'already has local business data. Export or clear local data '
          'before joining that shop.',
        );
      }
      await database.adoptCloudShopId(memberShopId);
      shopId = memberShopId;
    }

    // Each device gets its own bill-number letter before it bills for the
    // shop, so phones billing offline never issue the same number.
    if (!await database.hasDeviceCode(shopId)) {
      final code = await backend.registerDevice(
        shopId,
        await database.localDeviceId(),
      );
      await database.setDeviceCode(shopId, code);
    }

    final lastSync = await database.getCloudSyncState(lastSyncStateKey);
    final canPushAdminTables =
        knownIsAdmin ?? await backend.isShopAdmin(shopId);
    final firstSync = lastSync == null;

    // First sync on a device that already has local data: the user decides
    // whether to upload it or start fresh. Staff joining an existing shop
    // never upload catalog data, so they are not asked.
    if (firstSync &&
        firstSyncMode == null &&
        canPushAdminTables &&
        await database.hasLocalBusinessDataForCloud()) {
      return const CloudSyncResult.needsFirstSyncChoice();
    }

    final conflicts = <SyncConflict>[];
    for (final table in syncedTables) {
      conflicts.addAll(await _pull(table, shopId));
    }

    if (firstSync) {
      if (firstSyncMode == FirstSyncMode.startFresh) {
        await database.markAllCloudRowsClean();
      }
    }

    for (final table in syncedTables) {
      if (_adminManagedTables.contains(table) && !canPushAdminTables) continue;
      conflicts.addAll(await _push(table));
    }

    final syncedAt = DateTime.now().toUtc();
    await database.setCloudSyncState(
      lastSyncStateKey,
      syncedAt.toIso8601String(),
    );
    await database.saveSyncConflicts(conflicts);
    return CloudSyncResult.synced(syncedAt, conflicts: conflicts);
  }

  Future<List<SyncConflict>> _pull(String table, String shopId) async {
    final conflicts = <SyncConflict>[];
    final stored = DateTime.tryParse(
      await database.getCloudSyncState(_cursorKey(table)) ?? '',
    );
    var afterTs = stored == null
        ? DateTime.utc(1970)
        : stored.subtract(pullOverlap);
    var afterKey = '';
    DateTime? newest = stored;
    final keyColumn = table == 'app_settings' ? 'key' : 'uuid';

    while (true) {
      final page = await backend.pullPage(
        table,
        shopId: shopId,
        afterTs: afterTs,
        afterKey: afterKey,
        limit: pageSize,
      );
      if (page.isEmpty) break;
      conflicts.addAll(await database.cloudImportRows(table, page));
      final last = page.last;
      afterTs = DateTime.parse(last['server_updated_at'].toString());
      afterKey = last[keyColumn]?.toString() ?? '';
      if (newest == null || afterTs.isAfter(newest)) newest = afterTs;
      if (page.length < pageSize) break;
    }

    if (newest != null && newest != stored) {
      await database.setCloudSyncState(
        _cursorKey(table),
        newest.toUtc().toIso8601String(),
      );
    }
    return conflicts;
  }

  Future<List<SyncConflict>> _push(String table) async {
    final conflicts = <SyncConflict>[];
    final rows = await database.cloudDirtyRows(table);
    for (var start = 0; start < rows.length; start += pushChunkSize) {
      final chunk = rows.sublist(
        start,
        start + pushChunkSize < rows.length
            ? start + pushChunkSize
            : rows.length,
      );
      try {
        await backend.upsert(table, chunk);
        await database.markCloudRowsClean(table, chunk);
      } on SyncRowRejected {
        // Find the bad rows; upload the rest.
        for (final row in chunk) {
          try {
            await backend.upsert(table, [row]);
            await database.markCloudRowsClean(table, [row]);
          } on SyncRowRejected catch (error) {
            conflicts.add(
              SyncConflict(
                table: table,
                key: (row['uuid'] ?? row['key'])?.toString() ?? '',
                message: error.message,
              ),
            );
          }
        }
      }
    }
    return conflicts;
  }
}
