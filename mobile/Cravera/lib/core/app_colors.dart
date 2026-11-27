import 'package:flutter/material.dart';

/// The one place colors are defined. Screens use these names, never hex values,
/// so a palette change happens here and every screen follows.
///
/// "Market" (maintainer's pick of three mockups, 2026-11-26): warm cream
/// surfaces, olive green for the main action, tomato for "why this pick",
/// warm dark-brown text. Every text color passes WCAG AA (4.5:1) on
/// [background] and [surface].
class AppColors {
  // Surfaces, lightest to darkest. Each level sits "above" the one before it.
  static const background = Color(0xFFFBF6EE); // app background (cream)
  static const surface = Color(0xFFFFFFFF); // cards, inputs, nav bar
  static const surface2 = Color(0xFFF4EDE2); // raised: sheets, dialogs, chips
  static const surface3 = Color(0xFFEAE1D3); // pressed, selected rows, disabled
  static const border = Color(0xFFE3D9CB);

  // Brand.
  static const accent = Color(0xFF4F6B2E); // olive: the main action on a screen (6.0:1 with white)
  static const accentLight = Color(0xFF8FA86A); // highlights in gradients (orb, avatar)
  static const accentPressed = Color(0xFF3F5724);
  static const onAccent = Color(0xFFFFFFFF); // text/icons on olive
  static const tomato = Color(0xFFB4472A); // "why this pick" (5.0:1 on cream)
  static const sage = Color(0xFF3F6B4A); // secondary: "open now", distance, success (5.9:1)
  static const gold = Color(0xFF8A5A00); // star ratings only (5.5:1)
  static const danger = Color(0xFFB3261E); // sign out, destructive actions

  // Text, strongest to weakest. All pass WCAG AA on [background] and [surface].
  static const textPrimary = Color(0xFF2A2420);
  static const textSecondary = Color(0xFF4A413A);
  static const textMuted = Color(0xFF6B6058);

  // Glass: a light see-through base with a faint dark edge (see widgets/glass.dart).
  static const glassBase = Color(0xD9FFFFFF); // white at 85%
  static const glassEdge = Color(0x1A2A2420); // text color at 10%

  /// Over a photo: a cream veil so labels stay readable on any image.
  static const scrim = Color(0xDBFBF6EE);

  /// Olive at low strength, for tinted backgrounds behind accent content.
  static Color get accentSoft => accent.withValues(alpha: 0.12);
}
