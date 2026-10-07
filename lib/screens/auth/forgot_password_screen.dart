import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/field_error.dart';
import '../../widgets/paw_loader.dart';

/// ลืมรหัสผ่าน: กรอกอีเมล → ขอลิงก์รีเซ็ต (POST /auth/forgot-password)
/// การส่งอีเมลและหน้าตั้งรหัสใหม่จากลิงก์เป็นงานฝั่ง backend
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  /// อีเมลที่พิมพ์ไว้ในหน้าเข้าสู่ระบบ (ถ้ามี) ใส่ให้ล่วงหน้า
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> with FieldErrors {
  late final _email = TextEditingController(text: widget.initialEmail);
  bool _sending = false;

  /// ข้อความจาก backend หลังส่งคำขอสำเร็จ (null = ยังไม่ได้ส่ง)
  String? _sentMessage;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    clearFieldErrors();
    final email = _email.text.trim();
    if (email.isEmpty) {
      showFieldError('email', 'กรุณากรอกอีเมลที่ใช้สมัคร');
      return;
    }
    if (!_emailPattern.hasMatch(email)) {
      showFieldError('email', 'รูปแบบอีเมลไม่ถูกต้อง');
      return;
    }
    setState(() => _sending = true);
    try {
      final msg = await AuthService.instance.requestPasswordReset(email);
      if (!mounted) return;
      setState(() => _sentMessage = msg);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      showFieldError('submit', e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('ลืมรหัสผ่าน'),
        backgroundColor: AppColors.appBar,
        iconTheme: const IconThemeData(color: AppColors.primary),
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: _sentMessage == null ? _form() : _done(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return SectionCard(
      title: 'รีเซ็ตรหัสผ่าน',
      children: [
        const Text(
          'กรอกอีเมลที่ใช้สมัครสมาชิก ระบบจะส่งลิงก์สำหรับตั้งรหัสผ่านใหม่ไปให้',
          style: TextStyle(fontSize: 15, color: AppColors.textDark, height: 1.4),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('forgot-email'),
          controller: _email,
          enabled: !_sending,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.send,
          onChanged: (_) => clearFieldErrors(),
          onSubmitted: (_) {
            if (!_sending) _submit();
          },
          decoration: InputDecoration(
            labelText: 'อีเมล',
            prefixIcon: const Icon(Icons.email_outlined),
            error: fieldErrorWidget('email'),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          key: const ValueKey('forgot-submit'),
          onPressed: _sending ? null : _submit,
          child: _sending
              ? const SizedBox(width: 24, height: 24, child: PawSpinner())
              : const Text('ส่งลิงก์รีเซ็ตรหัสผ่าน'),
        ),
        InlineError(fieldError('submit')),
      ],
    );
  }

  Widget _done() {
    return SectionCard(
      title: 'ตรวจสอบอีเมลของคุณ',
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 64, color: AppColors.success),
        const SizedBox(height: 12),
        Text(
          _sentMessage!,
          key: const ValueKey('forgot-done'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, color: AppColors.textDark, height: 1.4),
        ),
        const SizedBox(height: 8),
        const Text(
          'ถ้าไม่เห็นอีเมล ลองดูในโฟลเดอร์จดหมายขยะ (Spam)',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.brown),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          key: const ValueKey('forgot-back'),
          onPressed: () => Navigator.pop(context),
          child: const Text('กลับไปหน้าเข้าสู่ระบบ'),
        ),
      ],
    );
  }
}
