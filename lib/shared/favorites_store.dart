/// ตัวกลางสถานะ "ถูกใจ" ให้หน้าที่ไม่ได้รับ likedDogs ผ่าน constructor
/// (เช่น โปรไฟล์ผู้อื่นที่เปิดจากหน้าแชท/รายละเอียด) ถามและสั่งถูกใจได้
///
/// MainScreen เป็นเจ้าของรายการถูกใจตัวจริง — attach ตอนสร้าง, detach ตอนทิ้ง
/// ทุกหน้าจึงเห็นค่าเดียวกัน และกดแล้วไปจบที่ POST/DELETE /pets/:id/like เส้นเดิม
class FavoritesStore {
  FavoritesStore._();
  static final FavoritesStore instance = FavoritesStore._();

  bool Function(String petId)? _isLiked;
  void Function(Map<String, dynamic> pet)? _toggle;

  void attach({
    required bool Function(String petId) isLiked,
    required void Function(Map<String, dynamic> pet) toggle,
  }) {
    _isLiked = isLiked;
    _toggle = toggle;
  }

  void detach() {
    _isLiked = null;
    _toggle = null;
  }

  bool isLiked(String? petId) =>
      petId != null && (_isLiked?.call(petId) ?? false);

  void toggle(Map<String, dynamic> pet) => _toggle?.call(pet);
}
