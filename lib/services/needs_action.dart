import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import 'backup_service.dart';
import 'cloud_service.dart';
import 'sync_status.dart';
import 'home_search.dart';
import '../utils/money.dart';

enum NeedsActionKind { overdueDues, expiring, syncProblem, backup }

/// One thing the shopkeeper should act on soon (the bell on Home).
class NeedsActionItem {
  final NeedsActionKind kind;
  final String title;
  final String detail;

  const NeedsActionItem(this.kind, this.title, this.detail);
}

/// Alerts are derived from one captured local workspace, never from a route
/// payload supplied by an external notification sender.
class NeedsActionWorkspace {
  final CheckoutScope scope;
  final (String?, CloudMembership, String?, String?) identity;
  const NeedsActionWorkspace(this.scope, this.identity);
  static (String?, CloudMembership, String?, String?) currentIdentity() {
    final state = CloudService.instance.state.value;
    return (
      state.user?.id,
      state.membership,
      state.shopRole,
      state.config?.url,
    );
  }

  static Future<NeedsActionWorkspace> capture() async {
    final identity = currentIdentity();
    final scope = await DatabaseHelper.instance.captureCheckoutScope();
    final workspace = NeedsActionWorkspace(scope, identity);
    await workspace.verify();
    return workspace;
  }

  Future<void> verify() async {
    final currentScope = await isCurrentHomeSearchScope(scope);
    if (!currentScope ||
        (identity.$1 != null && identity.$1 != scope.owner) ||
        identity != currentIdentity()) {
      throw StateError('Workspace changed. Reopen Needs action.');
    }
  }

  Future<T> read<T>(Future<T> Function() load) async {
    await verify();
    final value = await load();
    await verify();
    return value;
  }
}

class NeedsActionSnapshot {
  final NeedsActionWorkspace workspace;
  final List<NeedsActionItem> items;
  const NeedsActionSnapshot(this.workspace, this.items);
}

List<AgeingRow> overdueAgeingRows(List<AgeingRow> rows) => [
  for (final row in rows)
    if (row.buckets[2] + row.buckets[3] > 0.005)
      AgeingRow(
        customerName: row.customerName,
        customerPhone: row.customerPhone,
        buckets: [0, 0, row.buckets[2], row.buckets[3]],
      ),
];

Future<List<ExpiringBatch>> expiringAlertBatches({int days = 7}) async {
  final now = DateTime.now();
  final cutoff = DateTime(
    now.year,
    now.month,
    now.day,
  ).add(Duration(days: days));
  final rows = await DatabaseHelper.instance.expiringStock(days: days + 1);
  return rows
      .where(
        (row) => !DateTime(
          row.expiry.year,
          row.expiry.month,
          row.expiry.day,
        ).isAfter(cutoff),
      )
      .toList();
}

/// Collects what needs attention that Home doesn't already list: dues over
/// 30 days, stock expiring within a week, sync problems and an old backup.
/// (Unpaid bills and low stock have their own sections on Home.)
class NeedsAction {
  static Future<List<NeedsActionItem>> load() async {
    try {
      return (await loadSnapshot()).items;
    } catch (error) {
      debugPrint('Needs action failed: $error');
      return [];
    }
  }

  static Future<NeedsActionSnapshot> loadSnapshot() async {
    final workspace = await NeedsActionWorkspace.capture();
    final items = await workspace.read(_loadItems);
    return NeedsActionSnapshot(workspace, items);
  }

  static Future<List<NeedsActionItem>> _loadItems() async {
    final db = DatabaseHelper.instance;
    final items = <NeedsActionItem>[];
    final cloud = CloudService.instance.state.value;
    final canReadBusiness =
        cloud.isAdmin && (db.isAdminMutationAllowed?.call() ?? true);
    if (canReadBusiness) {
      final ageing = await db.receivablesAgeing();
      final overdue = overdueAgeingRows(ageing);
      if (overdue.isNotEmpty) {
        final amount = overdue.fold<double>(
          0,
          (s, r) => s + r.buckets[2] + r.buckets[3],
        );
        items.add(
          NeedsActionItem(
            NeedsActionKind.overdueDues,
            '${overdue.length} customer${overdue.length == 1 ? '' : 's'} '
                'owe for over 30 days',
            '${rupees(amount)} overdue · send reminders',
          ),
        );
      }
      final expiring = await expiringAlertBatches();
      if (expiring.isNotEmpty) {
        final expired = expiring
            .where((b) => b.isExpired(DateTime.now()))
            .length;
        items.add(
          NeedsActionItem(
            NeedsActionKind.expiring,
            expired > 0
                ? '$expired batch${expired == 1 ? '' : 'es'} expired'
                : '${expiring.length} batch${expiring.length == 1 ? '' : 'es'}'
                      ' expire this week',
            expiring.map((b) => b.productName).toSet().take(3).join(', '),
          ),
        );
      }
    }
    if (cloud.isConfigured && cloud.isSignedIn) {
      final conflicts = SyncStatus.instance.conflicts;
      if (conflicts.isNotEmpty || cloud.error != null) {
        items.add(
          NeedsActionItem(
            NeedsActionKind.syncProblem,
            'Some changes could not sync',
            conflicts.isNotEmpty
                ? '${conflicts.length} change(s) waiting'
                : cloud.error!,
          ),
        );
      }
    } else {
      final last = await BackupService.lastBackupAt();
      if (last == null || DateTime.now().difference(last).inDays >= 7) {
        items.add(
          NeedsActionItem(
            NeedsActionKind.backup,
            last == null ? 'No backup yet' : 'Last backup over a week ago',
            'Save a backup file so a lost phone does not lose your data',
          ),
        );
      }
    }
    return items;
  }
}
