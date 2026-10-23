import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/cloud_service.dart';
import '../../services/sync_status.dart';
import '../../theme/app_theme.dart';

/// Header icon for cloud sync: done, uploading, waiting or problem.
/// Hidden when the phone is not signed in to cloud.
class SyncStatusIcon extends StatelessWidget {
  final Color? color;

  const SyncStatusIcon({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, cloud, _) {
        if (!cloud.isConfigured || !cloud.isSignedIn) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: SyncStatus.instance,
          builder: (context, _) {
            final status = SyncStatus.instance;
            final (icon, tint, tip) = cloud.isSyncing
                ? (Icons.cloud_sync_outlined, color, 'Syncing…')
                : cloud.error != null || status.conflicts.isNotEmpty
                ? (Icons.cloud_off_outlined, AppColors.error, 'Sync problem')
                : status.pendingTotal > 0
                ? (
                    Icons.cloud_upload_outlined,
                    AppColors.amber,
                    '${status.pendingTotal} changes waiting to sync',
                  )
                : (Icons.cloud_done_outlined, color, 'All synced');
            return IconButton(
              key: const ValueKey('sync-status-icon'),
              tooltip: tip,
              icon: Icon(icon, color: tint),
              onPressed: () => showSyncStatusSheet(context),
            );
          },
        );
      },
    );
  }
}

Future<void> showSyncStatusSheet(BuildContext context) async {
  await SyncStatus.instance.refresh();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SyncStatusSheet(),
  );
}

class _SyncStatusSheet extends StatelessWidget {
  const _SyncStatusSheet();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, cloud, _) => ListenableBuilder(
        listenable: SyncStatus.instance,
        builder: (context, _) {
          final status = SyncStatus.instance;
          final last = cloud.lastSyncedAt;
          final headline = cloud.isSyncing
              ? 'Syncing…'
              : cloud.error != null
              ? 'Could not sync'
              : status.pendingTotal > 0
              ? '${status.pendingTotal} changes waiting to upload'
              : 'Everything is synced';
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.8,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text('Cloud sync', style: AppText.title),
                  const SizedBox(height: AppSpacing.xs),
                  Text(headline, style: AppText.subtitle),
                  Text(
                    last == null
                        ? 'Not synced yet'
                        : 'Last synced '
                              '${DateFormat('dd MMM, hh:mm a').format(last.toLocal())}',
                    style: AppText.caption,
                  ),
                  if (cloud.error != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      cloud.error!,
                      style: AppText.caption.copyWith(color: AppColors.error),
                    ),
                  ],
                  if (status.pending.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text('Waiting to upload', style: AppText.label),
                    for (final e in status.pending.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            Expanded(child: Text(SyncStatus.label(e.key))),
                            Text('${e.value}', style: AppText.subtitle),
                          ],
                        ),
                      ),
                  ],
                  if (status.conflicts.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      '${status.conflicts.length} change(s) could not sync',
                      style: AppText.label.copyWith(color: AppColors.error),
                    ),
                    Text(
                      'They stay on this phone and are retried on every '
                      'sync. If they keep failing, send this list to '
                      'support.',
                      style: AppText.caption,
                    ),
                    for (final c in status.conflicts.take(20))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                        ),
                        title: Text(SyncStatus.label(c.table)),
                        subtitle: Text(c.message),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: cloud.isSyncing
                        ? null
                        : () => CloudService.instance.syncNow(
                            reason: 'Manual sync',
                          ),
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(cloud.isSyncing ? 'Syncing…' : 'Sync now'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
