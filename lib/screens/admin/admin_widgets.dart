import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/api_exception.dart';

const Color adminOrange = Color(0xFFFF9E68);

final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');

String formatDateTime(DateTime? d) => d == null ? '-' : _dateTimeFormat.format(d);
String formatDate(DateTime? d) => d == null ? '-' : _dateFormat.format(d);

/// ข้อความ error ที่แสดงให้แอดมินอ่านได้ (ใช้ข้อความไทยจาก backend ถ้ามี)
String adminErrorMessage(Object e) =>
    e is ApiException ? e.message : 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';

void showAdminSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

class AdminErrorView extends StatelessWidget {
  const AdminErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(adminErrorMessage(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminEmptyView extends StatelessWidget {
  const AdminEmptyView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_user_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}
