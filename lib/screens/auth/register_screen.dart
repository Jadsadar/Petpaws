import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../services/auth_service.dart';
import '../../utils/password_policy.dart';
import '../../widgets/password_checklist.dart';
import '../../theme/app_theme.dart';
import '../../widgets/field_error.dart';
import '../../widgets/privacy_consent_dialog.dart';
import '../../widgets/paw_loader.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with FieldErrors {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  /// ยินยอมให้เก็บ/ใช้ข้อมูลส่วนบุคคลแล้ว (ต้องยินยอมก่อนสมัคร)
  bool _consented = false;

  @override
  void initState() {
    super.initState();
    // เข้าหน้าสมัครแล้วเด้งหนังสือขอความยินยอมขึ้นมาทันที
    WidgetsBinding.instance.addPostFrameCallback((_) => _askConsent());
  }

  Future<void> _askConsent() async {
    final ok = await showPrivacyConsentDialog(context);
    if (!mounted || ok == null) return;
    setState(() => _consented = ok);
    if (ok) clearFieldErrors();
  }

  Future<void> handleRegister() async {
    clearFieldErrors();
    if (!_consented) {
      showFieldError('consent', 'กรุณาอ่านและกดยินยอมการใช้ข้อมูลส่วนบุคคลก่อนสมัครสมาชิก');
      return;
    }
    final username = usernameController.text.trim();
    if (username.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty) {
      showFieldError(
          username.isEmpty
              ? 'username'
              : (emailController.text.isEmpty ? 'email' : 'password'),
          'กรุณากรอกข้อมูลให้ครบถ้วน');
      return;
    }
    if (username.contains('@') || username.contains(' ')) {
      showFieldError('username', 'ชื่อผู้ใช้ห้ามมีเว้นวรรคหรือเครื่องหมาย @');
      return;
    }
    final passwordError = PasswordPolicy.firstError(
      passwordController.text,
      username: username,
      email: emailController.text,
    );
    if (passwordError != null) {
      showFieldError('password', passwordError);
      return;
    }
    if (passwordController.text != confirmPasswordController.text) {
      showFieldError('confirm', 'รหัสผ่านไม่ตรงกัน');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final needsVerification = await AuthService.instance.register(
        email: emailController.text.trim(),
        password: passwordController.text,
        username: username,
      );
      currentUserProfile['email'] = emailController.text.trim();
      if (!mounted) return;
      // ต้องยืนยันอีเมล: แสดงหน้า "ตรวจอีเมลของคุณ" ก่อน (ปิดหน้านั้นแล้วค่อยกลับไปหน้า login)
      if (needsVerification) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VerifyEmailScreen(email: emailController.text.trim(), identifier: username),
          ),
        );
        if (!mounted) return;
      }
      // POST /auth/register ไม่ได้ล็อกอินให้ — กลับไปหน้า login ให้ผู้ใช้เข้าเอง
      Navigator.pop(context, true);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      showFieldError('submit', e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สมัครสมาชิก',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.textDark)),
        backgroundColor: AppColors.appBar,
        iconTheme: const IconThemeData(color: AppColors.primary),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'ข้อมูลพื้นฐานบัญชีผู้ใช้',
              children: [
                TextField(
                    key: const ValueKey('register-username'),
                    controller: usernameController,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                        labelText: 'Username (สำหรับใช้ล็อกอิน) *',
                        error: fieldErrorWidget('username'),
                        helper: const Text('ห้ามเว้นวรรค ใช้ล็อกอินแทนอีเมลได้',
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textDark)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card)))),
                const SizedBox(height: 16),
                TextField(
                    key: const ValueKey('register-email'),
                    controller: emailController,
                    enabled: !_isLoading,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                        labelText: 'อีเมล *',
                        error: fieldErrorWidget('email'),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card)))),
                const SizedBox(height: 16),
                TextField(
                    key: const ValueKey('register-password'),
                    controller: passwordController,
                    obscureText: _obscurePassword,
                    enabled: !_isLoading,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                        labelText: 'รหัสผ่าน *',
                        error: fieldErrorWidget('password'),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card)))),
                PasswordChecklist(
                  password: passwordController.text,
                  username: usernameController.text,
                  email: emailController.text,
                ),
                const SizedBox(height: 16),
                TextField(
                    key: const ValueKey('register-confirm'),
                    controller: confirmPasswordController,
                    obscureText: _obscureConfirmPassword,
                    enabled: !_isLoading,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_isLoading) handleRegister();
                    },
                    decoration: InputDecoration(
                        labelText: 'ยืนยันรหัสผ่าน *',
                        error: fieldErrorWidget('confirm'),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirmPassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(() =>
                              _obscureConfirmPassword = !_obscureConfirmPassword),
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card)))),
              ],
            ),
            const SizedBox(height: 16),
            // สถานะการยินยอม + ปุ่มเปิดอ่านอีกครั้ง
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: AppColors.section,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                    color: _consented ? AppColors.success : AppColors.sand),
              ),
              child: Row(
                children: [
                  Icon(_consented ? Icons.verified_user : Icons.privacy_tip_outlined,
                      color: _consented ? AppColors.success : AppColors.brown),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        _consented
                            ? 'ยินยอมการใช้ข้อมูลส่วนบุคคลแล้ว'
                            : 'ยังไม่ได้ยินยอมการใช้ข้อมูลส่วนบุคคล',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _consented ? AppColors.success : AppColors.textDark)),
                  ),
                  TextButton(
                    key: const ValueKey('consent-open'),
                    onPressed: _askConsent,
                    child: Text(_consented ? 'อ่านอีกครั้ง' : 'อ่านและยินยอม'),
                  ),
                ],
              ),
            ),
            InlineError(fieldError('consent')),
            const SizedBox(height: 24),
            ElevatedButton(
              key: const ValueKey('register-submit'),
              onPressed: _isLoading ? null : handleRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                elevation: 2,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: PawSpinner(color: Colors.white),
                    )
                  : const Text('สมัครสมาชิก',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            InlineError(fieldError('submit')),
          ],
        ),
      ),
    );
  }
}
