import 'package:flutter/material.dart';

abstract final class AppColors {
  static const brightGreen = Color(0xFF4DA6FF);
  static const deepGreen = Color(0xFF1478F5);
  static const forest = Color(0xFF082B52);
  static const gold = Color(0xFF62B8FF);
  static const lightGold = Color(0xFFA7D6FF);
  static const midnightBlue = Color(0xFF061A33);
  static const oceanBlue = Color(0xFF1478F5);
  static const electricBlue = Color(0xFF238CF6);
  static const cyanGlow = Color(0xFF61C8FF);
  static const violet = Color(0xFF1478F5);
  static const paleLavender = Color(0xFFE1F1FF);
  static const background = Color(0xFFEAF6FF);
  static const surface = Color(0xFFF8FCFF);
  static const raisedSurface = Color(0xFFFFFFFF);
  static const mutedSurface = Color(0xFFDCEEFF);
  static const paleMint = Color(0xFFEAF6FF);
  static const paleGold = Color(0xFFF0F8FF);
  static const textPrimary = Color(0xFF0A2040);
  static const textSecondary = Color(0xFF506784);
  static const border = Color(0xFFB4D8F7);

  // Aliases preservam componentes anteriores dentro da identidade azul,
  // verde-claro e dourada.
  static const brightBlue = brightGreen;
  static const deepBlue = deepGreen;
  static const paleBlue = paleMint;
}

abstract final class AppTheme {
  static const _colors = ColorScheme.light(
    primary: AppColors.violet,
    onPrimary: Colors.white,
    primaryContainer: AppColors.paleLavender,
    onPrimaryContainer: AppColors.midnightBlue,
    secondary: AppColors.electricBlue,
    onSecondary: Colors.white,
    secondaryContainer: AppColors.raisedSurface,
    onSecondaryContainer: AppColors.midnightBlue,
    tertiary: AppColors.gold,
    onTertiary: AppColors.midnightBlue,
    tertiaryContainer: AppColors.paleGold,
    onTertiaryContainer: AppColors.midnightBlue,
    surface: AppColors.surface,
    surfaceDim: AppColors.raisedSurface,
    surfaceBright: AppColors.paleLavender,
    surfaceContainerLowest: AppColors.surface,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.mutedSurface,
    surfaceContainerHigh: AppColors.raisedSurface,
    surfaceContainerHighest: AppColors.paleLavender,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.oceanBlue,
    outlineVariant: AppColors.border,
  );

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: _colors,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    textTheme: Typography.material2021().black.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Segoe UI', 'Roboto', 'Arial', 'sans-serif'],
    ).copyWith(
      headlineMedium: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.7,
        color: AppColors.textPrimary,
      ),
      titleLarge: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
      ),
      titleMedium: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
      bodyLarge: const TextStyle(fontSize: 16, height: 1.45),
      bodyMedium: const TextStyle(fontSize: 14, height: 1.45),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.midnightBlue,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shadowColor: Color(0x2B1478F5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.violet, width: 2),
      ),
      filled: true,
      fillColor: AppColors.raisedSurface,
      labelStyle: TextStyle(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: TextStyle(
        color: AppColors.midnightBlue,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: TextStyle(color: AppColors.textSecondary),
      iconColor: AppColors.oceanBlue,
      prefixIconColor: AppColors.oceanBlue,
      suffixIconColor: AppColors.oceanBlue,
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      textStyle: TextStyle(color: AppColors.textPrimary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.raisedSurface,
        labelStyle: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.violet,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.border,
        elevation: 4,
        shadowColor: AppColors.cyanGlow,
        side: const BorderSide(color: AppColors.cyanGlow, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.oceanBlue,
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.electricBlue, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.oceanBlue,
        backgroundColor: AppColors.mutedSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.paleLavender,
      secondarySelectedColor: AppColors.paleLavender,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.violet
            : AppColors.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.violet.withValues(alpha: 0.35)
            : AppColors.border,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.brightBlue,
      linearTrackColor: AppColors.paleBlue,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.midnightBlue,
      indicatorColor: AppColors.violet,
    ),
    listTileTheme: const ListTileThemeData(
      tileColor: Colors.transparent,
      textColor: AppColors.textPrimary,
      iconColor: AppColors.oceanBlue,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
    iconTheme: const IconThemeData(color: AppColors.oceanBlue),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.violet,
      foregroundColor: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
        side: BorderSide(color: AppColors.lightGold, width: 1.5),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(22)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.midnightBlue,
      contentTextStyle: TextStyle(color: Colors.white),
      actionTextColor: AppColors.lightGold,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
