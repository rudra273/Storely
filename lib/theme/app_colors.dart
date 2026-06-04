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

  // Dark mode: neutral charcoal system — amber accent pops on grey.
  static const darkBg = Color(0xFF161616);
  static const darkSurface = Color(0xFF1F1F1F);
  static const darkSurfaceRaised = Color(0xFF2A2A2A);
  static const darkInput = Color(0xFF252525);
  static const darkInk = Color(0xFFEEEEEE);
  static const darkInkMuted = Color(0xFFA1A1A1);
  static const darkInkFaint = Color(0xFF6B6B6B);
  static const darkBorder = Color(0xFF333333);
  static const darkBorderStrong = Color(0xFF3F3F3F);

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
