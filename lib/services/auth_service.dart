import 'dart:async';
import 'dart:typed_data';

import '../shared/api_client.dart';
import '../shared/api_exception.dart';
import '../shared/app_user.dart';
import '../shared/token_storage.dart';
import 'chat_socket.dart';

/// ห่อการเรียก auth API ไว้ที่เดียว — แทนที่ FirebaseAuth เดิมทั้งหมด
/// รองรับล็อกอินด้วย username หรือ email (ตรงกับ POST /auth/login ที่รับ
/// "identifier" แล้วแยกเองว่ามี '@' ไหม)
class AuthService {
  AuthService._() {
    // token refresh ล้มเหลว (refresh token หมดอายุ/ถูกเพิกถอน) ต้องเคลียร์
    // currentUser ทันที ไม่งั้น UI จะเข้าใจผิดว่ายังล็อกอินอยู่ทั้งที่ request ถัดไปจะ 401 ซ้ำ
    _api.onSessionExpired = () {
      ChatSocket.instance.disconnect();
      _currentUser = null;
      _controller.add(null);
    };
  }
  static final AuthService instance = AuthService._();

  final ApiClient _api = ApiClient.instance;
  final TokenStorage _tokenStorage = TokenStorage.instance;

  AppUser? _currentUser;
  final _controller = StreamController<AppUser?>.broadcast();

  /// ใช้กับ StreamBuilder — ต้องแนบ initialData: currentUser ด้วยเสมอ เพราะ
  /// broadcast controller ไม่ replay ค่าล่าสุดให้ subscriber ที่เข้ามาทีหลัง
  Stream<AppUser?> get authStateChanges => _controller.stream;

  AppUser? get currentUser => _currentUser;

  /// เรียกครั้งเดียวตอนแอปเริ่ม (ก่อน runApp) — เช็คว่ามี token ที่ยังใช้ได้ค้างอยู่ไหม
  /// ถ้ามีให้ดึงโปรไฟล์มาเติม currentUser ทันที แทนที่ผู้ใช้จะต้องล็อกอินใหม่ทุกครั้ง
  ///
  /// มี timeout กันไว้เสมอ — เพราะ main() รอ Future นี้ก่อนเรียก runApp() ถ้า request
  /// นี้ค้าง (backend ไม่ตอบ/เน็ตมีปัญหา) แล้วไม่มี timeout แอปจะค้างที่หน้าโหลด
  /// เปล่า ๆ ตลอดไปโดยไม่มีทางออก แทนที่จะ fallback ไปหน้า login ให้ลองใหม่ได้
  Future<void> restoreSession() async {
    final token = await _tokenStorage.readAccessToken();
    if (token == null) {
      _controller.add(null);
      return;
    }
    try {
      final me = await _api
          .get('/users/me')
          .timeout(const Duration(seconds: 8)) as Map<String, dynamic>;
      // /users/me ไม่ได้คืน profileCompleted ตรง ๆ (มันเป็น field ของ /auth endpoints)
      // แต่การที่ดึงโปรไฟล์สำเร็จ + มีชื่อแล้ว ก็ตีความได้ว่ากรอกโปรไฟล์แล้ว
      final displayName = (me['name'] as String?) ?? '';
      _currentUser = AppUser(
        uid: me['id'] as String,
        username: me['username'] as String,
        email: me['email'] as String,
        displayName: displayName,
        photoURL: (me['profileImageUrl'] as String?)?.isEmpty == true
            ? null
            : me['profileImageUrl'] as String?,
        profileCompleted: displayName != (me['username'] as String),
      );
      ChatSocket.instance.connect();
      _controller.add(_currentUser);
    } catch (_) {
      await _tokenStorage.clear();
      _currentUser = null;
      _controller.add(null);
    }
  }

  Future<void> signIn({required String identifier, required String password}) async {
    try {
      final res = await _api.post(
        '/auth/login',
        body: {'identifier': identifier, 'password': password},
        auth: false,
      ) as Map<String, dynamic>;

      await _tokenStorage.save(
        accessToken: res['accessToken'] as String,
        refreshToken: res['refreshToken'] as String,
      );
      _currentUser = AppUser.fromJson(res['user'] as Map<String, dynamic>);
      ChatSocket.instance.connect();
      _controller.add(_currentUser);
    } on ApiException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  /// สมัครสมาชิกด้วย username + email + password เท่านั้น ยังไม่มีชื่อเล่น
  /// (ตรงกับ POST /auth/register ที่ไม่ auto sign-in ให้ — ต้องไปกด login เอง)
  Future<void> register({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      await _api.post(
        '/auth/register',
        body: {'username': username, 'email': email, 'password': password},
        auth: false,
      );
    } on ApiException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  /// บันทึกชื่อเล่น + ข้อมูลโปรไฟล์อื่น ๆ — extraFields ใช้ชื่อ key เดียวกับ
  /// UpdateProfileDto ฝั่ง backend อยู่แล้ว (phone, lineId, fbLink, homeType, traits)
  /// จึงส่งต่อได้ตรง ๆ โดยไม่ต้องแปลงชื่อ
  Future<void> completeProfile({
    required String displayName,
    Map<String, dynamic> extraFields = const {},
  }) async {
    final res = await _api.patch('/users/me', body: {
      'name': displayName,
      ...extraFields,
    }) as Map<String, dynamic>;

    _currentUser = _currentUser?.copyWith(displayName: displayName, profileCompleted: true) ??
        AppUser(
          uid: res['id'] as String,
          username: res['username'] as String,
          email: res['email'] as String,
          displayName: displayName,
          profileCompleted: true,
        );
    _controller.add(_currentUser);
  }

  /// อัปโหลดรูปโปรไฟล์ขึ้น media service แล้วบันทึก URL ลงโปรไฟล์ทันที
  /// คืนค่า URL ของรูปที่อัปโหลดสำเร็จ
  Future<String> uploadProfileImage(Uint8List bytes, {String contentType = 'image/jpeg'}) async {
    if (_currentUser == null) throw AuthFailure('กรุณาเข้าสู่ระบบก่อน');

    final uploadRes = await _api.uploadFile(
      '/media/upload',
      bytes: bytes,
      filename: 'profile.${contentType.split('/').last}',
      contentType: contentType,
    ) as Map<String, dynamic>;
    final url = uploadRes['url'] as String;

    await _api.patch('/users/me', body: {'profileImageUrl': url});
    _currentUser = AppUser(
      uid: _currentUser!.uid,
      username: _currentUser!.username,
      email: _currentUser!.email,
      displayName: _currentUser!.displayName,
      photoURL: url,
      profileCompleted: _currentUser!.profileCompleted,
    );
    _controller.add(_currentUser);
    return url;
  }

  Future<void> signOut() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken != null) {
      // ไม่สนใจว่า logout ที่ server สำเร็จไหม — เคลียร์ token ในเครื่องเสมอ
      try {
        await _api.post('/auth/logout', body: {'refreshToken': refreshToken}, auth: false);
      } catch (_) {}
    }
    ChatSocket.instance.disconnect();
    await _tokenStorage.clear();
    _currentUser = null;
    _controller.add(null);
  }
}

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
