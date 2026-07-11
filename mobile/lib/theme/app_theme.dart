import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppColors {
  static const primary = Color(0xFF6BCB77);
  static const primaryDark = Color(0xFF4FA85A);
  static const background = Color(0xFFFFF9F0);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF3EFE8);
  static const streak = Color(0xFFFF6B35);
  static const water = Color(0xFF4ECDC4);
  static const protein = Color(0xFF4A90D9);
  static const fat = Color(0xFFE8A04C);
  static const carbs = Color(0xFFA78BFA);
  static const breakfast = Color(0xFFE8C84C);
  static const lunch = Color(0xFFE8A04C);
  static const dinner = Color(0xFFA78BFA);
  static const snack = Color(0xFF6BCB77);
  static const textPrimary = Color(0xFF2D2A26);
  static const textSecondary = Color(0xFF7A756C);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.background,
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 4,
    ),
  );

  final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
