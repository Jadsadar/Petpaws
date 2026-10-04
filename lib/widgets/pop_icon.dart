import 'dart:math' as math;

import 'package:flutter/material.dart';

/// ไอคอนที่ "เด้ง + ส่ายเบา ๆ" ครั้งเดียวตอนปรากฏ (ใช้กับไอคอนที่เพิ่งถูกเลือก
/// เช่น แท็บเมนูล่าง หมวดสัตว์) — สร้างใหม่เมื่อไหร่ก็เล่นใหม่เมื่อนั้น
class PopIcon extends StatefulWidget {
  const PopIcon({super.key, required this.child});

  final Widget child;

  @override
  State<PopIcon> createState() => _PopIconState();
}

class _PopIconState extends State<PopIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  )..forward();

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.25).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.25, end: 0.95), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 30),
  ]).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // ส่ายซ้าย-ขวาเล็กน้อยแล้วหยุด (ลดลงตามเวลา)
        final wiggle = math.sin(_c.value * math.pi * 3) * 0.18 * (1 - _c.value);
        return Transform.rotate(
          angle: wiggle,
          child: Transform.scale(scale: _scale.value, child: child),
        );
      },
      child: widget.child,
    );
  }
}

/// ห่อปุ่ม/การ์ดให้มีการตอบสนอง: ชี้เมาส์ = ขยายนิดหนึ่ง, กดค้าง = ยุบลง
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.hoverScale = 1.05, this.pressScale = 0.93});

  final Widget child;
  final double hoverScale;
  final double pressScale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final scale = _down ? widget.pressScale : (_hover ? widget.hoverScale : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
