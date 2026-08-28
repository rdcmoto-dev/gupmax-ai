import 'package:flutter/material.dart';

abstract final class AppColors {
  static const brightGreen = Color(0xFF62DFA8);
  static const deepGreen = Color(0xFF125E4B);
  static const forest = Color(0xFF083D32);
  static const gold = Color(0xFFD7B44A);
  static const lightGold = Color(0xFFF1D77B);
  static const midnightBlue = Color(0xFF03162F);
  static const oceanBlue = Color(0xFF063F69);
  static const electricBlue = Color(0xFF0B91C9);
  static const cyanGlow = Color(0xFF53D9F2);
  static const background = Color(0xFF03162F);
  static const surface = Color(0xFF0A2C4D);
  static const raisedSurface = Color(0xFF103C62);
  static const paleMint = Color(0xFFE4F7ED);
  static const paleGold = Color(0xFFFFF7DC);
  static const textPrimary = Color(0xFFF4FAFF);
  static const textSecondary = Color(0xFFB9D4E8);
  static const border = Color(0xFF35739A);

  // Aliases preservam componentes anteriores dentro da identidade azul,
  // verde-claro e dourada.
  static const brightBlue = brightGreen;
  static const deepBlue = deepGreen;
  static const paleBlue = paleMint;
}

abstract final class AppTheme {
  static const _colors = ColorScheme.dark(
    primary: AppColors.brightGreen,
    onPrimary: AppColors.midnightBlue,
    primaryContainer: AppColors.deepGreen,
    onPrimaryContainer: Colors.white,
    secondary: AppColors.brightGreen,
    onSecondary: AppColors.midnightBlue,
    secondaryContainer: AppColors.oceanBlue,
    onSecondaryContainer: Colors.white,
    tertiary: AppColors.gold,
    onTertiary: AppColors.midnightBlue,
    tertiaryContainer: AppColors.oceanBlue,
    onTertiaryContainer: Colors.white,
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
      fontFamily: 'Segoe UI',
      fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
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
      elevation: 5,
      shadowColor: Color(0x77000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: AppColors.gold, width: 1.2),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.deepGreen, width: 2),
      ),
      filled: true,
      fillColor: AppColors.raisedSurface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brightGreen,
        foregroundColor: AppColors.midnightBlue,
        disabledBackgroundColor: AppColors.border,
        elevation: 5,
        side: const BorderSide(color: AppColors.lightGold, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: AppColors.electricBlue,
        side: const BorderSide(color: AppColors.lightGold, width: 1.3),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.lightGold,
        backgroundColor: AppColors.oceanBlue.withValues(alpha: 0.72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.raisedSurface,
      selectedColor: AppColors.deepGreen,
      secondarySelectedColor: AppColors.deepGreen,
      side: const BorderSide(color: AppColors.gold),
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
      backgroundColor: AppColors.midnightBlue,
      indicatorColor: AppColors.deepGreen,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
    iconTheme: const IconThemeData(color: AppColors.cyanGlow),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.brightGreen,
      foregroundColor: AppColors.midnightBlue,
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
        side: BorderSide(color: AppColors.gold),
      ),
    ),
  );
}
