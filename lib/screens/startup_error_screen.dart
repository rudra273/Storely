import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../theme/app_theme.dart';

/// Shown instead of a blank screen when the app cannot start (usually the
/// local database failing to open or upgrade). Data is never deleted here:
/// the shopkeeper can retry, copy the error for support, or save a copy of
/// the database file before anything else is tried.
class StartupErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace? stackTrace;
  final Future<void> Function() onRetry;

  const StartupErrorApp({
    super.key,
    required this.error,
    required this.onRetry,
    this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: StorelyTheme.light(),
      darkTheme: StorelyTheme.dark(),
      home: StartupErrorScreen(
        error: error,
        stackTrace: stackTrace,
        onRetry: onRetry,
      ),
    );
  }
}

class StartupErrorScreen extends StatefulWidget {
  final Object error;
  final StackTrace? stackTrace;
  final Future<void> Function() onRetry;

  const StartupErrorScreen({
    super.key,
    required this.error,
    required this.onRetry,
    this.stackTrace,
  });

  @override
  State<StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<StartupErrorScreen> {
  bool _busy = false;

  String get _details => [
    'Storely could not start.',
    'Error: ${widget.error}',
    if (widget.stackTrace != null)
      widget.stackTrace.toString().split('\n').take(12).join('\n'),
  ].join('\n');

  Future<void> _retry() async {
    setState(() => _busy = true);
    await widget.onRetry();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _details));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Error details copied')));
  }

  /// Shares the raw database file so nothing is lost whatever happens next.
  Future<void> _saveData() async {
    try {
      final path = await DatabaseHelper.databasePath();
      if (!File(path).existsSync()) {
        throw StateError('No data file found on this phone.');
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: 'Storely data file (keep safe)',
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not share: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          children: [
            const SizedBox(height: AppSpacing.xxxl),
            const Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Storely could not start',
              textAlign: TextAlign.center,
              style: AppText.title,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your bills and products are still on this phone. Try again. '
              'If it keeps happening, save a copy of your data and send the '
              'error details to support.',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _busy ? null : _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_busy ? 'Starting…' : 'Try again'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _saveData,
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Save a copy of my data'),
            ),
            TextButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy error details'),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SelectableText('${widget.error}', style: AppText.caption),
            ),
          ],
        ),
      ),
    );
  }
}
