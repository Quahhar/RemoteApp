import 'package:flutter/material.dart';

/// Design tokens taken directly from the "WiFi Remote" mockup
/// (`Asset/TrackPad&Keyboard/WiFi Remote.dc.html`): a warm, flat, iOS-style
/// palette on a `#F7F6F4` paper background with a single amber `#F5A623` accent
/// and a coral power button — plus a matching dark palette (same amber accent,
/// warm near-black surfaces) selected by the dark-mode preference.
///
/// Token *names* are kept stable (screens reference them), so re-skinning is
/// mostly a matter of changing values here. The Pro/upgrade colour was retoned
/// to violet so it stays visually distinct from the amber accent.
///
/// Every token is a getter over the active [_Palette]; [setDark] swaps the
/// palette. `RemoteApp` calls it at the top of its build (before any screen
/// builds) whenever the preference changes, and screens re-read the getters on
/// their next build — so tokens must not be captured in `const` expressions.
class AppColors {
  AppColors._();

  static _Palette _p = _light;

  /// Whether the dark palette is active. `RemoteApp` owns this; widgets that
  /// need mode-specific tuning (e.g. the ambient glow) may read it.
  static bool get isDark => identical(_p, _dark);

  static void setDark(bool dark) => _p = dark ? _dark : _light;

  // Surfaces.
  static Color get bg => _p.bg; // paper screen background
  static Color get card => _p.card; // cards / controls
  static Color get fieldBg => _p.fieldBg; // text-field / inset fill
  static Color get inset => _p.inset; // trackpad / sunken surfaces

  // Accent (amber).
  static Color get accent => _p.accent;
  static Color get accentSoft => _p.accentSoft; // pressed / active wash
  static Color get accentSoftPressed => _p.accentSoftPressed;
  static Color get accentText => _p.accentText; // amber text on the wash
  static Color get accentDeep => _p.accentDeep; // deeper amber (badges/icons)

  // Text.
  static Color get textPrimary => _p.textPrimary;
  static Color get textMuted => _p.textMuted;
  static Color get textFaint => _p.textFaint;
  static Color get hintFaint => _p.hintFaint;

  // Pro / upgrade (violet — deliberately distinct from the amber accent).
  static Color get gold => _p.gold; // "Pro" accent (name kept stable)
  static Color get goldSoft => _p.goldSoft; // soft violet wash
  static Color get goldText => _p.goldText; // readable text on the wash

  // Status / actions.
  static Color get green => _p.green; // success ticks
  static Color get powerRed => _p.powerRed; // coral power glyph
  static Color get powerSoftBg => _p.powerSoftBg; // coral button fill
  static Color get powerSoftPressed => _p.powerSoftPressed;

  // Lines & borders.
  static Color get divider => _p.divider; // thin internal lines
  static Color get border => _p.border; // card outlines
  static Color get fieldBorder => _p.fieldBorder; // input / pad outlines
  static Color get navBorder => _p.navBorder; // top of bottom nav

  // D-pad dial.
  static Color get arrowGrey => _p.arrowGrey; // dial arrows
  static Color get dpadArrow => _p.dpadArrow;

  // Bottom-nav inactive icon/label.
  static Color get navInactive => _p.navInactive;
  static Color get navBar => _p.navBar; // translucent paper

  // Soft dot grid on the trackpad surface.
  static Color get dotGrid => _p.dotGrid;

  /// The original mockup palette, unchanged.
  static const _Palette _light = _Palette(
    bg: Color(0xFFF7F6F4),
    card: Color(0xFFFFFFFF),
    fieldBg: Color(0xFFF2F0EC),
    inset: Color(0xFFEFEDE9),
    accent: Color(0xFFF5A623),
    accentSoft: Color(0xFFFBEFD8),
    accentSoftPressed: Color(0xFFF4E2B8),
    accentText: Color(0xFFB07A12),
    accentDeep: Color(0xFFD9920F),
    textPrimary: Color(0xFF1C1B1A),
    textMuted: Color(0xFF8A8798),
    textFaint: Color(0xFF9A9692),
    hintFaint: Color(0xFFB7B3AD),
    gold: Color(0xFF6C4CD6),
    goldSoft: Color(0xFFEDE7FB),
    goldText: Color(0xFF4A2E9E),
    green: Color(0xFF34C759),
    powerRed: Color(0xFFE0795A),
    powerSoftBg: Color(0xFFFBEAE4),
    powerSoftPressed: Color(0xFFF4C9BB),
    divider: Color(0xFFECEAE6),
    border: Color(0xFFECEAE6),
    fieldBorder: Color(0xFFE6E3DE),
    navBorder: Color(0xFFECEAE6),
    arrowGrey: Color(0xFF3A3850),
    dpadArrow: Color(0xFF3A3850),
    navInactive: Color(0xFFB0ACA6),
    navBar: Color(0xF2F7F6F4),
    dotGrid: Color(0xFFDAD7D1),
  );

  /// Dark counterpart: warm near-black surfaces, the same amber accent, and
  /// each soft wash re-toned so it reads as a tint of its accent over the
  /// dark card rather than over white.
  static const _Palette _dark = _Palette(
    bg: Color(0xFF141316),
    card: Color(0xFF201F24),
    fieldBg: Color(0xFF29282E),
    inset: Color(0xFF242329),
    accent: Color(0xFFF5A623),
    accentSoft: Color(0xFF3B2F17),
    accentSoftPressed: Color(0xFF4E3D1C),
    accentText: Color(0xFFF2C879),
    accentDeep: Color(0xFFF5B94A),
    textPrimary: Color(0xFFF2F0ED),
    textMuted: Color(0xFF9A97A5),
    textFaint: Color(0xFF87848E),
    hintFaint: Color(0xFF67646E),
    gold: Color(0xFF9B82E8),
    goldSoft: Color(0xFF2B2540),
    goldText: Color(0xFFC9B8F5),
    green: Color(0xFF34C759),
    powerRed: Color(0xFFE58A6D),
    powerSoftBg: Color(0xFF3A241D),
    powerSoftPressed: Color(0xFF56352A),
    divider: Color(0xFF2C2B31),
    border: Color(0xFF2C2B31),
    fieldBorder: Color(0xFF343339),
    navBorder: Color(0xFF2C2B31),
    arrowGrey: Color(0xFFC9C6DB),
    dpadArrow: Color(0xFFC9C6DB),
    navInactive: Color(0xFF706D78),
    navBar: Color(0xF2141316),
    dotGrid: Color(0xFF3A3941),
  );
}

/// One complete set of colour tokens (see [AppColors] for what each means).
@immutable
class _Palette {
  const _Palette({
    required this.bg,
    required this.card,
    required this.fieldBg,
    required this.inset,
    required this.accent,
    required this.accentSoft,
    required this.accentSoftPressed,
    required this.accentText,
    required this.accentDeep,
    required this.textPrimary,
    required this.textMuted,
    required this.textFaint,
    required this.hintFaint,
    required this.gold,
    required this.goldSoft,
    required this.goldText,
    required this.green,
    required this.powerRed,
    required this.powerSoftBg,
    required this.powerSoftPressed,
    required this.divider,
    required this.border,
    required this.fieldBorder,
    required this.navBorder,
    required this.arrowGrey,
    required this.dpadArrow,
    required this.navInactive,
    required this.navBar,
    required this.dotGrid,
  });

  final Color bg;
  final Color card;
  final Color fieldBg;
  final Color inset;
  final Color accent;
  final Color accentSoft;
  final Color accentSoftPressed;
  final Color accentText;
  final Color accentDeep;
  final Color textPrimary;
  final Color textMuted;
  final Color textFaint;
  final Color hintFaint;
  final Color gold;
  final Color goldSoft;
  final Color goldText;
  final Color green;
  final Color powerRed;
  final Color powerSoftBg;
  final Color powerSoftPressed;
  final Color divider;
  final Color border;
  final Color fieldBorder;
  final Color navBorder;
  final Color arrowGrey;
  final Color dpadArrow;
  final Color navInactive;
  final Color navBar;
  final Color dotGrid;
}
