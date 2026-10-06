import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

/// ตรวจเวอร์ชันใหม่ครั้งเดียวตอนเปิดแอป (เฉพาะ Android) แล้วขึ้นกล่องถามว่าจะอัพเดตไหม
///
/// - กด "อัพเดต" → เปิดลิงก์ดาวน์โหลด APK แล้วให้ Android ติดตั้งทับ (ข้อมูลในแอปยังอยู่ ถ้า APK เซ็นด้วย keystore เดียวกัน)
/// - กด "ภายหลัง" → ปิดกล่อง ถามใหม่ตอนเปิดแอปครั้งหน้า (ไม่ถามซ้ำในรอบเดียวกัน)
///
/// พารามิเตอร์ [check] / [launch] / [enabled] มีไว้ให้เทสต์ใส่ของจำลอง
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child, this.check, this.launch, this.enabled});

  final Widget child;
  final Future<UpdateInfo?> Function()? check;
  final Future<bool> Function(Uri url)? launch;
  final bool? enabled;

  /// ข้อความตามที่กำหนด
  static const String message = 'Petpaws มีเวอร์ชั่นใหม่แล้ว ต้องการอัพเดตเวอร์ชั่นหรือไม่';

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _asked = false;

  bool get _enabled => widget.enabled ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    if (_enabled) WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_asked) return;
    final info = await (widget.check ?? UpdateService.instance.checkForUpdate)();
    if (info == null || !mounted) return;
    _asked = true;

    final update = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('มีเวอร์ชั่นใหม่'),
        content: Text('${UpdateGate.message}\n\n(เวอร์ชั่น ${info.versionName})', key: const ValueKey('update-message')),
        actions: [
          TextButton(
              key: const ValueKey('update-later'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ภายหลัง')),
          TextButton(
              key: const ValueKey('update-now'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('อัพเดต')),
        ],
      ),
    );
    if (update != true || !mounted) return;

    final uri = Uri.parse(info.apkUrl);
    final ok = await (widget.launch ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เปิดลิงก์ดาวน์โหลดไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
