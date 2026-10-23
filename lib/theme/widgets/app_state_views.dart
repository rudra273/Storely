import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_radius.dart';
import '../app_spacing.dart';
import '../app_text.dart';

/// Centered "nothing here yet" message with an optional primary action.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  final Widget? secondaryAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.secondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: AppRadius.lgRadius,
              ),
              child: Icon(icon, size: 36, color: AppColors.inkFaintOf(context)),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.title.copyWith(color: AppColors.inkOf(context)),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(
                  color: AppColors.inkMutedOf(context),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: onAction,
                icon: Icon(actionIcon ?? Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
            if (secondaryAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              secondaryAction!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Something failed to load: a plain message plus Try again. Technical
/// details are tucked behind "Details" instead of shown raw.
class AppErrorState extends StatelessWidget {
  final String title;
  final Object? error;
  final VoidCallback? onRetry;

  const AppErrorState({
    super.key,
    this.title = 'Could not load this',
    this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.subtitle.copyWith(color: AppColors.inkOf(context)),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your data is safe. Please try again.',
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(
                color: AppColors.inkMutedOf(context),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
            if (error != null)
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Details'),
                    content: SelectableText('$error'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Details'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Grey placeholder rows shown while a list loads (cheaper and calmer than
/// a spinner in the middle of the screen).
class AppSkeletonList extends StatelessWidget {
  final int rows;
  final double rowHeight;

  const AppSkeletonList({super.key, this.rows = 6, this.rowHeight = 72});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.borderOf(context);
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: rows,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => Semantics(
        label: i == 0 ? 'Loading' : null,
        child: Container(
          height: rowHeight,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.6),
            borderRadius: AppRadius.mdRadius,
          ),
        ),
      ),
    );
  }
}

/// Short user-facing text for an exception in a snackbar.
String friendlyError(Object error) {
  final text = error.toString().replaceFirst(
    RegExp(
      r'^(Exception|StateError|Bad state|Invalid argument\(s\)|ArgumentError):\s*',
    ),
    '',
  );
  return text.length > 160 ? '${text.substring(0, 157)}…' : text;
}
