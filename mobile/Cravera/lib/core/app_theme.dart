import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        surface: AppColors.surface,
        primary: AppColors.accent,
        secondary: AppColors.accent,
        onSurface: AppColors.textPrimary,
        onPrimary: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        // Let the radiant background bleed through.
        color: AppColors.surface2.withValues(alpha: 0.55),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.45), width: 1),
        ),
      ),
      textTheme: GoogleFonts.outfitTextTheme(base.textTheme).copyWith(
        // Structured hierarchy: clearer titles vs body.
        displaySmall: GoogleFonts.outfit(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        headlineSmall: GoogleFonts.outfit(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w800, letterSpacing: -0.2),
        titleMedium: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        bodyLarge: GoogleFonts.outfit(fontWeight: FontWeight.w500, height: 1.25),
        bodyMedium: GoogleFonts.outfit(fontWeight: FontWeight.w500, height: 1.25),
        labelLarge: GoogleFonts.outfit(fontWeight: FontWeight.w700),
      ).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2.withValues(alpha: 0.50),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.45), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.45), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AppColors.accent, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.textPrimary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: AppColors.border.withValues(alpha: 0.45), width: 1),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surface2,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
      ),
    );
  }
}
