import 'package:flutter/material.dart';
import 'app_tokens.dart';

/// Shared geometry and spacing for built-in Material components.
ThemeData applyComponentTheme(ThemeData base) {
  const label = TextStyle(
      fontFamily: 'Sarabun',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.4);
  const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)));
  const cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
      side: AppLayout.border);
  const inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
      borderSide: AppLayout.border);
  const padding = EdgeInsets.symmetric(horizontal: 20, vertical: 13);
  return base.copyWith(
    cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: cardShape,
        margin: EdgeInsets.zero),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: controlShape,
            minimumSize: const Size(48, 48),
            padding: padding,
            textStyle: label)),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            shape: controlShape,
            minimumSize: const Size(48, 48),
            padding: padding,
            textStyle: label)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brown,
            side: AppLayout.border,
            shape: controlShape,
            minimumSize: const Size(48, 48),
            padding: padding,
            textStyle: label)),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: AppColors.brown,
            shape: controlShape,
            minimumSize: const Size(48, 44),
            textStyle: label)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: CircleBorder(side: AppLayout.border)),
    iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
            foregroundColor: AppColors.textDark,
            minimumSize: const Size(44, 44))),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(fontSize: 14, color: AppColors.textMuted),
        floatingLabelStyle: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.brown),
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textMuted),
        helperStyle: const TextStyle(color: AppColors.textMuted),
        prefixIconColor: AppColors.mocha,
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        errorBorder: inputBorder.copyWith(
            borderSide: const BorderSide(color: AppColors.danger)),
        focusedErrorBorder: inputBorder.copyWith(
            borderSide: const BorderSide(color: AppColors.danger, width: 1.5)),
        focusedBorder: inputBorder.copyWith(
            borderSide: const BorderSide(color: AppColors.brown, width: 1.5))),
    chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryTint,
        side: AppLayout.border,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.chip))),
        labelStyle: const TextStyle(
            fontFamily: 'Sarabun',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textDark),
        checkmarkColor: AppColors.brown),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.mocha,
        elevation: 0,
        selectedLabelStyle: TextStyle(
            fontFamily: 'Sarabun', fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontFamily: 'Sarabun', fontSize: 12)),
    tabBarTheme: const TabBarThemeData(
        labelStyle: label,
        unselectedLabelStyle: TextStyle(fontFamily: 'Sarabun', fontSize: 14),
        labelColor: AppColors.textDark,
        unselectedLabelColor: AppColors.textMuted,
        dividerColor: AppColors.sand,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label),
    dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: cardShape,
        titleTextStyle: TextStyle(
            fontFamily: 'Sarabun',
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark)),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.card)))),
    tooltipTheme: TooltipThemeData(
        textStyle: const TextStyle(
            fontFamily: 'Sarabun', fontSize: 12, color: Colors.white),
        decoration: BoxDecoration(
            color: AppColors.textDark,
            borderRadius: BorderRadius.circular(AppRadius.chip))),
    popupMenuTheme: const PopupMenuThemeData(
        elevation: 0,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: cardShape),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: AppColors.primary),
    dividerTheme:
        const DividerThemeData(color: AppColors.sand, thickness: 1, space: 1),
    listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4)),
    switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : null)),
  );
}
