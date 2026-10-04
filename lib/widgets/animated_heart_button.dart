import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ปุ่มหัวใจถูกใจแบบมีแอนิเมชัน (หน้าตาเหมือนปุ่มเดิม: วงกลมขอบชมพู)
/// - กดถูกใจ: หัวใจเด้งขยายแล้วหดกลับ + หัวใจดวงเล็กกระจายออกรอบ ๆ
/// - กดเลิกถูกใจ: หัวใจหดลงเบา ๆ แล้วกลับขนาดเดิม
class AnimatedHeartButton extends StatefulWidget {
  const AnimatedHeartButton({
    super.key,
    required this.isFavorited,
    required this.onPressed,
    this.iconSize = 32,
  });

  final bool isFavorited;
  final VoidCallback onPressed;
  final double iconSize;

  @override
  State<AnimatedHeartButton> createState() => _AnimatedHeartButtonState();
}

class _AnimatedHeartButtonState extends State<AnimatedHeartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  // ถูกใจ: 1 -> 1.35 -> 0.9 -> 1 (เด้ง) / เลิกถูกใจ: 1 -> 0.8 -> 1
  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 0.9).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
  ]).animate(_c);
  late final Animation<double> _shrink = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 50),
    TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 50),
  ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  bool _likedLast = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    _likedLast = !widget.isFavorited; // สถานะหลังกด
    _c.forward(from: 0);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final fav = widget.isFavorited;
    final size = widget.iconSize + 16 * 2; // เท่ากับ IconButton เดิม (padding 8 + วงกลม)
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          final scale = !_c.isAnimating && t == 0
              ? 1.0
              : (_likedLast ? _pop.value : _shrink.value);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // หัวใจเล็กกระจายออก (เฉพาะตอนกดถูกใจ)
              if (_likedLast && _c.isAnimating)
                for (var i = 0; i < 7; i++) _particle(i, t, size),
              Transform.scale(scale: scale, child: child),
            ],
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary, width: 2),
            shape: BoxShape.circle,
            color: fav ? AppColors.primaryTint : Colors.white,
          ),
          child: IconButton(
            iconSize: widget.iconSize,
            tooltip: fav ? 'เลิกถูกใจ' : 'ถูกใจ',
            onPressed: _tap,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Icon(
                fav ? Icons.favorite : Icons.favorite_border,
                key: ValueKey(fav),
                color: fav ? AppColors.danger : AppColors.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _particle(int i, double t, double size) {
    final angle = -math.pi / 2 + (i - 3) * (math.pi / 5.5);
    final dist = size * 0.35 + size * 0.55 * Curves.easeOut.transform(t);
    final opacity = (1 - t).clamp(0.0, 1.0);
    return Transform.translate(
      offset: Offset(math.cos(angle) * dist, math.sin(angle) * dist),
      child: Opacity(
        opacity: opacity,
        child: Icon(Icons.favorite,
            size: 10 + (i % 3) * 3.0,
            color: i.isEven ? AppColors.primary : AppColors.danger),
      ),
    );
  }
}
