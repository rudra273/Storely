import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_text.dart';

export 'app_colors.dart';
export 'app_spacing.dart';
export 'app_radius.dart';
export 'app_shadows.dart';
export 'app_text.dart';
export 'widgets/app_card.dart';
export 'widgets/compact_list_row.dart';
export 'widgets/section_header.dart';
export 'widgets/status_pill.dart';
export 'widgets/app_screen_header.dart';
export 'widgets/app_info_action.dart';

class StorelyTheme {
  static ThemeData light() => _build(
    brightness: Brightness.light,
    bg: AppColors.bg,
    surface: AppColors.surface,
    raisedSurface: AppColors.surface,
    ink: AppColors.ink,
    inkMuted: AppColors.inkMuted,
    inkFaint: AppColors.inkFaint,
    border: AppColors.border,
    borderStrong: AppColors.borderStrong,
    primary: AppColors.navy,
    primaryContainer: AppColors.navyLight,
    onPrimary: Colors.white,
    navSurface: Colors.white,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    bg: AppColors.darkBg,
    surface: AppColors.darkSurface,
    raisedSurface: AppColors.darkSurfaceRaised,
    ink: AppColors.darkInk,
    inkMuted: AppColors.darkInkMuted,
    inkFaint: AppColors.darkInkFaint,
    border: AppColors.darkBorder,
    borderStrong: AppColors.darkBorderStrong,
    primary: AppColors.amber,
    primaryContainer: AppColors.darkSurfaceRaised,
    onPrimary: Colors.black,
    navSurface: AppColors.darkSurface,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color raisedSurface,
    required Color ink,
    required Color inkMuted,
    required Color inkFaint,
    required Color border,
    required Color borderStrong,
    required Color primary,
    required Color primaryContainer,
    required Color onPrimary,
    required Color navSurface,
  }) {
    final isDark = brightness == Brightness.dark;
    final baseTextTheme = AppText.textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
      decorationColor: ink,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardColor: surface,
      textTheme: baseTextTheme,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: isDark ? AppColors.darkInk : Colors.white,
        secondary: AppColors.amber,
        onSecondary: Colors.black,
        secondaryContainer: isDark
            ? const Color(0xFF3A2A00)
            : const Color(0xFFFFF3D6),
        onSecondaryContainer: isDark
            ? const Color(0xFFFFE4A3)
            : const Color(0xFF6B4D00),
        tertiary: const Color(0xFF0D9488),
        onTertiary: Colors.white,
        tertiaryContainer: isDark
            ? const Color(0xFF103B36)
            : const Color(0xFFCCFBF1),
        onTertiaryContainer: isDark
            ? const Color(0xFF99F6E4)
            : const Color(0xFF0D5549),
        error: AppColors.error,
        onError: Colors.white,
        surface: surface,
        onSurface: ink,
        surfaceContainerHighest: raisedSurface,
        onSurfaceVariant: inkMuted,
        outline: borderStrong,
        outlineVariant: border,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: isDark ? AppColors.darkBg : AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: Colors.white,
        ),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.light,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: navSurface,
        selectedItemColor: primary,
        unselectedItemColor: inkMuted,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdRadius,
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkInput : raisedSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdRadius,
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: TextStyle(color: inkFaint, fontSize: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: borderStrong),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.amber,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 4,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: AppText.caption.copyWith(
          color: inkMuted,
          fontWeight: FontWeight.w800,
        ),
        dataTextStyle: AppText.body.copyWith(color: ink),
        headingRowColor: WidgetStatePropertyAll(raisedSurface),
        dataRowColor: WidgetStatePropertyAll(surface),
        dividerThickness: 1,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        textStyle: AppText.body.copyWith(color: ink),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: raisedSurface,
          foregroundColor: inkMuted,
          selectedBackgroundColor: primary,
          selectedForegroundColor: onPrimary,
          side: BorderSide(color: borderStrong),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: raisedSurface,
        selectedColor: AppColors.amber.withValues(alpha: isDark ? 0.22 : 0.12),
        labelStyle: TextStyle(color: ink),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.smRadius),
        side: BorderSide(color: border),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkSurfaceRaised : AppColors.navy,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
        backgroundColor: surface,
        titleTextStyle: AppText.title.copyWith(color: ink),
        contentTextStyle: AppText.body.copyWith(color: inkMuted),
      ),
      iconTheme: IconThemeData(color: ink),
    );
  }
}
