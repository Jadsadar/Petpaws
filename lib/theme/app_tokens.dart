import 'package:flutter/material.dart';

/// Existing PetPaws palette.
class AppColors {
  AppColors._();
  static const primary = Color(0xFFF48EB8);
  static const primarySoft = Color(0xFFEDA2C3);
  static const primaryTint = Color(0xFFF7DAD9);
  static const onPrimary = Color(0xFF64321B);
  static const background = Color(0xFFF7F0E3);
  static const appBar = Color(0xF5FDF8F4);
  static const panel = Color(0xFAFFFFFF);
  static const section = Color(0xFFFFFBF3);
  static const surface = Colors.white;
  static const sand = Color(0xFFE6CCB2);
  static const caramel = Color(0xFFDDB892);
  static const mocha = Color(0xFFB08968);
  static const brown = Color(0xFF985A40);
  static const lavenderTint = Color(0xFFF3E6D8);
  static const danger = Color(0xFFC25E4F);
  static const dangerSoft = Color(0xFFE8A598);
  static const success = Color(0xFF5E9E6A);
  static const successSoft = Color(0xFFA3CFA6);
  static const warning = Color(0xFFD08A34);
  static const outline = Color(0xFF2A1A12);
  static const textDark = Color(0xFF64321B);
  static const textMuted = Color(0xFF9C6644);
}

class AppRadius {
  AppRadius._();
  static const double card = 16;
  static const double control = 10;
  static const double chip = 8;
  static const double pill = control;
}

class AppLayout {
  AppLayout._();
  static const double authWidth = 480;
  static const double formWidth = 720;
  static const double contentWidth = 960;
  static const double dashboardWidth = 1120;
  static const double deckWidth = 480;
  static const double pagePadding = 24;
  static const BorderSide border = BorderSide(color: AppColors.sand);
  static const shadows = <BoxShadow>[
    BoxShadow(color: Color(0x08985A40), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
