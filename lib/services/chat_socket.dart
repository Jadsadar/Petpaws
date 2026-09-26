import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../shared/api_client.dart';
import '../shared/token_storage.dart';

class ChatEvent {
  const ChatEvent(this.name, this.data);
  final String name;
  final Map<String, dynamic> data;
}

/// การเชื่อมต่อ WebSocket ของแชท (namespace /chat ฝั่ง backend) มีตัวเดียวทั้งแอป
///
/// - ส่ง access token ตัวเดียวกับ REST ทุกครั้งที่ต่อ/ต่อใหม่ (setAuthFn อ่านจาก
///   storage สดทุกรอบ เลยได้ token ล่าสุดที่ REST refresh ไว้แล้วเสมอ)
/// - เน็ตหลุด: socket.io ต่อใหม่ให้เอง
/// - server ตอบ 'unauthorized' (token หมดอายุ): socket.io จะ "ไม่" ต่อใหม่เอง —
///   refresh token แล้วต่อใหม่ 1 ครั้ง ถ้ายังไม่ผ่านถือว่า session หมด
/// - ต่อใหม่สำเร็จ: join ห้องที่เปิดอยู่ให้ใหม่ (server ลืมห้องตอนหลุด) แล้วแจ้ง
///   [onConnect] ให้หน้าจอดึงข้อมูลที่พลาดไประหว่างหลุดกลับมา
class ChatSocket {
  ChatSocket._();
  static final ChatSocket instance = ChatSocket._();

  static const _unauthorized = 'unauthorized';
  static const _serverEvents = ['message', 'read', 'typing', 'notification'];

  io.Socket? _socket;
  final Set<String> _rooms = {};
  bool _authRetried = false;

  // เป็นของ ChatSocket ไม่ใช่ของ io.Socket — คนที่ฟังอยู่ไม่ต้องสมัครใหม่
  // ตอน logout แล้ว login กลับ (socket ตัวใหม่ แต่ stream เดิม)
  final _events = StreamController<ChatEvent>.broadcast();
  final _connects = StreamController<void>.broadcast();

  Stream<ChatEvent> get events => _events.stream;
  Stream<void> get onConnect => _connects.stream;

  /// เรียกซ้ำได้ ต่อแค่ครั้งแรก
  void connect() {
    if (_socket != null) return;
    final socket = io.io(
      '${ApiClient.baseUrl}/chat',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          // ไม่ใช้ manager เดิมที่ cache ไว้ตาม URL — หลัง logout ต้องได้การเชื่อมต่อใหม่จริง
          .enableForceNew()
          .setAuthFn((send) async =>
              send({'token': await TokenStorage.instance.readAccessToken() ?? ''}))
          .build(),
    );

    socket.onConnect((_) {
      _authRetried = false;
      for (final room in _rooms) {
        socket.emit('join', {'conversationId': room});
      }
      _connects.add(null);
    });
    socket.onConnectError(_handleConnectError);
    for (final name in _serverEvents) {
      socket.on(name, (data) {
        if (data is Map) _events.add(ChatEvent(name, Map<String, dynamic>.from(data)));
      });
    }

    _socket = socket..connect();
  }

  Future<void> _handleConnectError(dynamic err) async {
    final message = err is Map ? err['message'] : err?.toString();
    if (message != _unauthorized || _authRetried) return;
    _authRetried = true;
    if (await ApiClient.instance.refreshSession()) _socket?.connect();
  }

  /// logout / session หมด — ปิดจริง ไม่ต่อใหม่
  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _rooms.clear();
    _authRetried = false;
  }

  void join(String conversationId) {
    connect();
    if (_rooms.add(conversationId) && (_socket?.connected ?? false)) {
      _socket!.emit('join', {'conversationId': conversationId});
    }
  }

  void leave(String conversationId) {
    if (_rooms.remove(conversationId)) {
      _socket?.emit('leave', {'conversationId': conversationId});
    }
  }

  void typing(String conversationId, bool isTyping) {
    if (_socket?.connected ?? false) {
      _socket!.emit('typing', {'conversationId': conversationId, 'isTyping': isTyping});
    }
  }
}
