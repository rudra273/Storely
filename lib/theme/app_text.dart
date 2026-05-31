import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppText {
  static const display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    color: AppColors.ink,
    height: 1.15,
  );

  static const title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
    height: 1.2,
  );

  static const subtitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.ink,
    height: 1.3,
  );

  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.ink,
    height: 1.4,
  );

  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.inkMuted,
    letterSpacing: 0.8,
    height: 1.2,
  );

  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.inkMuted,
    height: 1.3,
  );

  static TextTheme get textTheme => const TextTheme(
    displayLarge: display,
    titleLarge: title,
    titleMedium: subtitle,
    bodyLarge: body,
    bodyMedium: body,
    labelLarge: label,
    bodySmall: caption,
    labelSmall: caption,
  );
}
