import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Flat theme matching the "WiFi Remote" mockup: white cards, a single amber
/// accent and the platform's system font (SF on iOS, Roboto on Android — i.e.
/// the mockup's `system-ui`). Light and dark variants read the same
/// [AppColors] tokens, so [AppColors.setDark] must be called *before* the
/// matching getter (see `RemoteApp`).
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: brightness,
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
      appBarTheme: AppBarTheme(
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
