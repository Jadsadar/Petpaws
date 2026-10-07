import 'package:flutter/material.dart';
import 'app_tokens.dart';
import 'app_component_theme.dart';

export 'app_tokens.dart';
export 'app_surfaces.dart';

class AppTheme {
  AppTheme._();
  static const font = 'Sarabun';
  static const fontFallback = <String>[];
  static const logoFont = font;
  static const outline = <Shadow>[];
  static const outlineThick = <Shadow>[];
  static const snackDuration = Duration(milliseconds: 1500);
  static const snackErrorShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
    side: BorderSide(color: AppColors.danger),
  );
  static const snackSuccessShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
    side: BorderSide(color: AppColors.success),
  );
  static const snackSuccessText = TextStyle(color: AppColors.success);
  static const textScale = 1.0;
  static const maxTextScale = 1.6;
  static TextScaler appTextScaler(TextScaler system) => TextScaler.linear(
      (system.scale(1) * textScale).clamp(0.5, maxTextScale).toDouble());

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.caramel,
      tertiary: AppColors.primarySoft,
      surface: AppColors.surface,
      onSurface: AppColors.textDark,
    );
    final base = ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        fontFamily: font,
        fontFamilyFallback: fontFallback,
        scaffoldBackgroundColor: Colors.transparent);
    final text = base.textTheme.apply(
        fontFamily: font,
        bodyColor: AppColors.textDark,
        displayColor: AppColors.textDark);
    return applyComponentTheme(base.copyWith(
      hoverColor: AppColors.primaryTint.withValues(alpha: 0.2),
      focusColor: AppColors.primaryTint.withValues(alpha: 0.3),
      highlightColor: AppColors.primaryTint.withValues(alpha: 0.2),
      splashColor: AppColors.primaryTint.withValues(alpha: 0.3),
      textTheme: text.copyWith(
        headlineLarge: _heading(28),
        headlineMedium: _heading(24),
        headlineSmall: _heading(22),
        titleLarge: _heading(20),
        titleMedium: _heading(16),
        titleSmall: _heading(14),
        bodyLarge: _body(16),
        bodyMedium: _body(14),
        bodySmall: _body(12).copyWith(color: AppColors.textMuted),
        labelLarge: _heading(14),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.appBar,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        toolbarHeight: 64,
        titleTextStyle: _heading(20),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.white,
        elevation: 0,
        shape: snackErrorShape,
        contentTextStyle:
            TextStyle(fontFamily: font, fontSize: 14, color: AppColors.danger),
      ),
    ));
  }

  static TextStyle _heading(double size) => TextStyle(
      fontFamily: font,
      fontSize: size,
      fontWeight: FontWeight.w600,
      height: 1.4,
      color: AppColors.textDark);
  static TextStyle _body(double size) => TextStyle(
      fontFamily: font,
      fontSize: size,
      height: 1.55,
      color: AppColors.textDark);
}
