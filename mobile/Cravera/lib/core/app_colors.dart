import 'package:flutter/material.dart';

/// The one place colors are defined. Screens use these names, never hex values,
/// so a palette change happens here and every screen follows.
///
/// "Violet dark": cool near-black surfaces, a violet accent for the main
/// action, sage for secondary and "good" states, soft white text.
class AppColors {
  // Surfaces, darkest to lightest. Each level sits "above" the one before it.
  static const background = Color(0xFF0F0E14); // app background
  static const surface = Color(0xFF1A1922); // cards, inputs, nav bar
  static const surface2 = Color(0xFF24222E); // raised: sheets, dialogs, chips
  static const surface3 = Color(0xFF2E2B3A); // highest: pressed, selected rows
  static const border = Color(0xFF383546);

  // Brand.
  static const accent = Color(0xFF8B7CF6); // violet: the main action on a screen
  static const accentLight = Color(0xFFB7ADFF); // highlights in gradients (orb, avatar)
  static const accentPressed = Color(0xFF7363E6);
  static const onAccent = Color(0xFF12101F); // text/icons on violet (AA contrast)
  static const sage = Color(0xFFA7C4A0); // secondary accent, "open now", success
  static const gold = Color(0xFFF2C14E); // star ratings only
  static const danger = Color(0xFFF0776B); // sign out, destructive actions

  // Text, strongest to weakest. All pass WCAG AA on [background] and [surface].
  static const textPrimary = Color(0xFFF1EFF7);
  static const textSecondary = Color(0xFFCBC7D9);
  static const textMuted = Color(0xFF9A96AB);

  // Glass: a dark see-through base with a faint light edge (see widgets/glass.dart).
  static const glassBase = Color(0x8C1A1922); // surface at 55% opacity
  static const glassEdge = Color(0x1FFFFFFF); // white at 12%

  /// Violet at low strength, for tinted backgrounds behind accent content.
  static Color get accentSoft => accent.withValues(alpha: 0.16);
}
