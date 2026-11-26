import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Shared shapes, so every card, input and sheet rounds the same way.
class AppRadius {
  static const small = 12.0; // chips, small buttons
  static const medium = 18.0; // inputs, list rows
  static const large = 28.0; // cards, sheets
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    // Fraunces (a soft serif) for big headings gives a warm, editorial feel
    // that suits food; Outfit stays for everything else because it reads well small.
    final body = GoogleFonts.outfitTextTheme(base.textTheme);
    TextStyle display(TextStyle? s, double spacing) =>
        GoogleFonts.fraunces(textStyle: s, fontWeight: FontWeight.w700, letterSpacing: spacing);

    final textTheme = body
        .copyWith(
          displaySmall: display(body.displaySmall, -1.0),
          headlineMedium: display(body.headlineMedium, -0.6),
          headlineSmall: display(body.headlineSmall, -0.4),
          titleLarge: GoogleFonts.outfit(textStyle: body.titleLarge, fontWeight: FontWeight.w700, letterSpacing: -0.2),
          titleMedium: GoogleFonts.outfit(textStyle: body.titleMedium, fontWeight: FontWeight.w600),
          bodyLarge: GoogleFonts.outfit(textStyle: body.bodyLarge, fontWeight: FontWeight.w400, height: 1.35),
          bodyMedium: GoogleFonts.outfit(textStyle: body.bodyMedium, fontWeight: FontWeight.w400, height: 1.35),
          labelLarge: GoogleFonts.outfit(textStyle: body.labelLarge, fontWeight: FontWeight.w600),
        )
        .apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.surface,
        surfaceContainerHighest: AppColors.surface3,
        primary: AppColors.accent,
        onPrimary: AppColors.onAccent,
        secondary: AppColors.sage,
        onSecondary: AppColors.background,
        error: AppColors.danger,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textMuted,
        outline: AppColors.border,
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.large)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface2,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.border),
        focusedBorder: inputBorder(AppColors.accent, 1.5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          disabledBackgroundColor: AppColors.surface3,
          disabledForegroundColor: AppColors.textMuted,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        side: const BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        labelStyle: GoogleFonts.outfit(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surface3,
        contentTextStyle: GoogleFonts.outfit(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    );
  }
}
