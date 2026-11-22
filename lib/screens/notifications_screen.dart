import 'package:flutter/material.dart';

import '../services/needs_action.dart';
import '../services/cloud_service.dart';
import '../main.dart' show AppGate;
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
  late Future<NeedsActionSnapshot> _items = NeedsAction.loadSnapshot();
  int _generation = 0;
  bool _opening = false;
  late (String?, CloudMembership, String?, String?) _identity;

  @override
  void initState() {
    super.initState();
    _identity = NeedsActionWorkspace.currentIdentity();
    CloudService.instance.state.addListener(_onCloudChanged);
  }

  @override
  void dispose() {
    CloudService.instance.state.removeListener(_onCloudChanged);
    super.dispose();
  }

  void _onCloudChanged() {
    if (_identity != NeedsActionWorkspace.currentIdentity() && mounted) {
      _identity = NeedsActionWorkspace.currentIdentity();
      _reload();
    }
  }

  void _reload() {
    _generation++;
    setState(() {
      _items = NeedsAction.loadSnapshot();
    });
  }

  Future<void> _open(NeedsActionItem item, NeedsActionSnapshot snapshot) async {
    if (_opening) return;
    _opening = true;
    final generation = _generation;
    try {
      await snapshot.workspace.verify();
      final fresh = await NeedsAction.loadSnapshot();
      await snapshot.workspace.verify();
      if (!mounted || generation != _generation) return;
      if (!fresh.items.any((value) => value.kind == item.kind)) {
        _reload();
        return;
      }
      final workspace = snapshot.workspace;
      switch (item.kind) {
        case NeedsActionKind.overdueDues:
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => _NeedsActionRoute(
                workspace: workspace,
                child: ReceivablesScreen(
                  overdueOnly: true,
                  workspace: workspace,
                ),
              ),
            ),
          );
        case NeedsActionKind.expiring:
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => _NeedsActionRoute(
                workspace: workspace,
                child: ExpiringStockScreen(
                  initialDays: 7,
                  workspace: workspace,
                ),
              ),
            ),
          );
        case NeedsActionKind.syncProblem:
          await showSyncStatusSheet(
            context,
            assertWorkspace: workspace.verify,
            wrap: (child) =>
                _NeedsActionRoute(workspace: workspace, child: child),
          );
        case NeedsActionKind.backup:
          final restored = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => _NeedsActionRoute(
              workspace: workspace,
              child: BackupSheet(assertWorkspace: workspace.verify),
            ),
          );
          if (mounted && restored == true) {
            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const AppGate()),
              (_) => false,
            );
            return;
          }
      }
      if (mounted) _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
        _reload();
      }
    } finally {
      _opening = false;
    }
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
      body: FutureBuilder<NeedsActionSnapshot>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const AppSkeletonList(rows: 3);
          }
          if (snap.hasError) {
            return AppErrorState(
              title: 'Could not load alerts',
              error: snap.error,
              onRetry: _reload,
            );
          }
          final snapshot = snap.data!;
          final items = snapshot.items;
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
                key: ValueKey('needs-action-${item.kind.name}'),
                onTap: () => _open(item, snapshot),
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

class _NeedsActionRoute extends StatelessWidget {
  final NeedsActionWorkspace workspace;
  final Widget child;
  const _NeedsActionRoute({required this.workspace, required this.child});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CloudState>(
    valueListenable: CloudService.instance.state,
    builder: (context, _, _) =>
        workspace.identity != NeedsActionWorkspace.currentIdentity()
        ? const SafeArea(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Text('Workspace changed. Reopen Needs action.'),
            ),
          )
        : child,
  );
}
