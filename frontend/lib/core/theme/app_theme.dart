import 'package:flutter/material.dart';

abstract final class AppColors {
  static const brightBlue = Color(0xFF29B6F6);
  static const deepBlue = Color(0xFF1268B3);
  static const gold = Color(0xFFD4AF37);
  static const lightGold = Color(0xFFF2D675);
  static const background = Color(0xFFF7FAFC);
  static const surface = Colors.white;
  static const paleBlue = Color(0xFFE8F6FD);
  static const paleGold = Color(0xFFFFF8E1);
  static const textPrimary = Color(0xFF1F2937);
  static const textSecondary = Color(0xFF526579);
  static const border = Color(0xFFD8E4EC);
}

abstract final class AppTheme {
  static const _colors = ColorScheme.light(
    primary: AppColors.deepBlue,
    onPrimary: Colors.white,
    primaryContainer: AppColors.paleBlue,
    onPrimaryContainer: AppColors.textPrimary,
    secondary: AppColors.brightBlue,
    onSecondary: AppColors.textPrimary,
    secondaryContainer: Color(0xFFDDF3FD),
    onSecondaryContainer: AppColors.textPrimary,
    tertiary: AppColors.gold,
    onTertiary: AppColors.textPrimary,
    tertiaryContainer: AppColors.paleGold,
    onTertiaryContainer: AppColors.textPrimary,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.deepBlue,
    outlineVariant: AppColors.border,
  );

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: _colors,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: Typography.material2021().black.apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.deepBlue,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      shadowColor: Color(0x1A1268B3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.deepBlue, width: 2),
      ),
      filled: true,
      fillColor: AppColors.surface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.deepBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.border,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.deepBlue,
        side: const BorderSide(color: AppColors.deepBlue),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.deepBlue),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.paleBlue,
      secondarySelectedColor: AppColors.paleBlue,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.deepBlue
            : AppColors.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.brightBlue.withValues(alpha: 0.55)
            : AppColors.border,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.brightBlue,
      linearTrackColor: AppColors.paleBlue,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.paleBlue,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
    iconTheme: const IconThemeData(color: AppColors.deepBlue),
  );
}
