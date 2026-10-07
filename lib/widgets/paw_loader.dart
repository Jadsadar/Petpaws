import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ตัวโหลดของแอป: อุ้งเท้า 4 อันเด้งขึ้นทีละอันเหมือนรอยเท้าเดิน (แทนวงกลมหมุน)
/// ใช้ตอนโหลดทั้งหน้า เช่น `const Center(child: PawLoader())`
class PawLoader extends StatefulWidget {
  const PawLoader({super.key, this.size = 26, this.color = AppColors.primary, this.label});

  /// ขนาดอุ้งเท้าแต่ละอัน
  final double size;
  final Color color;

  /// ข้อความใต้อุ้งเท้า (ไม่บังคับ) เช่น 'กำลังหาน้อง ๆ ให้คุณ...'
  final String? label;

  @override
  State<PawLoader> createState() => _PawLoaderState();
}

class _PawLoaderState extends State<PawLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  static const _count = 4;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      label: 'กำลังโหลด',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _count; i++) _paw(i, s),
              ],
            ),
          ),
          if (widget.label != null) ...[
            const SizedBox(height: 12),
            Text(widget.label!,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textDark)),
          ],
        ],
      ),
    );
  }

  Widget _paw(int i, double s) {
    // แต่ละอันเริ่มช้ากว่ากันนิดหน่อย → เห็นเป็นรอยเท้าเดินไปทางขวา
    final t = (_c.value - i / _count) % 1.0;
    final lift = t < 0.3 ? math.sin(t / 0.3 * math.pi) : 0.0; // เด้งขึ้นแล้วลง
    final opacity = 0.35 + 0.65 * lift;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: s * 0.18),
      child: Transform.translate(
        // อุ้งเท้าสลับซ้าย-ขวา (สูง-ต่ำ) เหมือนรอยเท้าจริง
        offset: Offset(0, (i.isEven ? s * 0.2 : -s * 0.2) - lift * s * 0.45),
        child: Transform.rotate(
          angle: math.pi / 2 + (i.isEven ? -0.25 : 0.25),
          child: Icon(Icons.pets, size: s, color: widget.color.withValues(alpha: opacity)),
        ),
      ),
    );
  }
}

/// ตัวโหลดเล็กสำหรับบนปุ่ม/ในรูป: อุ้งเท้าเดียวหมุนพร้อมเต้นเบา ๆ
class PawSpinner extends StatefulWidget {
  const PawSpinner({super.key, this.size = 22, this.color = AppColors.onPrimary});

  final double size;
  final Color color;

  @override
  State<PawSpinner> createState() => _PawSpinnerState();
}

class _PawSpinnerState extends State<PawSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'กำลังโหลด',
      child: LayoutBuilder(builder: (context, c) {
        var d = widget.size;
        if (c.hasBoundedWidth && c.maxWidth < d) d = c.maxWidth;
        if (c.hasBoundedHeight && c.maxHeight < d) d = c.maxHeight;
        return SizedBox.square(
        dimension: d,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) => Transform.rotate(
            angle: _c.value * 2 * math.pi,
            child: Transform.scale(
              scale: 0.85 + 0.15 * math.sin(_c.value * 2 * math.pi * 2).abs(),
              child: child,
            ),
          ),
          child: Icon(Icons.pets, size: d, color: widget.color),
        ),
      );
      }),
    );
  }
}
