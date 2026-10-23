import 'package:storely/services/sync/sync_backend.dart';

/// In-memory stand-in for the Supabase backend, applying the same write
/// rules as supabase/migrations/20261024_sync_v2.sql (server clock, latest
/// edit wins, deletion wins, sticky billing deletions) so the sync engine can
/// be tested across several simulated devices.
class FakeSyncBackend implements SyncBackend {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {};
  String? memberShopId;
  bool admin = true;
  Object? adminCheckError;

  /// Keys the server refuses (simulates a constraint/permission error).
  final Set<String> rejectKeys = {};
  final Map<String, List<String>> _devices = {};
  DateTime _clock = DateTime.utc(2026, 1, 1);
  int uploads = 0;

  static const _sticky = {
    'bills',
    'bill_items',
    'bill_payments',
    'stock_movements',
  };

  DateTime _tick() => _clock = _clock.add(const Duration(milliseconds: 1));

  static String keyOf(String table, Map<String, dynamic> row) =>
      (table == 'app_settings' ? row['key'] : row['uuid']).toString();

  List<Map<String, dynamic>> rows(String table) =>
      (tables[table] ?? {}).values.toList();

  Map<String, dynamic>? row(String table, String key) => tables[table]?[key];

  @override
  Future<String?> resolveMembershipShopId() async => memberShopId;

  @override
  Future<bool> isShopAdmin(String shopId) async {
    if (adminCheckError != null) throw adminCheckError!;
    return admin;
  }

  @override
  Future<List<Map<String, dynamic>>> pullPage(
    String table, {
    required String shopId,
    required DateTime afterTs,
    required String afterKey,
    required int limit,
  }) async {
    final shopColumn = table == 'shops' ? 'uuid' : 'shop_id';
    final matching =
        rows(table).where((r) {
          if (r[shopColumn] != shopId) return false;
          final ts = DateTime.parse(r['server_updated_at'] as String);
          final cmp = ts.compareTo(afterTs);
          return cmp > 0 ||
              (cmp == 0 && keyOf(table, r).compareTo(afterKey) > 0);
        }).toList()..sort((a, b) {
          final cmp = (a['server_updated_at'] as String).compareTo(
            b['server_updated_at'] as String,
          );
          return cmp != 0 ? cmp : keyOf(table, a).compareTo(keyOf(table, b));
        });
    return [for (final r in matching.take(limit)) Map<String, dynamic>.from(r)];
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> incoming) async {
    for (final r in incoming) {
      if (rejectKeys.contains(keyOf(table, r))) {
        throw SyncRowRejected('rejected ${keyOf(table, r)}');
      }
    }
    uploads += incoming.length;
    final store = tables.putIfAbsent(table, () => {});
    for (final raw in incoming) {
      final key = keyOf(table, raw);
      final old = store[key];
      var row = Map<String, dynamic>.from(raw);
      if (old != null) {
        row = {...old, ...row};
        if (_sticky.contains(table) &&
            old['deleted_at'] != null &&
            row['deleted_at'] == null) {
          row['deleted_at'] = old['deleted_at'];
          if (table == 'bills') {
            for (final c in [
              'lifecycle_status',
              'cancelled_at',
              'cancel_reason',
            ]) {
              row[c] = old[c];
            }
          }
        }
        final incomingTs = DateTime.parse(row['updated_at'] as String);
        final storedTs = DateTime.parse(old['updated_at'] as String);
        if (incomingTs.isBefore(storedTs)) {
          if (old['deleted_at'] == null && raw['deleted_at'] != null) {
            row = {...old, 'deleted_at': raw['deleted_at']};
            if (table == 'bills') {
              for (final c in [
                'lifecycle_status',
                'cancelled_at',
                'cancel_reason',
              ]) {
                row[c] = raw[c];
              }
            }
          } else {
            continue;
          }
        }
      }
      row['server_updated_at'] = _tick().toIso8601String();
      store[key] = row;
    }
  }

  @override
  Future<String> registerDevice(String shopId, String deviceId) async {
    final devices = _devices.putIfAbsent(shopId, () => []);
    if (!devices.contains(deviceId)) devices.add(deviceId);
    final index = devices.indexOf(deviceId);
    return index == 0 ? '' : String.fromCharCode('A'.codeUnitAt(0) + index);
  }
}
