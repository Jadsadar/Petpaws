import 'dart:async';

import '../shared/api_client.dart';
import 'chat_socket.dart';

/// แชท: ส่ง/อ่าน/ดึงประวัติผ่าน REST ส่วนของที่เปลี่ยน "สด" มาทาง WebSocket
/// ([ChatSocket]) — หน้าจอดึง REST ครั้งแรกครั้งเดียว แล้วอัปเดตตาม event
/// ไม่มีการ poll ซ้ำเป็นช่วง ๆ อีกแล้ว
///
/// ทุกครั้งที่ socket ต่อใหม่ (เน็ตหลุดแล้วกลับมา) จะดึง REST ซ้ำหนึ่งรอบ
/// เพราะ event ที่เกิดระหว่างหลุดหายไปแล้ว ไม่มีการส่งย้อนหลัง
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final ApiClient _api = ApiClient.instance;
  final ChatSocket _socket = ChatSocket.instance;

  /// สร้างห้องแชทถ้ายังไม่มี พร้อมข้อความแรกในธุรกรรมเดียวกัน (ตาม SKILL.md
  /// "ห้องแชทเกิดตอนผู้ใช้กดส่งข้อความแรกเท่านั้น") หรือถ้ามีห้องอยู่แล้ว
  /// จะแนบข้อความนี้ต่อท้ายห้องเดิมให้เลย คืนค่า chatId เสมอ
  Future<String> createOrSend({required String petId, required String message}) async {
    final res = await _api.post('/chats', body: {'petId': petId, 'message': message})
        as Map<String, dynamic>;
    return res['chatId'] as String;
  }

  /// รายการห้องแชททั้งหมดของฉัน กรองด้วยชื่อสัตว์ได้ (ใช้ตอนเจ้าของเปิดดูเฉพาะ
  /// แชทของประกาศตัวนั้น) — ก๊อปพฤติกรรมเดิมจาก chatsForDogStream ที่กรองด้วย
  /// "ชื่อ" ไม่ใช่ petId ตรง ๆ เพราะ ChatInboxScreen ยังรับแค่พารามิเตอร์ dogName
  Future<List<Map<String, dynamic>>> myChats({String? petName}) async {
    final res = await _api.get(
      '/chats',
      query: petName == null ? null : {'petName': petName},
    ) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// หาห้องแชทเดิมของประกาศนี้ คืน null ถ้ายังไม่เคยคุยกัน
  ///
  /// หน้าที่มีปุ่ม "ทักแชท" (Discover / รายการที่สนใจ / รายละเอียดสัตว์) ไม่รู้ chatId
  /// จึงเปิด ChatScreen มาแบบ chatId = null — ถ้าไม่หาห้องเดิมให้ก่อน ผู้ใช้จะเห็น
  /// ห้องว่างทั้งที่เคยคุยกันไปแล้ว
  ///
  /// ต้องเทียบ otherUserId ด้วย ไม่ใช่แค่ petId เพราะเจ้าของประกาศตัวเดียวกัน
  /// มีห้องแชทกับผู้สนใจได้หลายคนพร้อมกัน
  Future<String?> findChatForPet({
    required String petId,
    required String otherUserId,
  }) async {
    for (final chat in await myChats()) {
      if (chat['petId'] == petId && chat['otherUserId'] == otherUserId) {
        return chat['id'] as String?;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> messages(String chatId) async {
    final res = await _api.get('/chats/$chatId/messages') as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> sendMessage(String chatId, String text) =>
      _api.post('/chats/$chatId/messages', body: {'text': text});

  Future<void> markRead(String chatId) => _api.post('/chats/$chatId/read');

  Future<int> _fetchUnreadCount() async {
    final res = await _api.get('/chats/unread-count') as Map<String, dynamic>;
    return res['count'] as int;
  }

  // ---------------------------------------------------------------------------
  // สด
  // ---------------------------------------------------------------------------

  /// ข้อความในห้อง — ประวัติจาก REST + ข้อความใหม่จาก event 'message'
  /// เก็บตาม id กันซ้ำ (ข้อความเดียวกันมาได้ทั้งจาก event และจากการดึงซ้ำตอนต่อใหม่)
  ///
  /// ข้อความของอีกฝ่ายที่เข้ามาระหว่างเปิดห้องอยู่ = อ่านแล้ว mark read ให้เลย
  /// อีกฝ่ายจะเห็น "อ่านแล้ว" และ badge ของเราไม่ขึ้น
  Stream<List<Map<String, dynamic>>> watchMessages(String chatId, {required String myUid}) {
    final byId = <String, Map<String, dynamic>>{};
    final subs = <StreamSubscription>[];
    late final StreamController<List<Map<String, dynamic>>> ctrl;

    void publish() {
      final list = byId.values.toList()
        ..sort((a, b) => '${a['createdAt']}'.compareTo('${b['createdAt']}'));
      if (!ctrl.isClosed) ctrl.add(list);
    }

    Future<void> load() async {
      try {
        for (final m in await messages(chatId)) {
          byId[m['id'] as String] = m;
        }
        publish();
      } catch (_) {
        // เน็ตหลุด — รอบต่อใหม่ของ socket จะดึงให้อีกครั้ง
      }
    }

    ctrl = StreamController(
      onListen: () {
        _socket.join(chatId);
        subs
          ..add(_socket.events
              .where((e) => e.name == 'message' && e.data['conversationId'] == chatId)
              .listen((e) {
            byId[e.data['id'] as String] = e.data;
            publish();
            if (e.data['senderId'] != myUid) markRead(chatId).catchError((_) {});
          }))
          ..add(_socket.onConnect.listen((_) => load()));
        load();
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
        _socket.leave(chatId);
      },
    );
    return ctrl.stream;
  }

  /// รายการห้อง — ดึงใหม่เมื่อมี 'notification' (ข้อความใหม่/อ่านแล้ว) หรือต่อใหม่
  Stream<List<Map<String, dynamic>>> watchChats({String? petName}) =>
      _refetchOnChange(() => myChats(petName: petName));

  int _lastUnreadCount = 0;
  Stream<int>? _sharedUnreadStream;

  /// badge จำนวนแชทที่ยังไม่ได้อ่าน (bottom nav / app bar)
  ///
  /// ⚠️ ต้องเป็น stream "ตัวเดียว" ที่ใช้ร่วมกันทั้งแอป เพราะหน้าจอที่เรียกอยู่
  /// (main_screen + profile_screen อีก 2 จุด) เรียกฟังก์ชันนี้ใน build() ซึ่งรันใหม่
  /// ทุกครั้งที่ setState — ถ้าสร้าง stream ใหม่ทุกครั้ง จะยิง REST ซ้ำทุก rebuild
  ///
  /// onCancel เป็น no-op เพื่อไม่ให้ source ถูกยกเลิกตอนคนฟังคนสุดท้ายหลุด
  /// (ไม่งั้นพอมีคนฟังใหม่ stream จะตายไปแล้วใช้ต่อไม่ได้)
  Stream<int> unreadChatCountStream() async* {
    yield _lastUnreadCount; // ค่าล่าสุดทันที ไม่ต้องรอ event ถัดไป
    yield* _sharedUnreadStream ??= _refetchOnChange(() async {
      return _lastUnreadCount = await _fetchUnreadCount();
    }).asBroadcastStream(onCancel: (_) {});
  }

  /// อีกฝ่ายกำลังพิมพ์ไหม (หน้าจอต้องตั้งเวลาดับเองเผื่อ event "หยุดพิมพ์" หาย)
  Stream<bool> otherTyping(String chatId, {required String myUid}) => _socket.events
      .where((e) =>
          e.name == 'typing' && e.data['conversationId'] == chatId && e.data['userId'] != myUid)
      .map((e) => e.data['isTyping'] == true);

  /// อีกฝ่ายอ่านข้อความในห้องถึงเวลาไหนแล้ว
  Stream<DateTime> otherReadAt(String chatId, {required String myUid}) => _socket.events
      .where((e) =>
          e.name == 'read' && e.data['conversationId'] == chatId && e.data['userId'] != myUid)
      .map((e) => DateTime.parse(e.data['readAt'] as String));

  void setTyping(String chatId, bool isTyping) => _socket.typing(chatId, isTyping);

  /// ดึง REST ครั้งแรกตอนมีคนฟัง แล้วดึงซ้ำเมื่อ server แจ้งว่ามีอะไรเปลี่ยน
  /// หรือ socket ต่อใหม่ — แทน polling loop เดิม
  Stream<T> _refetchOnChange<T>(Future<T> Function() fetch) {
    final subs = <StreamSubscription>[];
    late final StreamController<T> ctrl;

    Future<void> load() async {
      try {
        final value = await fetch();
        if (!ctrl.isClosed) ctrl.add(value);
      } catch (_) {}
    }

    ctrl = StreamController(
      onListen: () {
        _socket.connect();
        subs
          ..add(_socket.events.where((e) => e.name == 'notification').listen((_) => load()))
          ..add(_socket.onConnect.listen((_) => load()));
        load();
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );
    return ctrl.stream;
  }
}
