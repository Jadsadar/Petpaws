import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ข้อความเตือนใต้ช่องกรอก: ไอคอน ! + ตัวอักษรแดงอิฐ ไม่มีกรอบ
/// ([message] = null ไม่แสดงอะไร) ใช้แทนแจ้งเตือนเด้งด้านล่าง
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key, this.padding = const EdgeInsets.only(top: 6, left: 4)});

  final String? message;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final msg = message;
    if (msg == null) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          const SizedBox(width: 6),
          Expanded(
            child: Text(msg,
                style: const TextStyle(fontSize: 14, color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}

/// เก็บข้อความเตือนรายช่องของหน้า แสดงค้างจนกว่าจะแก้ไขแล้วกดส่งใหม่ (ไม่หายเอง)
/// ใช้: showFieldError('name', 'กรุณา...') แล้ววาง InlineError(fieldError('name')) ใต้ช่อง
/// หรือ InputDecoration(error: fieldErrorWidget('name')) ในช่องกรอก (ขอบช่องเป็นสีแดงด้วย)
mixin FieldErrors<T extends StatefulWidget> on State<T> {
  final Map<String, String> _fieldErrors = {};

  String? fieldError(String key) => _fieldErrors[key];

  /// สำหรับ InputDecoration.error — null เมื่อไม่มี error (ช่องกลับเป็นปกติ)
  Widget? fieldErrorWidget(String key) {
    final msg = _fieldErrors[key];
    return msg == null ? null : InlineError(msg, padding: EdgeInsets.zero);
  }

  void showFieldError(String key, String message) {
    setState(() {
      _fieldErrors
        ..clear()
        ..[key] = message;
    });
  }

  void clearFieldErrors() {
    if (!mounted || _fieldErrors.isEmpty) return;
    setState(_fieldErrors.clear);
  }

}
