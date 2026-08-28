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
  static const background = Color(0xFFF2F8F4);
  static const surface = Colors.white;
  static const paleMint = Color(0xFFE4F7ED);
  static const paleGold = Color(0xFFFFF7DC);
  static const textPrimary = Color(0xFF15352D);
  static const textSecondary = Color(0xFF526B63);
  static const border = Color(0xFFCFE3D8);

  // Aliases preservam os componentes anteriores enquanto a identidade visual
  // migra de azul para verde.
  static const brightBlue = brightGreen;
  static const deepBlue = deepGreen;
  static const paleBlue = paleMint;
}

abstract final class AppTheme {
  static const _colors = ColorScheme.light(
    primary: AppColors.deepGreen,
    onPrimary: Colors.white,
    primaryContainer: AppColors.paleBlue,
    onPrimaryContainer: AppColors.textPrimary,
    secondary: AppColors.brightGreen,
    onSecondary: AppColors.textPrimary,
    secondaryContainer: AppColors.paleMint,
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
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.deepGreen,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      shadowColor: Color(0x24125E4B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: AppColors.border),
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
      fillColor: AppColors.surface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.deepGreen,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.border,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.deepGreen,
        side: const BorderSide(color: AppColors.deepGreen),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.deepGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
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
