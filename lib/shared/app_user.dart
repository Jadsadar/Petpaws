/// แทนที่ Firebase `User` object เดิม — เก็บแค่ field ที่หน้าจอต่าง ๆ ใช้จริง
/// (`.uid`, `.displayName`, `.email`) เพื่อให้โค้ดที่เคยเขียนอิง Firebase User
/// เปลี่ยนมาใช้ตัวนี้ได้โดยแก้ชื่อ type อย่างเดียว ไม่ต้องรื้อ logic
class AppUser {
  const AppUser({
    required this.uid,
    required this.username,
    required this.email,
    required this.displayName,
    this.photoURL,
    this.profileCompleted = false,
    this.province,
  });

  final String uid;
  final String username;
  final String email;
  final String displayName;
  final String? photoURL;
  final bool profileCompleted;

  /// จังหวัดในโปรไฟล์ ใช้เติมค่าเริ่มต้นตอนลงประกาศ — null = ยังไม่รู้ (backend รุ่นเก่า
  /// ไม่ส่งมากับผลล็อกอิน) ต้องถามจาก GET /users/me เอง ส่วน '' = รู้แล้วว่าไม่ได้ตั้งไว้
  final String? province;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        uid: json['id'] as String,
        username: json['username'] as String,
        email: json['email'] as String,
        displayName: (json['displayName'] as String?) ?? '',
        photoURL: json['avatarUrl'] as String?,
        profileCompleted: (json['profileCompleted'] as bool?) ?? false,
        province: json.containsKey('province') ? (json['province'] as String?) ?? '' : null,
      );

  AppUser copyWith({String? displayName, String? photoURL, bool? profileCompleted, String? province}) =>
      AppUser(
        uid: uid,
        username: username,
        email: email,
        displayName: displayName ?? this.displayName,
        photoURL: photoURL ?? this.photoURL,
        profileCompleted: profileCompleted ?? this.profileCompleted,
        province: province ?? this.province,
      );
}
