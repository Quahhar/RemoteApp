import 'package:flutter/material.dart';

/// Design tokens taken directly from the "WiFi Remote" mockup: a flat, light,
/// iOS-style palette on an `#f4f4f6` screen with a single `#2f6bf6` blue accent.
class AppColors {
  AppColors._();

  // Surfaces.
  static const Color bg = Color(0xFFF4F4F6); // screen background
  static const Color card = Color(0xFFFFFFFF); // white cards / controls
  static const Color fieldBg = Color(0xFFF4F4F6); // text-field fill

  // Accent.
  static const Color accent = Color(0xFF2F6BF6);
  static const Color accentSoft = Color(0xFFEEF3FF); // pressed / active wash
  static const Color accentSoftPressed = Color(0xFFDDE7FF);

  // Text.
  static const Color textPrimary = Color(0xFF1C1C1E);
  static const Color textMuted = Color(0xFF8A8A8E);
  static const Color textFaint = Color(0xFF9A9AA0);
  static const Color hintFaint = Color(0xFFC2C2C8);

  // Status / actions.
  static const Color green = Color(0xFF34C759);
  static const Color powerRed = Color(0xFFFF3B30);
  static const Color powerSoftBg = Color(0xFFFFECEC);

  // Lines & borders.
  static const Color divider = Color(0xFFF0F0F2); // thin internal lines
  static const Color border = Color(0xFFEDEDF1); // OK button / outlines
  static const Color navBorder = Color(0xFFE9E9EE); // top of bottom nav

  // D-pad triangles.
  static const Color arrowGrey = Color(0xFFB4B4BB);

  // Bottom-nav inactive icon/label.
  static const Color navInactive = Color(0xFF9A9AA0);
  static const Color navBar = Color(0xF2FFFFFF); // translucent white

  // Soft dot grid on the trackpad surface.
  static const Color dotGrid = Color(0xFFECECF0);
}
