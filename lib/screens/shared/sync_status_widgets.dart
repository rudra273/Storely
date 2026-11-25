import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db/database_helper.dart';
import '../../services/cloud_service.dart';
import '../../services/sync/cloud_sync_engine.dart';
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

Future<void> showSyncStatusSheet(
  BuildContext context, {
  Future<void> Function()? assertWorkspace,
  Widget Function(Widget child)? wrap,
}) async {
  await assertWorkspace?.call();
  await SyncStatus.instance.refresh();
  await assertWorkspace?.call();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        wrap?.call(_SyncStatusSheet(assertWorkspace: assertWorkspace)) ??
        _SyncStatusSheet(assertWorkspace: assertWorkspace),
  );
}

class _SyncStatusSheet extends StatelessWidget {
  final Future<void> Function()? assertWorkspace;
  const _SyncStatusSheet({this.assertWorkspace});

  Future<void> _resolve(
    BuildContext context,
    SyncConflict conflict,
    String action,
  ) async {
    try {
      await assertWorkspace?.call();
      if (!context.mounted) return;
      if (action == 'reconcile') {
        final resolved = await showNativeSaleReconciliationDialog(
          context,
          billUuid: conflict.key,
          assertWorkspace: assertWorkspace,
        );
        if (resolved == true) {
          await SyncStatus.instance.refresh();
        }
        return;
      }
      if (action == 'cloud') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Use the cloud copy?'),
            content: const Text(
              "This phone's version of this record stops syncing. The "
              "cloud's version replaces it on the next sync (if the cloud has "
              'one). Use this when the record keeps failing to sync.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Use cloud copy'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await assertWorkspace?.call();
        await CloudSyncEngine.useCloudCopy(DatabaseHelper.instance, conflict);
      }
      await assertWorkspace?.call();
      await CloudService.instance.syncNow(reason: 'Retry sync problems');
      await SyncStatus.instance.refresh();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

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
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Fix',
                          onSelected: (action) => _resolve(context, c, action),
                          itemBuilder: (_) => [
                            if (c.table ==
                                CloudSyncEngine.nativeSaleConflictTable)
                              const PopupMenuItem(
                                value: 'reconcile',
                                child: Text('Review & reconcile'),
                              ),
                            const PopupMenuItem(
                              value: 'retry',
                              child: Text('Try again'),
                            ),
                            if (c.table != 'purchase_documents' &&
                                c.table !=
                                    CloudSyncEngine.nativeSaleConflictTable)
                              const PopupMenuItem(
                                value: 'cloud',
                                child: Text('Use cloud copy'),
                              ),
                          ],
                        ),
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

typedef NativeSaleInspectFn =
    Future<NativeSaleReconciliationReport> Function(String billUuid);
typedef NativeSaleResolveFn =
    Future<void> Function(
      NativeSaleReconciliationReport report, {
      bool allowStockShortage,
      bool acceptRecordedSnapshot,
      bool postOriginalBeforeLocalEdits,
      String? reason,
    });

Future<bool?> showNativeSaleReconciliationDialog(
  BuildContext context, {
  required String billUuid,
  Future<void> Function()? assertWorkspace,
  NativeSaleInspectFn? inspect,
  NativeSaleResolveFn? resolve,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => NativeSaleReconciliationDialog(
      billUuid: billUuid,
      assertWorkspace: assertWorkspace,
      inspect: inspect ?? CloudService.instance.inspectReservedNativeSale,
      resolve: resolve ?? CloudService.instance.resolveReservedNativeSale,
    ),
  );
}

class NativeSaleReconciliationDialog extends StatefulWidget {
  final String billUuid;
  final Future<void> Function()? assertWorkspace;
  final NativeSaleInspectFn inspect;
  final NativeSaleResolveFn resolve;

  const NativeSaleReconciliationDialog({
    super.key,
    required this.billUuid,
    this.assertWorkspace,
    required this.inspect,
    required this.resolve,
  });

  @override
  State<NativeSaleReconciliationDialog> createState() =>
      _NativeSaleReconciliationDialogState();
}

class _NativeSaleReconciliationDialogState
    extends State<NativeSaleReconciliationDialog> {
  final _reasonController = TextEditingController();
  NativeSaleReconciliationReport? _report;
  String? _loadError;
  String? _submitError;
  bool _loading = true;
  bool _submitting = false;
  bool _allowStockShortage = false;
  bool _acceptRecordedSnapshot = false;
  bool _postOriginalBeforeLocalEdits = false;

  @override
  void initState() {
    super.initState();
    _reasonController.addListener(_onReasonChanged);
    _load();
  }

  @override
  void dispose() {
    _reasonController.removeListener(_onReasonChanged);
    _reasonController.dispose();
    super.dispose();
  }

  void _onReasonChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _submitError = null;
    });
    try {
      await widget.assertWorkspace?.call();
      final report = await widget.inspect(widget.billUuid);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
        _allowStockShortage = false;
        _acceptRecordedSnapshot = false;
        _postOriginalBeforeLocalEdits = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  bool _canSubmit(NativeSaleReconciliationReport report) {
    if (_submitting) return false;
    if (report.serverStatus == 'already_committed') return true;
    if (report.serverStatus == 'ready') return true;
    if (report.serverStatus == 'needs_reconciliation' && report.canReconcile) {
      if (report.hasStockShortages && !_allowStockShortage) return false;
      if (report.hasSnapshotOrTermsMismatches && !_acceptRecordedSnapshot) {
        return false;
      }
      if (report.localDiff.hasEdits && !_postOriginalBeforeLocalEdits) {
        return false;
      }
      return _reasonController.text.trim().length >= 3;
    }
    return false;
  }

  String? _primaryActionLabel(NativeSaleReconciliationReport report) {
    if (report.serverStatus == 'already_committed') {
      return 'Confirm synced invoice';
    }
    if (report.serverStatus == 'ready') {
      return report.localDiff.hasEdits
          ? 'Post original invoice & sync edits'
          : 'Post original invoice';
    }
    if (report.serverStatus == 'needs_reconciliation' && report.canReconcile) {
      return 'Post original invoice';
    }
    return null;
  }

  Future<void> _submit() async {
    final report = _report;
    if (report == null || !_canSubmit(report)) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.assertWorkspace?.call();
      final isNeedsReconcile =
          report.serverStatus == 'needs_reconciliation' && report.canReconcile;
      await widget.resolve(
        report,
        allowStockShortage: isNeedsReconcile && _allowStockShortage,
        acceptRecordedSnapshot: isNeedsReconcile && _acceptRecordedSnapshot,
        postOriginalBeforeLocalEdits: report.serverStatus == 'ready'
            ? report.localDiff.hasEdits
            : _postOriginalBeforeLocalEdits,
        reason: isNeedsReconcile ? _reasonController.text.trim() : null,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitError = error.toString();
        _submitting = false;
      });
    }
  }

  String _statusHeadline(String status) => switch (status) {
    'already_committed' => 'This invoice is already recorded in the cloud.',
    'ready' => 'The original invoice is ready to post to the cloud.',
    'needs_reconciliation' =>
      'Cloud stock or catalog details changed since this invoice was issued.',
    'identity_conflict' =>
      'The cloud already has a conflicting record with this invoice identity.',
    'blocked' => 'This invoice cannot be reconciled automatically.',
    _ => 'Cloud status: $status',
  };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final title = report == null || report.sale.invoiceNumber.isEmpty
        ? 'Review & reconcile invoice'
        : 'Reconcile ${report.sale.invoiceNumber}';

    if (_loading) {
      return AlertDialog(
        title: Text(title),
        content: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Checking cloud status…')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      );
    }

    if (_loadError != null || report == null) {
      return AlertDialog(
        title: Text(title),
        content: Text(
          _loadError ?? 'Could not inspect this reserved invoice.',
          style: AppText.caption.copyWith(color: AppColors.error),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Close'),
          ),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    }

    final primaryLabel = _primaryActionLabel(report);
    final isNeedsReconcile =
        report.serverStatus == 'needs_reconciliation' && report.canReconcile;

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (report.sale.totalAmount.isNotEmpty)
                Text(
                  'Original total: ${report.sale.totalAmount}',
                  style: AppText.label,
                ),
              const SizedBox(height: AppSpacing.xs),
              Text(_statusHeadline(report.serverStatus)),
              if (report.stockShortages.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Stock shortages',
                  style: AppText.label.copyWith(color: AppColors.error),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final item in report.stockShortages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      '• ${item['product_name'] ?? item['product_uuid']}: '
                      'sold ${item['recorded_quantity']}, '
                      'available ${item['available_quantity']} '
                      '(short by ${item['shortage_quantity']})',
                      style: AppText.caption,
                    ),
                  ),
              ],
              if (report.hasSnapshotOrTermsMismatches) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Price, tax or snapshot differences',
                  style: AppText.label.copyWith(color: AppColors.amber),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final diff in [
                  ...report.termsMismatches,
                  ...report.snapshotMismatches,
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Text(
                      '• ${diff['field']}: recorded ${diff['recorded']} vs cloud ${diff['current']}',
                      style: AppText.caption,
                    ),
                  ),
              ],
              if (report.identityConflicts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Identity conflicts',
                  style: AppText.label.copyWith(color: AppColors.error),
                ),
                for (final msg in report.identityConflicts)
                  Text('• $msg', style: AppText.caption),
              ],
              if (report.blockingReasons.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Blocking issues',
                  style: AppText.label.copyWith(color: AppColors.error),
                ),
                for (final msg in report.blockingReasons)
                  Text('• $msg', style: AppText.caption),
              ],
              if (report.localDiff.hasEdits) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Local edits after checkout', style: AppText.label),
                const SizedBox(height: AppSpacing.xs),
                for (final line in report.localDiff.summaryLines)
                  Text('• $line', style: AppText.caption),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'The original invoice will be confirmed first, and your local edits will sync on top of it.',
                  style: AppText.caption,
                ),
              ],
              if (isNeedsReconcile) ...[
                const SizedBox(height: AppSpacing.md),
                if (report.hasStockShortages)
                  CheckboxListTile(
                    key: const ValueKey('reconcile-allow-shortage'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Allow stock shortage'),
                    value: _allowStockShortage,
                    onChanged: _submitting
                        ? null
                        : (v) =>
                              setState(() => _allowStockShortage = v == true),
                  ),
                if (report.hasSnapshotOrTermsMismatches)
                  CheckboxListTile(
                    key: const ValueKey('reconcile-accept-snapshot'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Keep recorded prices & cost snapshots'),
                    value: _acceptRecordedSnapshot,
                    onChanged: _submitting
                        ? null
                        : (v) => setState(
                            () => _acceptRecordedSnapshot = v == true,
                          ),
                  ),
                if (report.localDiff.hasEdits)
                  CheckboxListTile(
                    key: const ValueKey('reconcile-post-original-first'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Post original invoice first, then sync local edits',
                    ),
                    value: _postOriginalBeforeLocalEdits,
                    onChanged: _submitting
                        ? null
                        : (v) => setState(
                            () => _postOriginalBeforeLocalEdits = v == true,
                          ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const ValueKey('reconcile-reason-field'),
                  controller: _reasonController,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Reconciliation reason',
                    hintText: 'Why are you approving this reconciliation?',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
              if (_submitError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _submitError!,
                  style: AppText.caption.copyWith(color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(primaryLabel == null ? 'Close' : 'Cancel'),
        ),
        if (primaryLabel != null)
          FilledButton(
            key: const ValueKey('reconcile-submit-button'),
            onPressed: _canSubmit(report) ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(primaryLabel),
          ),
      ],
    );
  }
}
