import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';
import 'backup_service.dart';
import 'cloud_service.dart';
import 'sync_status.dart';

enum NeedsActionKind { overdueDues, expiring, syncProblem, backup }

/// One thing the shopkeeper should act on soon (the bell on Home).
class NeedsActionItem {
  final NeedsActionKind kind;
  final String title;
  final String detail;

  const NeedsActionItem(this.kind, this.title, this.detail);
}

/// Collects what needs attention that Home doesn't already list: dues over
/// 30 days, stock expiring within a week, sync problems and an old backup.
/// (Unpaid bills and low stock have their own sections on Home.)
class NeedsAction {
  static Future<List<NeedsActionItem>> load() async {
    final db = DatabaseHelper.instance;
    final items = <NeedsActionItem>[];
    try {
      final ageing = await db.receivablesAgeing();
      final overdue = ageing.where((r) => r.buckets[2] + r.buckets[3] > 0.005);
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
            '₹${amount.toStringAsFixed(0)} overdue · send reminders',
          ),
        );
      }
      final expiring = await db.expiringStock(days: 7);
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
      final cloud = CloudService.instance.state.value;
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
    } catch (error) {
      debugPrint('Needs action failed: $error');
    }
    return items;
  }
}
