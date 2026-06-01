import 'package:flutter/material.dart';

import '../app_colors.dart';
import '../app_spacing.dart';

class AppInfoSection {
  final String title;
  final List<String> points;

  const AppInfoSection({required this.title, required this.points});
}

class AppInfoAction extends StatelessWidget {
  final String title;
  final String? intro;
  final List<AppInfoSection> sections;
  final Color? iconColor;

  const AppInfoAction({
    super.key,
    required this.title,
    required this.sections,
    this.intro,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Help',
      icon: Icon(Icons.info_outline_rounded, color: iconColor),
      onPressed: () => showAppInfoDialog(
        context,
        title: title,
        intro: intro,
        sections: sections,
      ),
    );
  }
}

Future<void> showAppInfoDialog(
  BuildContext context, {
  required String title,
  String? intro,
  required List<AppInfoSection> sections,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(
        Icons.info_outline_rounded,
        color: AppColors.amber,
        size: 32,
      ),
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (intro != null && intro.trim().isNotEmpty) ...[
              Text(
                intro,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            ...sections.map(_InfoSectionView.new),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

class _InfoSectionView extends StatelessWidget {
  final AppInfoSection section;

  const _InfoSectionView(this.section);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...section.points.map(
            (point) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    decoration: BoxDecoration(
                      color: AppColors.amber,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
