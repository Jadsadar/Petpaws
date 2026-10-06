import 'dart:typed_data';

import '../shared/api_client.dart';
import '../shared/api_exception.dart';

/// อัปโหลดรูปประกาศ/รูปโปรไฟล์ — คืน URL สาธารณะของรูปที่อัปสำเร็จ
///
/// ทางหลัก: ขอใบอนุญาต (POST /media/upload-url) แล้วอัปตรงไป storage เอง แบบเดียวกับไฟล์แชท
/// ไฟล์ไม่ต้องวิ่งผ่าน API และไม่ค้างใน RAM ของ API ระหว่างอัป
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  final ApiClient _api = ApiClient.instance;

  /// อัปโหลดรูปสัตว์เลี้ยง คืนค่า URL ของรูปที่อัปโหลดสำเร็จ
  Future<String> uploadPetImage(Uint8List bytes, {String contentType = 'image/jpeg'}) =>
      uploadImage(bytes, contentType: contentType, filename: 'pet');

  Future<String> uploadImage(
    Uint8List bytes, {
    String contentType = 'image/jpeg',
    String filename = 'image',
  }) async {
    final Map<String, dynamic> grant;
    try {
      grant = await _api.post('/media/upload-url', body: {'contentType': contentType})
          as Map<String, dynamic>;
    } on ApiException catch (e) {
      // backend รุ่นก่อนยังไม่มี upload-url — อัปผ่าน API แบบเดิม
      if (e.statusCode != 404) rethrow;
      return _uploadViaApi(bytes, contentType: contentType, filename: filename);
    }
    final upload = grant['upload'] as Map<String, dynamic>;
    await _api.uploadPresigned(
      url: upload['url'] as String,
      fields: Map<String, String>.from(upload['fields'] as Map),
      bytes: bytes,
      contentType: contentType,
    );
    return grant['url'] as String;
  }

  Future<String> _uploadViaApi(Uint8List bytes, {required String contentType, required String filename}) async {
    final res = await _api.uploadFile(
      '/media/upload',
      bytes: bytes,
      filename: '$filename.${contentType.split('/').last}',
      contentType: contentType,
    ) as Map<String, dynamic>;
    return res['url'] as String;
  }
}
