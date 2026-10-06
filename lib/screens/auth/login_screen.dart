import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import 'register_screen.dart';
import '../../theme/app_theme.dart';

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
    if (!mounted || (_identifierError == null && _passwordError == null)) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(shape: AppTheme.snackSuccessShape, duration: AppTheme.snackDuration, content: Text('สมัครสมาชิกสำเร็จ กรุณาเข้าสู่ระบบ', style: AppTheme.snackSuccessText)));
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
      _showFieldError(password: e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    identifierController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // หน้าเข้าสู่ระบบใช้พื้นหลังลายสัตว์ หน้าอื่นใช้ภาพมือจับอุ้งเท้า
    return AppBackground(
      bg: AppBg.login,
      child: Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.pets,
                  size: 100,
                  color: AppColors.primary,
                  shadows: AppTheme.outlineThick),
              const SizedBox(height: 16),
              const Text(
                'PetPaws',
                style: TextStyle(
                    fontFamily: AppTheme.logoFont,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    shadows: AppTheme.outlineThick),
              ),
              const Text(
                'หาบ้านใหม่ให้สัตว์เลี้ยงแสนรัก',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark),
              ),
              const SizedBox(height: 48),
              TextField(
                key: const ValueKey('login-identifier'),
                controller: identifierController,
                onChanged: (_) => _clearFieldErrors(),
                enabled: !_isLoading,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  error: _fieldError(_identifierError),
                  labelText: 'อีเมล หรือ ชื่อผู้ใช้',
                  prefixIcon:
                      const Icon(Icons.person, color: AppColors.primarySoft),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
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
                  prefixIcon:
                      const Icon(Icons.lock, color: AppColors.primarySoft),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.black45,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 32),
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
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 2,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text('เข้าสู่ระบบ',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('ยังไม่มีบัญชีเหรอ? ',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark)),
                  GestureDetector(
                    key: const ValueKey('login-register-link'),
                    onTap: _isLoading ? null : _goToRegister,
                    child: const Text(
                      'สมัครเลย',
                      style: TextStyle(
                          fontSize: 20,
                          color: AppColors.textDark,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.outline),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    ),
    );
  }
}
