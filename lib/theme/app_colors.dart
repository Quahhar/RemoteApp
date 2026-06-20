import 'package:flutter/material.dart';

/// Design tokens taken directly from the Remote Control mockup.
class AppColors {
  AppColors._();

  // Text.
  static const Color textPrimary = Color(0xFF26243A);
  static const Color textSecondary = Color(0xFF5A5870);
  static const Color textMuted = Color(0xFF6B6982);
  static const Color label = Color(0xFF4A4860);
  static const Color icon = Color(0xFF3A3850);

  // Accents.
  static const Color accent = Color(0xFF3A5BD9); // active tab / primary
  static const Color powerRed = Color(0xFFE8493A);
  static const Color powerBg = Color(0xFFFDEEE9);
  static const Color statusGreen = Color(0xFF2EC06A);
  static const Color statusGrey = Color(0xFFB8B6C4);

  // Frosted surfaces (white at various opacities).
  static const Color cardFill = Color(0x6BFFFFFF); // 0.42
  static const Color cardBorder = Color(0x8CFFFFFF); // 0.55
  static const Color softFill = Color(0x38FFFFFF); // 0.22
  static const Color softBorder = Color(0x52FFFFFF); // 0.32
  static const Color navBar = Color(0xC7FFFFFF); // 0.78
  static const Color okFill = Color(0xFFFFFFFF);

  /// Halo behind the connected status dot.
  static const Color statusHaloGreen = Color(0x2E2EC06A); // rgba(46,192,106,.18)

  /// Full-screen background gradient (mockup: linear-gradient(170deg, …)).
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment(-0.17, -1.0),
    end: Alignment(0.17, 1.0),
    colors: [
      Color(0xFFD2C2EF),
      Color(0xFFBCC0EF),
      Color(0xFF9FB1EA),
      Color(0xFF8FA8E8),
    ],
    stops: [0.0, 0.38, 0.70, 1.0],
  );
}
