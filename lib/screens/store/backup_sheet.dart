import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/backup_service.dart';
import '../../services/cloud_service.dart';
import '../../theme/app_theme.dart';

/// Back up all shop data to one file, or restore from one.
/// Pops `true` after a restore (callers should reload everything).
class BackupSheet extends StatefulWidget {
  const BackupSheet({super.key});

  @override
  State<BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<BackupSheet> {
  DateTime? _lastBackup;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    BackupService.lastBackupAt().then((value) {
      if (mounted) setState(() => _lastBackup = value);
    });
  }

  Future<void> _backup() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await BackupService.shareBackup();
      final last = await BackupService.lastBackupAt();
      if (!mounted) return;
      setState(() => _lastBackup = last);
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Backup failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (!mounted || bytes == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final (info, dbBytes) = await BackupService.readBackup(bytes);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.restore_rounded, size: 32),
          title: const Text('Replace data on this phone?'),
          content: Text(
            '${info.shopName}\n'
            'Backed up ${DateFormat('dd MMM yyyy, hh:mm a').format(info.createdAt)}\n'
            '${info.products} products · ${info.bills} bills · '
            '${info.customers} customers\n\n'
            'Everything on this phone now is replaced by this backup. '
            'A copy of the current data is kept on the phone first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await BackupService.restore(dbBytes);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on BackupException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Restore failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = CloudService.instance.state.value.isSignedIn;
    final last = _lastBackup;
    final stale = last == null || DateTime.now().difference(last).inDays >= 7;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Backup & restore', style: AppText.title),
            const SizedBox(height: AppSpacing.xs),
            Text(
              last == null
                  ? 'No backup yet. If this phone is lost, so is the data.'
                  : 'Last backup ${DateFormat('dd MMM yyyy, hh:mm a').format(last)}',
              style: AppText.caption.copyWith(
                color: stale ? AppColors.error : null,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              key: const ValueKey('backup-now'),
              onPressed: _busy ? null : _backup,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Back up now'),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Makes one file with all products, bills, customers and '
              'settings. Save it to Google Drive, WhatsApp it to yourself, '
              'or keep it in Files.',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: _busy || signedIn ? null : _restore,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Restore from a backup file'),
            ),
            if (signedIn) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'This phone syncs with cloud, so your data is already safe '
                'there. Sign out of cloud to restore a file instead.',
                style: AppText.caption,
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: AppSpacing.md),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _message!,
                style: AppText.caption.copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
