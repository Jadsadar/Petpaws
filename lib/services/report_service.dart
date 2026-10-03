import '../shared/api_client.dart';

/// ส่งรายงานเข้าคิวของแอดมิน (POST /reports) — เป้าหมายต้องมีพอดี 1 อย่าง:
/// ประกาศสัตว์ / ตัวผู้ใช้ / ข้อความในแชท (ตรงกับ CHECK reports_exactly_one_target ใน DB)
///
/// [reason] ต้องเป็นค่าใน utils/report_reasons.dart (backend ตรวจ enum ตายตัว)
/// ข้อความ: backend ตรวจว่าผู้รายงานอยู่ในแชทนั้นและไม่ใช่ข้อความของตัวเอง
class ReportService {
  ReportService._();
  static final ReportService instance = ReportService._();

  final ApiClient _api = ApiClient.instance;

  Future<void> reportMessage(String messageId, {required String reason, String? detail}) =>
      _send({'reportedMessageId': messageId}, reason, detail);

  Future<void> reportPet(String petId, {required String reason, String? detail}) =>
      _send({'reportedPetId': petId}, reason, detail);

  Future<void> reportUser(String userId, {required String reason, String? detail}) =>
      _send({'reportedUserId': userId}, reason, detail);

  /// บล็อกมีผลสองทาง: ห้องแชทของทั้งคู่ถูกปิด และ deck ไม่แสดงประกาศของกันและกัน
  Future<void> blockUser(String userId) => _api.post('/blocks', body: {'blockedUserId': userId});

  Future<void> unblockUser(String userId) => _api.delete('/blocks/$userId');

  Future<void> _send(Map<String, String> target, String reason, String? detail) async {
    final text = detail?.trim() ?? '';
    await _api.post('/reports', body: {
      ...target,
      'reason': reason,
      if (text.isNotEmpty) 'detail': text,
    });
  }
}
