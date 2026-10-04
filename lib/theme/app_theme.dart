import 'package:flutter/material.dart';

/// สีของแอปทั้งหมดอยู่ที่นี่ที่เดียว — โทนพาสเทล ครีม-ชมพู-น้ำตาล
/// (palette: coolors.co/f7f0e3-eda2c3-f48eb8-985a40-64321b
///  และ coolors.co/e6ccb2-ddb892-b08968-7f5539-9c6644)
class AppColors {
  AppColors._();

  /// สีหลัก (ชมพู): ปุ่มหลัก แท็บที่เลือก หัวข้อเด่น
  static const primary = Color(0xFFF48EB8);

  /// ชมพูอ่อน: ไอคอนประกอบ ปุ่มรอง
  static const primarySoft = Color(0xFFEDA2C3);

  /// ชมพูจางมาก: พื้นชิป/การ์ดที่เลือกอยู่
  static const primaryTint = Color(0xFFF7DAD9);

  /// ตัวอักษร/ไอคอนบนปุ่มสีชมพู (น้ำตาลเข้ม อ่านง่ายกว่าตัวขาวบนพาสเทล)
  static const onPrimary = Color(0xFF64321B);

  /// พื้นหลังหน้า (ครีม) ใช้ใต้ภาพลายอุ้งเท้าและหน้าที่ไม่มีภาพ
  static const background = Color(0xFFF7F0E3);

  /// แถบหัวข้อด้านบน: ครีมเกือบทึบ บังลายอุ้งเท้าให้หัวข้ออ่านง่าย
  static const appBar = Color(0xF5FDF8F4);

  /// พื้นกรอบรองข้อความบนพื้นลาย (TextPanel) ขาวอมครีม เกือบทึบ
  static const panel = Color(0xFAFFFFFF);

  /// พื้นการ์ดแบ่งหมวด (SectionCard) ครีมอ่อนเกือบขาว
  static const section = Color(0xFFFFFBF3);

  /// พื้นผิวการ์ด แถบเมนู ช่องกรอก
  static const surface = Colors.white;

  /// โทนน้ำตาลนม/คาราเมล
  static const sand = Color(0xFFE6CCB2);
  static const caramel = Color(0xFFDDB892);
  static const mocha = Color(0xFFB08968);
  static const brown = Color(0xFF985A40);

  /// เดิมชื่อ lavender ในรอบแรก — ใช้เป็นสีรองโทนทราย
  static const lavenderTint = Color(0xFFF3E6D8);

  /// สีสื่อความหมาย โทนอบอุ่นเข้ากับธีม (ไม่แดง/เขียวจัด)
  /// danger: ออกจากระบบ ลบ ยกเลิก ปัด "ไม่สนใจ" แจ้งเตือนที่ยังไม่อ่าน
  static const danger = Color(0xFFC25E4F);
  static const dangerSoft = Color(0xFFE8A598);

  /// success: ถูกใจ ผ่านเงื่อนไข ถูกรับเลี้ยงแล้ว
  static const success = Color(0xFF5E9E6A);
  static const successSoft = Color(0xFFA3CFA6);

  /// warning: ระดับกลาง เช่น รหัสผ่าน "พอใช้"
  static const warning = Color(0xFFD08A34);

  /// ขอบตัวอักษร/ไอคอนสีชมพู ให้อ่านชัดบนพื้นลาย
  static const outline = Color(0xFF2A1A12);

  /// ตัวอักษร
  static const textDark = Color(0xFF64321B);
  static const textMuted = Color(0xFF9C6644);
}

/// ความโค้งของมุม ใช้ค่าเดียวกันทั้งแอปให้ดูเป็นชุดเดียว
class AppRadius {
  AppRadius._();

  static const double card = 24;
  static const double pill = 30;
}

class AppTheme {
  AppTheme._();

  /// ทั้งแอปใช้ Sarabun (ไทย/อังกฤษ/ตัวเลข) — Titan One ใช้เฉพาะโลโก้ PetPaws หน้าเข้าสู่ระบบ
  static const font = 'Sarabun';
  static const fontFallback = <String>[];
  static const logoFont = 'TitanOne';

  /// ขอบดำรอบตัวอักษรสีชมพู ใส่ใน TextStyle(shadows: AppTheme.outline)
  static const outline = <Shadow>[
    Shadow(color: AppColors.outline, offset: Offset(1.30, 0.00)),
    Shadow(color: AppColors.outline, offset: Offset(0.92, 0.92)),
    Shadow(color: AppColors.outline, offset: Offset(0.00, 1.30)),
    Shadow(color: AppColors.outline, offset: Offset(-0.92, 0.92)),
    Shadow(color: AppColors.outline, offset: Offset(-1.30, 0.00)),
    Shadow(color: AppColors.outline, offset: Offset(-0.92, -0.92)),
    Shadow(color: AppColors.outline, offset: Offset(-0.00, -1.30)),
    Shadow(color: AppColors.outline, offset: Offset(0.92, -0.92)),
  ];

  /// ขอบหนาสำหรับหัวข้อใหญ่/โลโก้
  static const outlineThick = <Shadow>[
    Shadow(color: AppColors.outline, offset: Offset(2.60, 0.00)),
    Shadow(color: AppColors.outline, offset: Offset(2.40, 0.99)),
    Shadow(color: AppColors.outline, offset: Offset(1.84, 1.84)),
    Shadow(color: AppColors.outline, offset: Offset(0.99, 2.40)),
    Shadow(color: AppColors.outline, offset: Offset(0.00, 2.60)),
    Shadow(color: AppColors.outline, offset: Offset(-0.99, 2.40)),
    Shadow(color: AppColors.outline, offset: Offset(-1.84, 1.84)),
    Shadow(color: AppColors.outline, offset: Offset(-2.40, 0.99)),
    Shadow(color: AppColors.outline, offset: Offset(-2.60, 0.00)),
    Shadow(color: AppColors.outline, offset: Offset(-2.40, -0.99)),
    Shadow(color: AppColors.outline, offset: Offset(-1.84, -1.84)),
    Shadow(color: AppColors.outline, offset: Offset(-0.99, -2.40)),
    Shadow(color: AppColors.outline, offset: Offset(-0.00, -2.60)),
    Shadow(color: AppColors.outline, offset: Offset(0.99, -2.40)),
    Shadow(color: AppColors.outline, offset: Offset(1.84, -1.84)),
    Shadow(color: AppColors.outline, offset: Offset(2.40, -0.99)),
    Shadow(color: AppColors.outline, offset: Offset(1.30, 0.00)),
    Shadow(color: AppColors.outline, offset: Offset(0.92, 0.92)),
    Shadow(color: AppColors.outline, offset: Offset(0.00, 1.30)),
    Shadow(color: AppColors.outline, offset: Offset(-0.92, 0.92)),
    Shadow(color: AppColors.outline, offset: Offset(-1.30, 0.00)),
    Shadow(color: AppColors.outline, offset: Offset(-0.92, -0.92)),
    Shadow(color: AppColors.outline, offset: Offset(-0.00, -1.30)),
    Shadow(color: AppColors.outline, offset: Offset(0.92, -0.92)),
  ];

  /// แจ้งเตือน (SnackBar) แสดงค้างไว้ 1.5 วินาที
  static const snackDuration = Duration(milliseconds: 1500);

  /// ขอบแจ้งเตือน: แดงอิฐ = ผิดพลาด/เตือน (ค่าเริ่มต้น), เขียว = สำเร็จ
  static const snackErrorShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
    side: BorderSide(color: AppColors.danger, width: 1.5),
  );
  static const snackSuccessShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
    side: BorderSide(color: AppColors.success, width: 1.5),
  );
  static const snackSuccessText = TextStyle(color: AppColors.success);

  /// ขยายตัวอักษรทั้งแอป (คูณกับขนาดที่ผู้ใช้ตั้งในเครื่องอีกที)
  static const textScale = 1.12;

  static const _bold = TextStyle(
    fontFamily: font,
    fontFamilyFallback: fontFallback,
    fontWeight: FontWeight.w700,
  );

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
      // โปร่งใส: ให้เห็นภาพพื้นหลังที่ AppBackground วาดไว้ใต้ทุกหน้า
      scaffoldBackgroundColor: Colors.transparent,
    );

    const pillShape = StadiumBorder();
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.card),
    );
    final pillBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      borderSide: const BorderSide(color: AppColors.mocha, width: 1.6),
    );

    return base.copyWith(
      // สีตอนชี้/กด/โฟกัส เป็นชมพูจาง ไม่ให้เป็นแถบเทามืดค้าง (เช่น การ์ดประกาศ, ช่องเลือกสถานะ)
      hoverColor: AppColors.primaryTint.withValues(alpha: 0.35),
      focusColor: AppColors.primaryTint.withValues(alpha: 0.45),
      highlightColor: AppColors.primaryTint.withValues(alpha: 0.4),
      splashColor: AppColors.primaryTint.withValues(alpha: 0.5),
      textTheme: () {
        final t = base.textTheme.apply(
          fontFamily: font,
          fontFamilyFallback: fontFallback,
          bodyColor: AppColors.textDark,
          displayColor: AppColors.textDark,
        );
        // ข้อความที่ผู้ใช้พิมพ์ในช่องกรอก (bodyLarge) ใช้ Sarabun ล้วน
        // อีเมล/ชื่อผู้ใช้/รหัสผ่านจะได้อ่านง่าย ไม่ปนตัว Titan
        return t.copyWith(
          bodyLarge: t.bodyLarge
              ?.copyWith(fontFamily: 'Sarabun', fontFamilyFallback: const []),
        );
      }(),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.appBar,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        // หัวข้อภาษาไทยเป็นน้ำตาลเข้ม อ่านชัดบนพื้นครีม
        titleTextStyle: _bold.copyWith(fontSize: 22, color: AppColors.textDark),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: cardShape,
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          shape: pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: _bold.copyWith(fontSize: 17),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: _bold.copyWith(fontSize: 17),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brown,
          side: const BorderSide(color: AppColors.primarySoft, width: 1.5),
          shape: pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: _bold.copyWith(fontSize: 16),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.brown,
          shape: pillShape,
          textStyle: _bold.copyWith(fontSize: 16),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
        shape: CircleBorder(),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: AppColors.textDark),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        labelStyle: const TextStyle(color: AppColors.textDark),
        floatingLabelStyle: const TextStyle(
            color: AppColors.textDark, fontWeight: FontWeight.w700),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        helperStyle: const TextStyle(color: AppColors.textDark),
        prefixIconColor: AppColors.primary,
        border: pillBorder,
        enabledBorder: pillBorder,
        errorBorder: pillBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
        focusedErrorBorder: pillBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.danger, width: 2.2),
        ),
        focusedBorder: pillBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.brown, width: 2.2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryTint,
        side: const BorderSide(color: AppColors.sand),
        shape: pillShape,
        labelStyle: const TextStyle(
          fontFamily: font,
          fontFamilyFallback: fontFallback,
          fontWeight: FontWeight.w600,
          color: AppColors.textDark,
        ),
        checkmarkColor: AppColors.brown,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.mocha,
        elevation: 0,
        selectedLabelStyle: _bold.copyWith(fontSize: 13),
        unselectedLabelStyle: const TextStyle(
            fontFamily: font, fontFamilyFallback: fontFallback, fontSize: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        titleTextStyle:
            _bold.copyWith(fontSize: 20, color: AppColors.textDark),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // แจ้งเตือนแบบกล่องขาวขอบแดงอิฐ เหมือนข้อความ error ใต้ช่องกรอก
        // (ข้อความสำเร็จใช้ snackSuccessShape + สีเขียวแทน) ฟอนต์ Sarabun ทั้งข้อความ
        backgroundColor: Colors.white,
        elevation: 3,
        contentTextStyle: TextStyle(
            fontFamily: 'Sarabun', fontSize: 15, color: AppColors.danger),
        shape: snackErrorShape,
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: const TextStyle(
            fontFamily: 'Sarabun', fontSize: 14, color: Colors.white),
        decoration: BoxDecoration(
          color: AppColors.textDark.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.primary),
      dividerTheme: const DividerThemeData(
          color: AppColors.sand, thickness: 1, space: 1),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.primary),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.primary : null),
      ),
    );
  }
}

/// ชุดภาพพื้นหลัง: login = หน้าเข้าสู่ระบบ (แมว/หมา), other = หน้าอื่นทั้งหมด (มือจับอุ้งเท้า)
enum AppBg { login, other }

/// พื้นหลังใต้หน้าจอ เลือกภาพตามสัดส่วนจอ ([bg] = ชุดภาพ ค่าเริ่มต้น other):
/// จอสูงกว่ากว้าง (มือถือ) ใช้ bg_mobile, จอกว้าง (คอม/เว็บ) ใช้ bg_web
/// ขยายเต็มจอแบบ cover — ภาพทำมาตามสัดส่วนจอแต่ละแบบแล้ว จึงโดนตัดขอบน้อย
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child, this.bg = AppBg.other});

  final Widget child;
  final AppBg bg;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final portrait = constraints.maxHeight > constraints.maxWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background,
            image: DecorationImage(
              image: AssetImage(
                  'assets/images/bg_${bg == AppBg.other ? '' : '${bg.name}_'}${portrait ? 'mobile' : 'web'}.jpg'),
              fit: BoxFit.cover,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

/// กรอบขาวครีมขอบมนรองใต้ข้อความที่วางบนพื้นลายอุ้งเท้าโดยตรง ให้อ่านง่าย
/// ข้อความบรรทัดเดียวใช้ทรงแคปซูล ([pill] = true) หลายบรรทัดใช้มุมโค้งแบบการ์ด
class TextPanel extends StatelessWidget {
  const TextPanel({
    super.key,
    required this.child,
    this.center = false,
    this.pill = true,
  });

  final Widget child;
  final bool center;
  final bool pill;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: center ? Alignment.center : AlignmentDirectional.centerStart,
      child: Container(
        padding: pill
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 5)
            : const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius:
              BorderRadius.circular(pill ? AppRadius.pill : AppRadius.card),
          border: Border.all(color: AppColors.caramel, width: 1.2),
        ),
        child: child,
      ),
    );
  }
}

/// การ์ดรวมหัวข้อกับช่องกรอกของหมวดเดียวกันเป็นก้อนเดียว ให้ฟอร์มยาวดูง่าย
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AppColors.section,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.caramel),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14985A40), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontFamily: 'Sarabun',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 14),
          ],
          ...children,
        ],
      ),
    );
  }
}
