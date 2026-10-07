import 'package:flutter/material.dart';

import '../utils/password_policy.dart';
import '../theme/app_theme.dart';

/// แถบวัดความแข็งแรงและรายการเงื่อนไขรหัสผ่าน แสดงใต้ช่องกรอกรหัสผ่าน
class PasswordChecklist extends StatelessWidget {
  const PasswordChecklist({
    super.key,
    required this.password,
    this.username = '',
    this.email = '',
  });

  final String password;
  final String username;
  final String email;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final rules =
        PasswordPolicy.check(password, username: username, email: email);
    final ratio =
        PasswordPolicy.strength(password, username: username, email: email);
    final color = ratio < 0.5
        ? AppColors.danger
        : (ratio < 1 ? AppColors.warning : AppColors.success);
    final label = ratio < 0.5 ? 'อ่อน' : (ratio < 1 ? 'พอใช้' : 'แข็งแรง');

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextPanel(
        pill: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            ...rules.map(
              (rule) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Icon(
                        rule.passed
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 15,
                        color:
                            rule.passed ? AppColors.success : AppColors.mocha),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(rule.label,
                          style: TextStyle(
                              fontSize: 12,
                              color: rule.passed
                                  ? AppColors.success
                                  : AppColors.textDark)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
