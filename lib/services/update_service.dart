import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// เวอร์ชันใหม่ที่พบบน GitHub Releases
class UpdateInfo {
  const UpdateInfo({required this.buildNumber, required this.versionName, required this.apkUrl});

  /// เลข build ของ release นั้น (ตรงกับ --build-number ที่ CI ใช้สร้าง APK)
  final int buildNumber;

  /// ชื่อเวอร์ชันที่แสดง เช่น 1.0.25
  final String versionName;

  /// ลิงก์ดาวน์โหลดไฟล์ APK
  final String apkUrl;
}

/// ตรวจว่ามีเวอร์ชันใหม่ของแอปหรือยัง โดยดู release ล่าสุดบน GitHub
///
/// ทำไมใช้ GitHub Releases ตรงๆ: workflow release.yml สร้าง APK แล้วออก release ชื่อ tag `v1.0.<เลขรอบ>`
/// ทุกครั้งที่ merge เข้า main อยู่แล้ว และเลขรอบนั้นก็คือ --build-number ของ APK ด้วย
/// จึงเทียบเลขกับ build number ที่ติดตั้งอยู่ในเครื่องได้ตรงๆ ไม่ต้องมี endpoint เพิ่มฝั่ง backend
/// (repo เป็น public จึงเรียก API และดาวน์โหลด APK ได้โดยไม่ต้องล็อกอิน)
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String repo = 'Jadsadar/Petpaws';
  static const Duration timeout = Duration(seconds: 10);

  /// tag รูปแบบ v1.0.25 → 25 (รูปแบบอื่นไม่ใช่ release ของแอป คืน null)
  static int? buildFromTag(String tag) {
    final m = RegExp(r'^v?\d+\.\d+\.(\d+)$').firstMatch(tag.trim());
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// คืนข้อมูลเวอร์ชันใหม่ถ้ามี release ที่เลข build สูงกว่า [currentBuild] (ไม่ระบุ = อ่านจากแอปที่ติดตั้ง)
  /// ตรวจไม่ได้ (เน็ตหลุด, GitHub จำกัดคำขอ, release ไม่มี APK) = คืน null เงียบๆ
  /// การตรวจอัปเดตต้องไม่รบกวนการใช้แอป
  Future<UpdateInfo?> checkForUpdate({int? currentBuild}) async {
    try {
      final current = currentBuild ?? int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
      if (current == null) return null;

      final res = await http.get(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(timeout);
      if (res.statusCode != 200) return null;

      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final tag = (json['tag_name'] as String?) ?? '';
      final latest = buildFromTag(tag);
      if (latest == null || latest <= current) return null;

      final assets = (json['assets'] as List?) ?? const [];
      for (final a in assets) {
        final asset = a as Map<String, dynamic>;
        final name = (asset['name'] as String?) ?? '';
        final url = (asset['browser_download_url'] as String?) ?? '';
        if (name.endsWith('.apk') && url.startsWith('https://')) {
          return UpdateInfo(
            buildNumber: latest,
            versionName: tag.replaceFirst(RegExp(r'^v'), ''),
            apkUrl: url,
          );
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
