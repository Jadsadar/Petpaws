import '../shared/api_client.dart';
import '../shared/api_exception.dart';

// ป้ายภาษาไทยของเหตุผลรายงานอยู่ใน utils/report_reasons.dart (ใช้ร่วมกับฝั่งผู้ใช้ที่ส่งรายงาน)

/// เรียก API ฝั่งแอดมิน (backend/api/src/admin) ทั้งหมดที่เดียว
/// ทุก endpoint ถูกคุมด้วย AdminGuard ฝั่ง server (เช็ก users.is_admin จาก DB ทุกครั้ง)
/// ฝั่งแอปจึงไม่ต้องเชื่อถือ flag อะไรเอง แค่ซ่อนปุ่มไว้เพื่อ UX เท่านั้น
class AdminService {
  AdminService._();
  static final AdminService instance = AdminService._();

  final ApiClient _api = ApiClient.instance;

  /// ขนาดหน้ามาตรฐานของทุกรายการในหน้าแอดมิน (backend รับสูงสุด 50)
  static const int pageSize = 20;

  /// ผลเช็คสิทธิ์แอดมินของผู้ใช้ที่ล็อกอินอยู่ — จำไว้ ไม่ยิงซ้ำทุกครั้ง
  bool? _isAdmin;

  /// ตอนนี้ backend ยังไม่ส่ง isAdmin มากับ /auth/login หรือ /users/me เลยใช้วิธี
  /// ลองเรียก endpoint ของแอดมินที่อ่านอย่างเดียว: 200 = แอดมิน, 403 = ไม่ใช่
  /// ข้อผิดพลาดอื่น (เน็ตหลุด ฯลฯ) ถือว่า "ไม่รู้" และไม่จำผล เพื่อให้ลองใหม่ครั้งหน้า
  Future<bool> checkIsAdmin() async {
    if (_isAdmin != null) return _isAdmin!;
    try {
      await _api.get('/admin/banned-users', query: {'page': '1', 'pageSize': '1'});
      return _isAdmin = true;
    } on ApiException catch (e) {
      if (e.statusCode == 403) return _isAdmin = false;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// เรียกตอนออกจากระบบ กันผลของบัญชีเก่าค้างไปให้บัญชีถัดไป
  void clearCache() => _isAdmin = null;

  Map<String, String> _paging(int page, int size) => {'page': '$page', 'pageSize': '$size'};

  /// ผู้ใช้ที่ถูกรายงานตั้งแต่ [minReports] คนขึ้นไป (นับคนรายงานไม่ซ้ำ) แบ่งหน้า
  Future<AdminPage<ReportedUser>> reportedUsers({int minReports = 1, int page = 1, int size = pageSize}) async {
    final res = await _api.get('/admin/reported-users',
        query: {'minReports': '$minReports', ..._paging(page, size)}) as Map<String, dynamic>;
    return AdminPage.fromJson(res, ReportedUser.fromJson);
  }

  Future<AdminPage<UserReport>> userReports(String userId, {int page = 1, int size = pageSize}) async {
    final res = await _api.get('/admin/users/$userId/reports', query: _paging(page, size))
        as Map<String, dynamic>;
    return AdminPage.fromJson(res, UserReport.fromJson);
  }

  Future<AdminPage<BannedUser>> bannedUsers({int page = 1, int size = pageSize}) async {
    final res = await _api.get('/admin/banned-users', query: _paging(page, size)) as Map<String, dynamic>;
    return AdminPage.fromJson(res, BannedUser.fromJson);
  }

  /// ตัวเลขสรุปบนแดชบอร์ด (นับทั้งระบบ ไม่ขึ้นกับหน้าที่แอดมินเปิดอยู่)
  Future<AdminSummary> summary() async {
    final res = await _api.get('/admin/summary') as Map<String, dynamic>;
    return AdminSummary(
      reported: (res['reported'] as num?)?.toInt() ?? 0,
      temporary: (res['temporary'] as num?)?.toInt() ?? 0,
      permanent: (res['permanent'] as num?)?.toInt() ?? 0,
    );
  }

  /// โปรไฟล์ + ประกาศทั้งหมดของผู้ใช้พร้อมรูป (ให้แอดมินตรวจสิ่งที่ถูกรายงาน)
  Future<AdminProfile> profile(String userId) async {
    final res = await _api.get('/admin/users/$userId') as Map<String, dynamic>;
    return AdminProfile.fromJson(res);
  }

  /// [days] เป็น null = แบนถาวร (จนกว่าแอดมินจะปลดเอง)
  /// การแบนจะเตะผู้ใช้ออกจากทุกเครื่อง ปิดรายงานค้างของเขา และล็อกอินใหม่ไม่ได้
  Future<void> ban(String userId, {int? days, String? note}) async {
    await _api.post('/admin/users/$userId/ban', body: {
      if (days != null) 'days': days,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<void> unban(String userId) async {
    await _api.post('/admin/users/$userId/unban');
  }

  /// ปัดรายงานทั้งหมดของผู้ใช้นี้ทิ้ง (ตรวจแล้วไม่ผิด) โดยไม่แบน
  Future<void> dismissReports(String userId) async {
    await _api.post('/admin/users/$userId/dismiss-reports');
  }
}

DateTime? _parseDate(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// หนึ่งหน้าของรายการแบ่งหน้า — [total] คือจำนวนทั้งหมดก่อนแบ่งหน้า
class AdminPage<T> {
  const AdminPage({required this.items, required this.total, required this.page, required this.pageSize});

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;

  factory AdminPage.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) parse) => AdminPage(
        items: (j['items'] as List<dynamic>).map((e) => parse(e as Map<String, dynamic>)).toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 1,
        pageSize: (j['pageSize'] as num?)?.toInt() ?? AdminService.pageSize,
      );

  /// จำนวนหน้าทั้งหมด (อย่างน้อย 1 เพื่อให้แสดง "หน้า 1 / 1" ได้แม้รายการว่าง)
  int get totalPages => total <= 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);
  bool get hasPrevious => page > 1;
  bool get hasNext => page < totalPages;
}

class AdminSummary {
  const AdminSummary({required this.reported, required this.temporary, required this.permanent});

  /// จำนวนผู้ใช้ที่ถูกรายงานและยังรอตรวจ / ถูกแบนชั่วคราว / ถูกแบนถาวร
  final int reported;
  final int temporary;
  final int permanent;
}

class ReportedUser {
  const ReportedUser({
    required this.id,
    required this.username,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
    required this.reportCount,
    required this.lastReportedAt,
  });

  final String id;
  final String username;
  final String email;
  final String displayName;
  final String avatarUrl;
  final int reportCount;
  final DateTime? lastReportedAt;

  factory ReportedUser.fromJson(Map<String, dynamic> j) => ReportedUser(
        id: j['id'] as String,
        username: j['username'] as String,
        email: (j['email'] as String?) ?? '',
        displayName: (j['displayName'] as String?) ?? '',
        avatarUrl: (j['avatarUrl'] as String?) ?? '',
        reportCount: (j['reportCount'] as num?)?.toInt() ?? 0,
        lastReportedAt: _parseDate(j['lastReportedAt']),
      );

  String get title => displayName.isNotEmpty ? displayName : username;
}

class BannedUser {
  const BannedUser({
    required this.id,
    required this.username,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
    required this.suspendedUntil,
    required this.permanent,
  });

  final String id;
  final String username;
  final String email;
  final String displayName;
  final String avatarUrl;
  final DateTime? suspendedUntil;
  final bool permanent;

  factory BannedUser.fromJson(Map<String, dynamic> j) => BannedUser(
        id: j['id'] as String,
        username: j['username'] as String,
        email: (j['email'] as String?) ?? '',
        displayName: (j['displayName'] as String?) ?? '',
        avatarUrl: (j['avatarUrl'] as String?) ?? '',
        suspendedUntil: _parseDate(j['suspendedUntil']),
        permanent: (j['permanent'] as bool?) ?? false,
      );

  String get title => displayName.isNotEmpty ? displayName : username;
}

/// รูปหนึ่งใบของประกาศ ([thumbUrl] ใช้แสดงภาพย่อ ถ้าไม่มีให้ใช้ [url] แทน)
class PetPhoto {
  const PetPhoto({required this.url, this.thumbUrl});

  final String url;
  final String? thumbUrl;

  factory PetPhoto.fromJson(Map<String, dynamic> j) =>
      PetPhoto(url: j['url'] as String, thumbUrl: j['thumbUrl'] as String?);

  String get previewUrl => (thumbUrl != null && thumbUrl!.isNotEmpty) ? thumbUrl! : url;
}

List<PetPhoto> _photos(Object? v) =>
    ((v as List<dynamic>?) ?? const []).map((e) => PetPhoto.fromJson(e as Map<String, dynamic>)).toList();

/// ประกาศสัตว์ที่ถูกรายงาน (หรือของผู้ใช้ที่แอดมินเปิดดูโปรไฟล์)
class AdminPet {
  const AdminPet({
    required this.id,
    required this.name,
    required this.species,
    required this.status,
    required this.description,
    required this.deleted,
    required this.photos,
    this.location = '',
    this.createdAt,
  });

  final String id;
  final String name;
  final String species;
  final String status;
  final String description;
  final bool deleted;
  final List<PetPhoto> photos;
  final String location;
  final DateTime? createdAt;

  factory AdminPet.fromJson(Map<String, dynamic> j) => AdminPet(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '-',
        species: (j['species'] as String?) ?? '',
        status: (j['status'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        deleted: (j['deleted'] as bool?) ?? false,
        photos: _photos(j['photos']),
        location: (j['location'] as String?) ?? '',
        createdAt: _parseDate(j['createdAt']),
      );

  /// ป้ายสถานะสำหรับแอดมิน: ลบแล้ว > รับเลี้ยงแล้ว > ยังเปิดอยู่
  String get statusLabel => deleted ? 'ถูกลบ' : (status == 'adopted' ? 'ได้บ้านแล้ว' : 'ยังเปิดรับเลี้ยง');
}

class UserReport {
  const UserReport({
    required this.id,
    required this.reason,
    required this.detail,
    required this.createdAt,
    required this.reporterName,
    required this.targetType,
    required this.petName,
    required this.messageBody,
    this.pet,
    this.messageCreatedAt,
  });

  final String id;
  final String reason;
  final String detail;
  final DateTime? createdAt;
  final String reporterName;

  /// 'user' | 'pet' | 'message' — รายงานตัวผู้ใช้ตรง ๆ, ประกาศสัตว์ของเขา, หรือข้อความที่เขาส่ง
  final String targetType;
  final String? petName;

  /// เฉพาะข้อความที่ถูกรายงานข้อความเดียว (แอดมินไม่เห็นส่วนอื่นของแชท)
  final String? messageBody;
  final DateTime? messageCreatedAt;

  /// รายละเอียดประกาศพร้อมรูป เมื่อ [targetType] เป็น 'pet'
  final AdminPet? pet;

  factory UserReport.fromJson(Map<String, dynamic> j) {
    final reporter = (j['reporter'] as Map<String, dynamic>?) ?? const {};
    final name = (reporter['displayName'] as String?) ?? '';
    final pet = j['pet'] as Map<String, dynamic>?;
    return UserReport(
      id: j['id'] as String,
      reason: (j['reason'] as String?) ?? 'other',
      detail: (j['detail'] as String?) ?? '',
      createdAt: _parseDate(j['createdAt']),
      reporterName: name.isNotEmpty ? name : (reporter['username'] as String? ?? '-'),
      targetType: (j['targetType'] as String?) ?? 'user',
      petName: j['petName'] as String?,
      messageBody: j['messageBody'] as String?,
      messageCreatedAt: _parseDate(j['messageCreatedAt']),
      pet: pet == null ? null : AdminPet.fromJson(pet),
    );
  }
}

/// โปรไฟล์ที่แอดมินเปิดดู: ข้อมูลบัญชี + ประกาศทั้งหมดพร้อมรูป (ไม่มีเบอร์โทร/ไลน์)
class AdminProfile {
  const AdminProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
    required this.bio,
    required this.province,
    required this.homeType,
    required this.isSuspended,
    required this.suspendedUntil,
    required this.createdAt,
    required this.lastLoginAt,
    required this.pendingReportCount,
    required this.pets,
  });

  final String id;
  final String username;
  final String email;
  final String displayName;
  final String avatarUrl;
  final String bio;
  final String province;
  final String homeType;
  final bool isSuspended;
  final DateTime? suspendedUntil;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final int pendingReportCount;
  final List<AdminPet> pets;

  factory AdminProfile.fromJson(Map<String, dynamic> j) => AdminProfile(
        id: j['id'] as String,
        username: j['username'] as String,
        email: (j['email'] as String?) ?? '',
        displayName: (j['displayName'] as String?) ?? '',
        avatarUrl: (j['avatarUrl'] as String?) ?? '',
        bio: (j['bio'] as String?) ?? '',
        province: (j['province'] as String?) ?? '',
        homeType: (j['homeType'] as String?) ?? '',
        isSuspended: (j['isSuspended'] as bool?) ?? false,
        suspendedUntil: _parseDate(j['suspendedUntil']),
        createdAt: _parseDate(j['createdAt']),
        lastLoginAt: _parseDate(j['lastLoginAt']),
        pendingReportCount: (j['pendingReportCount'] as num?)?.toInt() ?? 0,
        pets: ((j['pets'] as List<dynamic>?) ?? const [])
            .map((e) => AdminPet.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String get title => displayName.isNotEmpty ? displayName : username;
}
