import 'dart:async';
import 'dart:math';

import '../shared/api_client.dart';
import '../shared/api_exception.dart';
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
  ///
  /// ข้อความแรกเป็นรูป/วิดีโอได้ — [media] คือค่าที่ได้จาก ChatMediaService.upload
  ///
  /// [clientId] = id ของข้อความนี้ที่แอปสร้างเอง ([newMessageClientId]) ส่งค่าเดิมทุกครั้งที่ลองใหม่
  /// — ถ้าคำขอก่อนหน้าบันทึกไปแล้วแต่คำตอบหาย server จะไม่บันทึกซ้ำ
  Future<String> createOrSend({
    required String petId,
    String message = '',
    Map<String, dynamic>? media,
    String? clientId,
  }) async {
    final res = await _api.post('/chats', body: {
      'petId': petId,
      if (message.isNotEmpty) 'message': message,
      if (media != null) 'media': media,
      if (clientId != null) 'clientId': clientId,
    }) as Map<String, dynamic>;
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
    try {
      // query เดียวบน unique index ฝั่ง server — ไม่ต้องโหลดกล่องข้อความทั้งก้อนมาวนหา
      final res = await _api.get('/chats/lookup', query: {
        'petId': petId,
        'otherUserId': otherUserId,
      }) as Map<String, dynamic>;
      return res['chatId'] as String?;
    } on ApiException catch (e) {
      // backend รุ่นก่อนยังไม่มี /chats/lookup (ไปตกที่ GET /chats/:id) — ถอยไปวิธีเดิม
      if (e.statusCode == 401) rethrow;
    }
    for (final chat in await myChats()) {
      if (chat['petId'] == petId && chat['otherUserId'] == otherUserId) {
        return chat['id'] as String?;
      }
    }
    return null;
  }

  /// จำนวนข้อความต่อหน้า (ตรงกับค่า default ฝั่ง backend)
  static const int pageSize = 50;

  /// ข้อความทีละหน้า เรียงเก่า -> ใหม่ ไม่ส่ง [before] = หน้าล่าสุด
  /// ได้น้อยกว่า [pageSize] แปลว่าไม่มีข้อความเก่ากว่านี้แล้ว
  Future<List<Map<String, dynamic>>> messages(String chatId, {String? before}) async {
    final res = await _api.get('/chats/$chatId/messages', query: {
      'limit': '$pageSize',
      if (before != null) 'before': before,
    }) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// หน้าล่าสุด + สถานะห้องในคำขอเดียว (ตอนเปิดห้อง) — room = null ถ้า backend รุ่นก่อน
  /// ไม่รู้จัก include=room แล้วตอบ array มาแบบเดิม หน้าจอต้องถาม [detail] เอง
  Future<({List<Map<String, dynamic>> messages, Map<String, dynamic>? room})> latestPage(
      String chatId) async {
    final res = await _api.get('/chats/$chatId/messages', query: {
      'limit': '$pageSize',
      'include': 'room',
    });
    if (res is List) return (messages: res.cast<Map<String, dynamic>>(), room: null);
    final body = res as Map<String, dynamic>;
    return (
      messages: (body['messages'] as List).cast<Map<String, dynamic>>(),
      room: body['room'] as Map<String, dynamic>?,
    );
  }

  /// สถานะห้อง: status ('active'|'closed'), closedReason, blockedByMe — ใช้เลือกว่าจะโชว์ช่องพิมพ์ไหม
  Future<Map<String, dynamic>> detail(String chatId) async =>
      await _api.get('/chats/$chatId') as Map<String, dynamic>;

  /// ลบแชท = ซ่อนเฉพาะฝั่งเรา อีกฝ่ายยังเห็น (ข้อความใหม่ทำให้ห้องกลับมา)
  Future<void> hideChat(String chatId) => _api.delete('/chats/$chatId');

  /// คืนข้อความที่บันทึกแล้วจาก server (มี id/createdAt/media URL จริง) ให้หน้าจอ
  /// ใส่ลง feed ได้ทันที ไม่ต้องรอ event จาก socket
  /// [clientId] ดู [createOrSend]
  Future<Map<String, dynamic>> sendMessage(
    String chatId, {
    String text = '',
    Map<String, dynamic>? media,
    String? clientId,
  }) async {
    final res = await _api.post('/chats/$chatId/messages', body: {
      if (text.isNotEmpty) 'text': text,
      if (media != null) 'media': media,
      if (clientId != null) 'clientId': clientId,
    }) as Map<String, dynamic>;
    return res['message'] as Map<String, dynamic>;
  }

  Future<void> markRead(String chatId) => _api.post('/chats/$chatId/read');

  Future<int> _fetchUnreadCount() async {
    final res = await _api.get('/chats/unread-count') as Map<String, dynamic>;
    return res['count'] as int;
  }

  // ---------------------------------------------------------------------------
  // สด
  // ---------------------------------------------------------------------------

  /// เปิดฟังข้อความของห้อง — ดู [MessageFeed]
  MessageFeed openMessages(String chatId, {required String myUid}) =>
      MessageFeed._(this, _socket, chatId, myUid);

  /// รายการห้อง — ดึงครั้งแรกและตอนต่อใหม่ ระหว่างนั้นแก้ตาม 'notification' ในเครื่องเอง
  /// (server แนบสถานะห้องมาให้แล้ว ดู [applyInboxNotification]) ดึงใหม่เฉพาะตอนแก้เองไม่ได้
  Stream<List<Map<String, dynamic>>> watchChats({String? petName}) {
    List<Map<String, dynamic>>? chats;
    return _refetchOnChange(
      () async => chats = await myChats(petName: petName),
      onNotification: (payload) {
        final current = chats;
        if (current == null) return null;
        final next = applyInboxNotification(current, payload, petName: petName);
        if (next != null) chats = next;
        return next;
      },
    );
  }

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
    yield* _sharedUnreadStream ??= _refetchOnChange(
      () async => _lastUnreadCount = await _fetchUnreadCount(),
      // server แนบยอดรวมมากับ 'notification' แล้ว ไม่ต้องยิง GET /chats/unread-count
      onNotification: (payload) {
        final total = payload['unreadTotal'];
        return total is int ? _lastUnreadCount = total : null;
      },
    ).asBroadcastStream(onCancel: (_) {});
  }

  /// อีกฝ่ายกำลังพิมพ์ไหม (หน้าจอต้องตั้งเวลาดับเองเผื่อ event "หยุดพิมพ์" หาย)
  Stream<bool> otherTyping(String chatId, {required String myUid}) => _socket.events
      .where((e) =>
          e.name == 'typing' && e.data['conversationId'] == chatId && e.data['userId'] != myUid)
      .map((e) => e.data['isTyping'] == true);

  void setTyping(String chatId, bool isTyping) => _socket.typing(chatId, isTyping);

  /// ดึง REST ครั้งแรกตอนมีคนฟัง และทุกครั้งที่ socket ต่อใหม่ (event ระหว่างหลุดหายไปแล้ว)
  /// ส่วน 'notification' ระหว่างต่ออยู่: ให้ [onNotification] คำนวณค่าใหม่จาก payload เอง
  /// ถ้าคืน null (ข้อมูลไม่พอ เช่น ห้องใหม่ที่ยังไม่อยู่ในรายการ) ค่อยดึง REST ใหม่
  Stream<T> _refetchOnChange<T>(
    Future<T> Function() fetch, {
    T? Function(Map<String, dynamic> payload)? onNotification,
  }) {
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
          ..add(_socket.events.where((e) => e.name == 'notification').listen((e) {
            final next = onNotification?.call(e.data);
            if (next == null) {
              load();
            } else if (!ctrl.isClosed) {
              ctrl.add(next);
            }
          }))
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

/// ข้อความในห้อง 1 ห้อง — หน้าล่าสุดจาก REST + ข้อความใหม่จาก event 'message'
/// + หน้าเก่ากว่าที่ผู้ใช้กดโหลดเพิ่ม ([loadOlder]) เก็บตาม id กันซ้ำ
/// (ข้อความเดียวกันมาได้ทั้งจาก event, จากผลของ POST และจากการดึงซ้ำตอนต่อใหม่)
///
/// ข้อความของอีกฝ่ายที่เข้ามาระหว่างเปิดห้องอยู่ = อ่านแล้ว mark read ให้เลย
/// อีกฝ่ายจะเห็น "อ่านแล้ว" และ badge ของเราไม่ขึ้น
///
/// สถานะอ่านอยู่ที่ `readAt` ของแต่ละข้อความ: ค่าเริ่มมาจาก REST (DB เก็บไว้ถาวร)
/// แล้ว event 'read' เติมลงข้อความของเราที่ส่งก่อนเวลานั้น — อยู่ใน list เดียวกับ
/// ข้อความ จึงไม่หายตอนหน้าจอ rebuild หรือออกแล้วเข้าห้องใหม่
class MessageFeed {
  MessageFeed._(this._chat, this._socket, this.chatId, this._myUid) {
    _ctrl = StreamController(onListen: _start, onCancel: _stop);
  }

  final ChatService _chat;
  final ChatSocket _socket;
  final String chatId;
  final String _myUid;

  final _byId = <String, Map<String, dynamic>>{};
  final _subs = <StreamSubscription>[];
  late final StreamController<List<Map<String, dynamic>>> _ctrl;

  bool _hasMore = false;
  bool _loadingOlder = false;

  /// สถานะห้องที่มากับหน้าล่าสุด (ทุกครั้งที่โหลด รวมตอนต่อใหม่) — null = backend รุ่นก่อน
  /// ไม่ได้ส่งมา หน้าจอต้องถาม ChatService.detail เอง
  void Function(Map<String, dynamic>? room)? onRoomStatus;

  Stream<List<Map<String, dynamic>>> get stream => _ctrl.stream;

  /// ยังมีข้อความเก่ากว่าที่โหลดอยู่ให้ดึงเพิ่ม
  bool get hasMore => _hasMore;
  bool get loadingOlder => _loadingOlder;

  /// ใส่ข้อความที่ได้จากผลของ POST ลง feed ทันที
  void upsert(Map<String, dynamic> message) {
    _byId[message['id'] as String] = message;
    _publish();
  }

  Future<void> loadOlder() async {
    if (!_hasMore || _loadingOlder || _byId.isEmpty) return;
    _loadingOlder = true;
    _publish();
    try {
      final page = await _chat.messages(chatId, before: _sorted().first['id'] as String);
      _hasMore = page.length >= ChatService.pageSize;
      for (final m in page) {
        _byId[m['id'] as String] = m;
      }
    } finally {
      _loadingOlder = false;
      _publish();
    }
  }

  List<Map<String, dynamic>> _sorted() => _byId.values.toList()
    ..sort((a, b) => '${a['createdAt']}'.compareTo('${b['createdAt']}'));

  void _publish() {
    if (!_ctrl.isClosed) _ctrl.add(_sorted());
  }

  /// ดึงหน้าล่าสุด (ครั้งแรก และทุกครั้งที่ socket ต่อใหม่)
  Future<void> _loadLatest() async {
    try {
      final latest = await _chat.latestPage(chatId);
      final page = latest.messages;
      onRoomStatus?.call(latest.room);
      // หลุดไปนานจนหน้าล่าสุดไม่ต่อกับของที่มีอยู่เลย = มีช่องโหว่ตรงกลาง
      // ทิ้งของเก่าแล้วเริ่มจากหน้าล่าสุดใหม่ ให้ loadOlder ไล่ย้อนต่อได้ถูก
      final connected = page.isEmpty || _byId.isEmpty || page.any((m) => _byId.containsKey(m['id']));
      if (!connected) _byId.clear();
      if (_byId.isEmpty) _hasMore = page.length >= ChatService.pageSize;
      for (final m in page) {
        _byId[m['id'] as String] = m;
      }
      _publish();
    } catch (e) {
      // ถ้ามีข้อความโชว์อยู่แล้ว เก็บของเดิมไว้ — รอบต่อใหม่ของ socket จะดึงให้อีกครั้ง
      // แต่ถ้ายังไม่เคยได้ข้อมูลเลย ต้องบอกหน้าจอ ไม่งั้นหมุนโหลดค้างตลอดไป
      if (_byId.isEmpty && !_ctrl.isClosed) _ctrl.addError(e);
    }
  }

  /// ลองดึงหน้าล่าสุดใหม่ (ปุ่ม "ลองใหม่" ตอนโหลดครั้งแรกไม่สำเร็จ)
  Future<void> reload() => _loadLatest();

  void _start() {
    _socket.join(chatId);
    _subs
      ..add(_socket.events
          .where((e) => e.name == 'message' && e.data['conversationId'] == chatId)
          .listen((e) {
        upsert(e.data);
        if (e.data['senderId'] != _myUid) _chat.markRead(chatId).catchError((_) {});
      }))
      ..add(_socket.events
          .where((e) =>
              e.name == 'read' && e.data['conversationId'] == chatId && e.data['userId'] != _myUid)
          .listen((e) {
        final readAt = DateTime.parse(e.data['readAt'] as String);
        for (final m in _byId.values) {
          final sentAt = DateTime.tryParse('${m['createdAt']}');
          if (m['senderId'] == _myUid &&
              m['readAt'] == null &&
              sentAt != null &&
              !sentAt.isAfter(readAt)) {
            m['readAt'] = e.data['readAt'];
          }
        }
        _publish();
      }))
      ..add(_socket.onConnect.listen((_) => _loadLatest()));
    _loadLatest();
  }

  void _stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _socket.leave(chatId);
  }
}

/// แก้รายการห้องในกล่องข้อความตาม 'notification' จาก server โดยไม่ต้องดึง GET /chats ใหม่
/// คืนรายการใหม่ (เรียงข้อความล่าสุดก่อน) หรือ null = แก้เองไม่ได้ ต้องดึงจาก server:
/// - server รุ่นก่อนไม่ได้แนบ room มา
/// - ห้องที่ยังไม่อยู่ในรายการ (ห้องใหม่ / ห้องที่ลบไปแล้วมีข้อความใหม่) — ไม่มีชื่อ/รูปคู่สนทนาให้วาด
///
/// [petName] = กล่องข้อความที่กรองเฉพาะประกาศเดียว ห้องของสัตว์ตัวอื่นไม่เกี่ยว คืนรายการเดิม
List<Map<String, dynamic>>? applyInboxNotification(
  List<Map<String, dynamic>> chats,
  Map<String, dynamic> payload, {
  String? petName,
}) {
  final id = payload['conversationId'];
  if (payload['type'] == 'hidden') {
    return [for (final c in chats) if (c['id'] != id) c];
  }
  final room = payload['room'];
  if (room is! Map) return null;
  if (petName != null && room['petName'] != petName) return chats;

  final i = chats.indexWhere((c) => c['id'] == id);
  if (i < 0) return null;
  final next = [...chats];
  next[i] = {
    ...chats[i],
    'lastMessage': room['lastMessage'],
    'lastMessageAt': room['lastMessageAt'],
    'unreadCount': room['unreadCount'],
    'status': room['status'],
    'closedReason': room['closedReason'],
  };
  DateTime at(Map<String, dynamic> c) =>
      DateTime.tryParse('${c['lastMessageAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0);
  next.sort((a, b) => at(b).compareTo(at(a)));
  return next;
}

final _random = Random.secure();

/// id ของข้อความที่แอปสร้างเองตอนกดส่ง (UUID v4) — ใช้ค่าเดิมทุกครั้งที่ส่งซ้ำ server จะได้รู้ว่า
/// เป็นข้อความเดิม (ไม่บันทึกซ้ำ) และใช้จับคู่ bubble "กำลังส่ง" กับข้อความจริงที่ server ตอบมา
String newMessageClientId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant RFC 4122
  final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
