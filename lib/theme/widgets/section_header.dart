import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_text.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Optional overflow (3-dot) menu shown to the right of the action label,
  /// e.g. for per-section display settings.
  final VoidCallback? onMenu;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: AppText.title.copyWith(fontSize: 15),
        ),
        const Spacer(),
        if (actionLabel != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.amber,
              ),
            ),
          ),
        if (onMenu != null)
          IconButton(
            onPressed: onMenu,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(
              Icons.more_vert_rounded,
              size: 20,
              color: AppColors.inkMutedOf(context),
            ),
          ),
      ],
    );
  }
}
