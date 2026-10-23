import 'package:flutter/material.dart';

import '../services/needs_action.dart';
import '../theme/app_theme.dart';
import 'reports_screens.dart';
import 'shared/sync_status_widgets.dart';
import 'store/backup_sheet.dart';

/// The bell on Home: a short list of things to act on that Home doesn't
/// already show (overdue dues, expiring stock, sync problems, backup).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<NeedsActionItem>> _items = NeedsAction.load();

  void _reload() => setState(() => _items = NeedsAction.load());

  Future<void> _open(NeedsActionItem item) async {
    switch (item.kind) {
      case NeedsActionKind.overdueDues:
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const ReceivablesScreen()),
        );
      case NeedsActionKind.expiring:
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const ExpiringStockScreen()),
        );
      case NeedsActionKind.syncProblem:
        await showSyncStatusSheet(context);
      case NeedsActionKind.backup:
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const BackupSheet(),
        );
    }
    if (mounted) _reload();
  }

  static IconData _icon(NeedsActionKind kind) => switch (kind) {
    NeedsActionKind.overdueDues => Icons.schedule_rounded,
    NeedsActionKind.expiring => Icons.event_busy_outlined,
    NeedsActionKind.syncProblem => Icons.cloud_off_outlined,
    NeedsActionKind.backup => Icons.backup_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: navyAppBar(title: 'Needs action'),
      body: FutureBuilder<List<NeedsActionItem>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppSkeletonList(rows: 3);
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.task_alt_rounded,
              title: 'All caught up',
              message:
                  'Overdue dues, expiring stock, sync problems and backup '
                  'reminders show up here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) {
              final item = items[i];
              return AppCard(
                onTap: () => _open(item),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    LeadingIconChip(
                      icon: _icon(item.kind),
                      color: AppColors.error,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title, style: AppText.subtitle),
                          Text(item.detail, style: AppText.caption),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
