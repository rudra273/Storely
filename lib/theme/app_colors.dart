import 'package:flutter/material.dart';

class AppColors {
  // Brand
  static const navy = Color(0xFF1B2838);
  static const navyLight = Color(0xFF243447);
  static const amber = Color(0xFFF5A623);

  // Text
  static const ink = Color(0xFF1B2838);
  static const inkMuted = Color(0xFF6B7280);
  static const inkFaint = Color(0xFF9CA3AF);

  // Aliases kept for backward compat
  static const textDark = ink;
  static const textMuted = inkMuted;
  static const cream = bg;
  static const creamDark = Color(0xFFECEEF2);

  // Surfaces
  static const bg = Color(0xFFF7F8FA);
  static const surface = Color(0xFFFFFFFF);

  // Borders
  static const border = Color(0xFFECEEF2);
  static const borderStrong = Color(0xFFE2E5EA);

  // Status
  static const success = Color(0xFF16A34A);
  static const error = Color(0xFFEF4444);
  static const warning = amber;
}
