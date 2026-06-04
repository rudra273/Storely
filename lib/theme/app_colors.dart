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

  // Dark mode: pure dark/grey base with the same yellow accent.
  static const darkBg = Color(0xFF000000);
  static const darkSurface = navy;
  static const darkSurfaceRaised = navyLight;
  static const darkInk = Color(0xFFF5F5F5);
  static const darkInkMuted = Color(0xFFB8B8B8);
  static const darkInkFaint = Color(0xFF7A7A7A);
  static const darkBorder = Color(0xFF2A2A2A);
  static const darkBorderStrong = Color(0xFF3A3A3A);

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color bgOf(BuildContext context) => isDark(context) ? darkBg : bg;
  static Color surfaceOf(BuildContext context) =>
      isDark(context) ? darkSurface : surface;
  static Color raisedSurfaceOf(BuildContext context) =>
      isDark(context) ? darkSurfaceRaised : surface;
  static Color inkOf(BuildContext context) => isDark(context) ? darkInk : ink;
  static Color inkMutedOf(BuildContext context) =>
      isDark(context) ? darkInkMuted : inkMuted;
  static Color inkFaintOf(BuildContext context) =>
      isDark(context) ? darkInkFaint : inkFaint;
  static Color borderOf(BuildContext context) =>
      isDark(context) ? darkBorder : border;
  static Color borderStrongOf(BuildContext context) =>
      isDark(context) ? darkBorderStrong : borderStrong;
  static Color brandOf(BuildContext context) => isDark(context) ? amber : navy;
  static Color softBgOf(BuildContext context) =>
      isDark(context) ? darkSurfaceRaised : bg;
}
