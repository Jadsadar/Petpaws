import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
import '../../services/auth_service.dart';
import '../../utils/password_policy.dart';
import '../../widgets/password_checklist.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> handleRegister() async {
    final username = usernameController.text.trim();
    if (username.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วน')));
      return;
    }
    if (username.contains('@') || username.contains(' ')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ชื่อผู้ใช้ห้ามมีเว้นวรรคหรือเครื่องหมาย @')));
      return;
    }
    final passwordError = PasswordPolicy.firstError(
      passwordController.text,
      username: username,
      email: emailController.text,
    );
    if (passwordError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(passwordError)));
      return;
    }
    if (passwordController.text != confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รหัสผ่านไม่ตรงกัน')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService.instance.register(
        email: emailController.text.trim(),
        password: passwordController.text,
        username: username,
      );
      currentUserProfile['email'] = emailController.text.trim();
      // POST /auth/register ไม่ได้ล็อกอินให้ — กลับไปหน้า login ให้ผู้ใช้เข้าเอง
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
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
                fontWeight: FontWeight.bold, color: Color(0xFFFF9E68))),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFFFF9E68)),
        elevation: 1,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('ข้อมูลพื้นฐานบัญชีผู้ใช้',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF9E68))),
            const SizedBox(height: 16),
            TextField(
                controller: usernameController,
                enabled: !_isLoading,
                decoration: InputDecoration(
                    labelText: 'Username (สำหรับใช้ล็อกอิน) *',
                    helperText: 'ห้ามเว้นวรรค ใช้ล็อกอินแทนอีเมลได้',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)))),
            const SizedBox(height: 16),
            TextField(
                controller: emailController,
                enabled: !_isLoading,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                    labelText: 'อีเมล *',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)))),
            const SizedBox(height: 16),
            TextField(
                controller: passwordController,
                obscureText: _obscurePassword,
                enabled: !_isLoading,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: 'รหัสผ่าน *',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)))),
            PasswordChecklist(
              password: passwordController.text,
              username: usernameController.text,
              email: emailController.text,
            ),
            const SizedBox(height: 16),
            TextField(
                controller: confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                enabled: !_isLoading,
                decoration: InputDecoration(
                    labelText: 'ยืนยันรหัสผ่าน *',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setState(() =>
                          _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)))),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isLoading ? null : handleRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9E68),
                foregroundColor: Colors.white,
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
                  : const Text('สมัครสมาชิก',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
