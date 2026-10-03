import '../shared/api_client.dart';

/// จัดการประกาศหาบ้าน (โพสต์, แก้ไข, ลบ, ปัด, ถูกใจ, ฟีด Discover)
///
/// backend คืนค่าเป็น "dog" map ที่ใช้ key เดียวกับที่หน้าจอทั้งหมดใช้อยู่แล้ว
/// (id, ownerId, ownerName, name, breed, province, age, gender, weight, tags,
/// story, imageUrl, status, engagementLikes) จึงส่งต่อ Map<String,dynamic>
/// ตรง ๆ ได้เลยโดยไม่ต้องมี model class แปลงไปมา
class PetService {
  PetService._();
  static final PetService instance = PetService._();

  final ApiClient _api = ApiClient.instance;

  Future<Map<String, dynamic>> create(Map<String, dynamic> fields) async =>
      (await _api.post('/pets', body: fields)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> update(String id, Map<String, dynamic> fields) async =>
      (await _api.patch('/pets/$id', body: fields)) as Map<String, dynamic>;

  Future<void> delete(String id) => _api.delete('/pets/$id');

  Future<Map<String, dynamic>> getOne(String id) async =>
      (await _api.get('/pets/$id')) as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> mine() async {
    final res = await _api.get('/pets/mine') as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// ประกาศทั้งหมดของผู้ใช้คนหนึ่ง ใช้ในหน้าโปรไฟล์สาธารณะ เพื่อให้เห็นประกาศ
  /// ครบเหมือนกันไม่ว่าจะกดเข้ามาจากหน้าไหน
  Future<List<Map<String, dynamic>>> byOwner(String ownerId) async {
    final res = await _api.get('/pets/by-owner/$ownerId') as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> myLikes() async {
    final res = await _api.get('/pets/likes') as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> like(String id) => _api.post('/pets/$id/like');
  Future<void> unlike(String id) => _api.delete('/pets/$id/like');
  Future<void> pass(String id) => _api.post('/pets/$id/pass');
  Future<void> unpass(String id) => _api.delete('/pets/$id/pass');

  /// ฟีดหน้า Discover — deck_feed() ฝั่ง DB จัดการกรอง/จัดลำดับให้หมดแล้ว
  /// (ไม่มีสัตว์ตัวเอง, ไม่มีตัวที่เคยปัด, เรียงจังหวัดใกล้ก่อน)
  Future<DeckPage> deck({String? cursor, String? province, String? species, List<String>? tags}) async {
    final query = <String, String>{
      if (cursor != null) 'cursor': cursor,
      if (province != null && province.isNotEmpty) 'province': province,
      if (species != null && species.isNotEmpty) 'species': species,
      if (tags != null && tags.isNotEmpty) 'tags': tags.join(','),
    };
    final res = await _api.get('/pets/deck', query: query) as Map<String, dynamic>;
    return DeckPage(
      dogs: (res['dogs'] as List).cast<Map<String, dynamic>>(),
      nextCursor: res['nextCursor'] as String?,
      hasMore: res['hasMore'] as bool,
    );
  }
}

class DeckPage {
  DeckPage({required this.dogs, required this.nextCursor, required this.hasMore});

  final List<Map<String, dynamic>> dogs;
  final String? nextCursor;
  final bool hasMore;
}
