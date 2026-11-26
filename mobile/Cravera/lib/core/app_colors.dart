import 'package:flutter/material.dart';

/// The one place colors are defined. Screens use these names, never hex values,
/// so a palette change happens here and every screen follows.
///
/// "Warm dark": warm charcoal surfaces, an ember (terracotta) accent for the
/// main action, sage for secondary and "good" states, cream text.
class AppColors {
  // Surfaces, darkest to lightest. Each level sits "above" the one before it.
  static const background = Color(0xFF15110F); // app background
  static const surface = Color(0xFF211B18); // cards, inputs, nav bar
  static const surface2 = Color(0xFF2C2420); // raised: sheets, dialogs, chips
  static const surface3 = Color(0xFF372D28); // highest: pressed, selected rows
  static const border = Color(0xFF3D332D);

  // Brand.
  static const accent = Color(0xFFE8683F); // ember: the main action on a screen
  static const accentPressed = Color(0xFFC9542E);
  static const onAccent = Color(0xFF1C120D); // text/icons on ember (AA contrast)
  static const sage = Color(0xFFA7C4A0); // secondary accent, "open now", success
  static const gold = Color(0xFFF2B544); // star ratings
  static const danger = Color(0xFFF0776B); // sign out, destructive actions

  // Text, strongest to weakest. All pass WCAG AA on [background] and [surface].
  static const textPrimary = Color(0xFFF6EEE6);
  static const textSecondary = Color(0xFFD6C8BC);
  static const textMuted = Color(0xFFA39488);

  /// Ember at low strength, for tinted backgrounds behind accent content.
  static Color get accentSoft => accent.withValues(alpha: 0.16);
}
