import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import 'register_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/paw_loader.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController identifierController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  // ข้อผิดพลาดแสดงใต้ช่องกรอก (แทนแจ้งเตือนเด้ง) ค้างจนกว่าจะพิมพ์ใหม่หรือกดเข้าสู่ระบบอีกครั้ง
  String? _identifierError;
  String? _passwordError;

  void _showFieldError({String? identifier, String? password}) {
    setState(() {
      _identifierError = identifier;
      _passwordError = password;
    });
  }

  void _clearFieldErrors() {
    if (!mounted || (_identifierError == null && _passwordError == null)) {
      return;
    }
    setState(() {
      _identifierError = null;
      _passwordError = null;
    });
  }

  /// ข้อความ error ใต้ช่อง: ไอคอน ! + ตัวอักษรสีแดงอิฐ ไม่มีกรอบ
  Widget? _fieldError(String? message) {
    if (message == null) return null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
        const SizedBox(width: 6),
        Expanded(
          child: Text(message,
              style: const TextStyle(fontSize: 14, color: AppColors.danger)),
        ),
      ],
    );
  }

  Future<void> _goToRegister() async {
    final registered = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
    if (registered == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          shape: AppTheme.snackSuccessShape,
          duration: AppTheme.snackDuration,
          content: Text('สมัครสมาชิกสำเร็จ กรุณาเข้าสู่ระบบ',
              style: AppTheme.snackSuccessText)));
    }
  }

  Future<void> login() async {
    final identifier = identifierController.text.trim();
    final password = passwordController.text;
    if (identifier.isEmpty || password.isEmpty) {
      const msg = 'กรุณากรอกอีเมล/ชื่อผู้ใช้ และรหัสผ่าน';
      _showFieldError(
        identifier: identifier.isEmpty ? msg : null,
        password: identifier.isEmpty ? null : msg,
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.instance
          .signIn(identifier: identifier, password: password);
      // AuthGate จะสลับหน้าไปยัง MainScreen ให้อัตโนมัติเมื่อสถานะล็อกอินเปลี่ยน
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.code == 'EMAIL_NOT_VERIFIED') {
        // ยังไม่ได้กดลิงก์ในอีเมล — เสนอส่งลิงก์ใหม่แทนการโชว์ error ใต้ช่องรหัสผ่านเฉยๆ
        // หยุดหมุนโหลดก่อนเปิดกล่อง ไม่งั้นปุ่มล็อกอินหมุนค้างอยู่ข้างหลังกล่องจนกว่าจะปิด
        setState(() => _isLoading = false);
        await _offerResend(identifier, e.message);
      } else {
        _showFieldError(password: e.message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// ล็อกอินไม่ผ่านเพราะยังไม่ได้ยืนยันอีเมล — เสนอส่งลิงก์ยืนยันอีกครั้ง
  Future<void> _offerResend(String identifier, String message) async {
    final resend = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยังไม่ได้ยืนยันอีเมล'),
        content: Text(message),
        actions: [
          TextButton(
              key: const ValueKey('verify-close'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ปิด')),
          TextButton(
              key: const ValueKey('verify-resend'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ส่งลิงก์ยืนยันอีกครั้ง')),
        ],
      ),
    );
    if (resend != true || !mounted) return;
    String text;
    try {
      text = await AuthService.instance.resendVerification(identifier);
    } on AuthFailure catch (e) {
      text = e.message;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    identifierController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // พื้นที่ที่เหลือจริง (หักคีย์บอร์ดแล้ว) — จอเตี้ย/คีย์บอร์ดขึ้น ย่อโลโก้ให้ช่องกรอกยังอยู่ในจอ
    final avail = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final logoSize = avail < 420 ? 0.0 : 48.0;
    final gap = avail < 640 ? 20.0 : 28.0;
    // หน้าเข้าสู่ระบบใช้พื้นหลังลายสัตว์ หน้าอื่นใช้ภาพมือจับอุ้งเท้า
    return AppBackground(
      bg: AppBg.login,
      child: Scaffold(
        body: AppPageFrame(
            maxWidth: AppLayout.authWidth,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: SectionCard(
                  children: [
                    if (logoSize > 0) ...[
                      Icon(Icons.pets,
                          size: logoSize, color: AppColors.primary),
                      const SizedBox(height: 16),
                    ],
                    // ชื่อแอปไม่ตัดบรรทัดกลางคำ: ถ้าจอแคบ/ตัวอักษรใหญ่ให้ย่อลงแทน
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'PetPaws',
                        style: TextStyle(
                            fontFamily: AppTheme.logoFont,
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary),
                      ),
                    ),
                    const Text(
                      'หาบ้านใหม่ให้สัตว์เลี้ยงแสนรัก',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark),
                    ),
                    SizedBox(height: gap),
                    TextField(
                      key: const ValueKey('login-identifier'),
                      controller: identifierController,
                      onChanged: (_) => _clearFieldErrors(),
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        error: _fieldError(_identifierError),
                        labelText: 'อีเมล หรือ ชื่อผู้ใช้',
                        prefixIcon: const Icon(Icons.person,
                            color: AppColors.primarySoft),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('login-password'),
                      controller: passwordController,
                      onChanged: (_) => _clearFieldErrors(),
                      obscureText: _obscurePassword,
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        if (!_isLoading) login();
                      },
                      decoration: InputDecoration(
                        error: _fieldError(_passwordError),
                        labelText: 'รหัสผ่าน',
                        prefixIcon: const Icon(Icons.lock,
                            color: AppColors.primarySoft),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: Colors.black45,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.control),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    // ลืมรหัสผ่าน: ชิดขวาใต้ช่องรหัสผ่าน (ตำแหน่งมาตรฐาน)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey('login-forgot-link'),
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ForgotPasswordScreen(
                                      initialEmail: identifierController.text
                                              .contains('@')
                                          ? identifierController.text.trim()
                                          : '',
                                    ),
                                  ),
                                ),
                        child: const Text('ลืมรหัสผ่าน?',
                            style: TextStyle(
                                fontSize: 15,
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.outline)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        key: const ValueKey('login-submit'),
                        onPressed: _isLoading ? null : login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.control)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: PawSpinner(color: Colors.white),
                              )
                            : const Text('เข้าสู่ระบบ',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text('ยังไม่มีบัญชีเหรอ? ',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark)),
                        GestureDetector(
                          key: const ValueKey('login-register-link'),
                          onTap: _isLoading ? null : _goToRegister,
                          child: const Text(
                            'สมัครเลย',
                            style: TextStyle(
                                fontSize: 18,
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.outline),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            )),
      ),
    );
  }
}
