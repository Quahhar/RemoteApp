import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Flat, light theme matching the "WiFi Remote" mockup: an `#f4f4f6` screen,
/// white cards, a single blue accent and the platform's system font (SF on iOS,
/// Roboto on Android — i.e. the mockup's `system-ui`).
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.accent,
        surface: AppColors.bg,
        onSurface: AppColors.textPrimary,
      ),
    );

    return base.copyWith(
      // No GoogleFonts: the system font is what the mockup uses.
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      snackBarTheme:
          const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
