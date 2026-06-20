import 'package:flutter/material.dart';

/// App-wide dark theme. Colors are intentionally conservative here; the Remote
/// screen will be retuned to match the supplied design mockup.
class AppTheme {
  AppTheme._();

  static const Color seed = Color(0xFF7C4DFF);
  static const Color _bg = Color(0xFF0E0E12);
  static const Color _surface = Color(0xFF16161D);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(surface: _surface);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: _bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surface,
        indicatorColor: seed.withValues(alpha: 0.24),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
