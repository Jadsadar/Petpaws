import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import 'api_exception.dart';
import 'token_storage.dart';

/// จุดเดียวที่คุยกับ backend/api ทั้งหมด — ตาม SKILL.md: "fetch API ตรงใน
/// component ต้องผ่าน api.ts ของฟีเจอร์เสมอ" (ที่นี่คือ ApiClient ตัวกลาง)
///
/// หน้าที่หลัก: แนบ access token ทุก request, ถ้าโดน 401 เพราะ token หมดอายุ
/// จะลอง refresh ให้อัตโนมัติ "ครั้งเดียว" แล้วยิง request เดิมซ้ำ — ถ้า refresh
/// ก็ยังไม่ผ่านอีก ค่อยเคลียร์ token ทิ้งแล้วโยน exception ให้ชั้นบนพาไปหน้า login
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  // ตอนนี้แอปรันเป็น web เท่านั้น (ไม่มีโฟลเดอร์ android/ios) จึง hardcode
  // localhost ตรง ๆ ได้ — วันที่ลงมือถือจริงต้องเปลี่ยนเป็น 10.0.2.2 (Android
  // emulator) หรือ IP เครื่อง แล้วอาจต้องทำเป็น build-time config แทน
  static const String baseUrl = 'http://localhost:3000';

  final _tokenStorage = TokenStorage.instance;

  /// เรียกตอน logout หรือ refresh ล้มเหลว ให้ AuthService ไปแจ้ง UI ต่อ
  void Function()? onSessionExpired;

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await _tokenStorage.readAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  dynamic _decode(http.Response res) {
    final text = res.bodyBytes.isEmpty ? '{}' : utf8.decode(res.bodyBytes);
    final decoded = jsonDecode(text);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    final error = (decoded is Map ? decoded['error'] : null) as Map?;
    throw ApiException(
      res.statusCode,
      (error?['code'] as String?) ?? 'ERROR',
      (error?['message'] as String?) ?? 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
    );
  }

  Future<dynamic> get(String path, {Map<String, String>? query, bool auth = true}) =>
      _withRefresh(() async {
        final res = await http.get(_uri(path, query), headers: await _headers(auth: auth));
        return _decode(res);
      }, auth);

  Future<dynamic> post(String path, {Object? body, bool auth = true}) => _withRefresh(() async {
        final res = await http.post(
          _uri(path),
          headers: await _headers(auth: auth),
          body: body == null ? null : jsonEncode(body),
        );
        return _decode(res);
      }, auth);

  Future<dynamic> patch(String path, {Object? body, bool auth = true}) => _withRefresh(() async {
        final res = await http.patch(
          _uri(path),
          headers: await _headers(auth: auth),
          body: body == null ? null : jsonEncode(body),
        );
        return _decode(res);
      }, auth);

  Future<dynamic> delete(String path, {bool auth = true}) => _withRefresh(() async {
        final res = await http.delete(_uri(path), headers: await _headers(auth: auth));
        return _decode(res);
      }, auth);

  /// อัปโหลดไฟล์แบบ multipart — ใช้กับ POST /media/upload เท่านั้น
  Future<dynamic> uploadFile(
    String path, {
    required Uint8List bytes,
    required String filename,
    required String contentType,
  }) =>
      _withRefresh(() async {
        final token = await _tokenStorage.readAccessToken();
        final request = http.MultipartRequest('POST', _uri(path))
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: filename,
            contentType: _parseContentType(contentType),
          ));
        final streamed = await request.send();
        final res = await http.Response.fromStream(streamed);
        return _decode(res);
      }, true);

  /// ทำ request ที่ส่งเข้ามา ถ้าเจอ 401 (token หมดอายุ) จะ refresh แล้วลองซ้ำ
  /// "ครั้งเดียว" กันวนลูปไม่รู้จบถ้า refresh token เองก็ใช้ไม่ได้แล้ว
  Future<dynamic> _withRefresh(Future<dynamic> Function() run, bool auth) async {
    try {
      return await run();
    } on ApiException catch (e) {
      if (!auth || !e.isUnauthorized) rethrow;

      final refreshed = await _tryRefresh();
      if (!refreshed) {
        onSessionExpired?.call();
        rethrow;
      }
      return run();
    }
  }

  // ถ้ามีหลาย request โดน 401 พร้อมกัน (เช่น deck + likes + unread-count ยิงพร้อม
  // กันตอน token หมดอายุพอดี) ต้องให้ทุก request รอผลของการ refresh "ครั้งเดียวกัน"
  // ไม่ใช่ปล่อยให้ request ที่มาทีหลังเห็นว่ากำลัง refresh อยู่แล้วก็ถือว่าล้มเหลวทันที
  // (เดิมเป็นแบบนั้น ทำให้ session ถูกเคลียร์ทิ้งทั้งที่ refresh ตัวแรกกำลังจะสำเร็จ)
  Future<bool>? _refreshFuture;

  /// ให้ WebSocket ใช้ refresh ตัวเดียวกับ REST (single-flight เดียวกัน) ตอน server
  /// ปฏิเสธ token — ถ้า refresh ไม่ผ่านถือว่า session หมด แจ้ง UI เหมือนฝั่ง REST
  Future<bool> refreshSession() async {
    final ok = await _tryRefresh();
    if (!ok) onSessionExpired?.call();
    return ok;
  }

  Future<bool> _tryRefresh() {
    return _refreshFuture ??= _doRefresh().whenComplete(() => _refreshFuture = null);
  }

  Future<bool> _doRefresh() async {
    try {
      final refreshToken = await _tokenStorage.readRefreshToken();
      if (refreshToken == null) return false;

      final res = await http.post(
        _uri('/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (res.statusCode != 200) {
        await _tokenStorage.clear();
        return false;
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      await _tokenStorage.save(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

MediaType _parseContentType(String contentType) {
  final parts = contentType.split('/');
  return MediaType(parts.first, parts.length > 1 ? parts[1] : 'octet-stream');
}
