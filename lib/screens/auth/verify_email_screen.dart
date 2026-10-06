import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// หน้า "ตรวจอีเมลของคุณ" ที่ขึ้นหลังสมัครสมาชิก (เมื่อ backend เปิดระบบยืนยันอีเมล)
/// ผู้ใช้กดลิงก์ในอีเมลแล้วกลับมาที่นี่เพื่อไปหน้าล็อกอิน — ปิดหน้านี้ = กลับไปหน้า login
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email, required this.identifier});

  /// อีเมลที่ลิงก์ถูกส่งไป (โชว์ให้ผู้ใช้เช็กว่าพิมพ์ถูกไหม)
  final String email;

  /// ใช้ขอส่งลิงก์ซ้ำ (ชื่อผู้ใช้ — backend รับทั้งอีเมลและชื่อผู้ใช้)
  final String identifier;

  /// ตรงกับช่วงพักส่งซ้ำฝั่ง backend (VERIFY_RESEND_COOLDOWN_SECONDS)
  static const int cooldownSeconds = 60;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  // เพิ่งส่งไปตอนสมัคร จึงเริ่มนับถอยหลังทันที — กดส่งซ้ำได้หลังครบเวลา
  int _secondsLeft = VerifyEmailScreen.cooldownSeconds;
  Timer? _timer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = VerifyEmailScreen.cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, VerifyEmailScreen.cooldownSeconds));
      if (_secondsLeft == 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    String text;
    try {
      text = await AuthService.instance.resendVerification(widget.identifier);
      _startCooldown();
    } on AuthFailure catch (e) {
      text = e.message;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _secondsLeft == 0 && !_sending;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ยืนยันอีเมล',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
        backgroundColor: AppColors.appBar,
        iconTheme: const IconThemeData(color: AppColors.primary),
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 88, color: AppColors.primary),
              const SizedBox(height: 20),
              const Text('ตรวจอีเมลของคุณ',
                  key: ValueKey('verify-title'),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(
                'เราส่งลิงก์ยืนยันไปที่\n${widget.email}',
                key: const ValueKey('verify-email'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
              const SizedBox(height: 12),
              const Text(
                'กดลิงก์ในอีเมลเพื่อยืนยัน แล้วกลับมาเข้าสู่ระบบ\nไม่เจออีเมล? ลองดูในจดหมายขยะ (Spam)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  key: const ValueKey('verify-done'),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยืนยันแล้ว ไปเข้าสู่ระบบ'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const ValueKey('verify-resend-button'),
                onPressed: canResend ? _resend : null,
                child: Text(_secondsLeft > 0 ? 'ส่งลิงก์อีกครั้งได้ใน $_secondsLeft วินาที' : 'ส่งลิงก์ยืนยันอีกครั้ง'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
