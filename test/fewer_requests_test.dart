import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/chat/chat_screen.dart';
import 'package:petpaws/services/chat_service.dart';
import 'package:petpaws/services/chat_socket.dart';
import 'package:petpaws/shared/app_user.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _chat(String id, String at, {String pet = 'หมู', int unread = 0}) => {
      'id': id,
      'petName': pet,
      'otherUserName': 'สมชาย',
      'lastMessage': 'เดิม',
      'lastMessageAt': at,
      'unreadCount': unread,
      'status': 'active',
      'closedReason': null,
    };

Map<String, dynamic> _room({String pet = 'หมู', int unread = 1, String at = '2026-10-06T12:00:00.000Z'}) => {
      'lastMessage': '📷 รูปภาพ',
      'lastMessageAt': at,
      'unreadCount': unread,
      'status': 'active',
      'closedReason': null,
      'petName': pet,
    };

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => ChatSocket.instance.disconnect());

  group('applyInboxNotification — แก้กล่องข้อความจาก notification โดยไม่ดึง GET /chats ใหม่', () {
    final chats = [
      _chat('a', '2026-10-06T10:00:00.000Z'),
      _chat('b', '2026-10-06T09:00:00.000Z'),
    ];

    test('ข้อความใหม่: อัปเดตห้องนั้น และย้ายขึ้นบนสุด', () {
      final next = applyInboxNotification(chats, {
        'type': 'message',
        'conversationId': 'b',
        'room': _room(unread: 2),
      })!;

      expect(next.map((c) => c['id']), ['b', 'a']);
      expect(next.first, containsPair('lastMessage', '📷 รูปภาพ'));
      expect(next.first, containsPair('unreadCount', 2));
      // ไม่แก้ list เดิมในที่ (StreamBuilder ต้องเห็นเป็นค่าใหม่)
      expect(chats.last['unreadCount'], 0);
    });

    test('อ่านแล้ว: ยังไม่อ่านเป็น 0 ลำดับไม่เปลี่ยน', () {
      final next = applyInboxNotification(
          [_chat('a', '2026-10-06T10:00:00.000Z', unread: 3)],
          {'type': 'read', 'conversationId': 'a', 'room': _room(unread: 0, at: '2026-10-06T10:00:00.000Z')})!;

      expect(next.single['unreadCount'], 0);
    });

    test('ลบห้อง: เอาออกจากรายการ', () {
      final next = applyInboxNotification(chats, {'type': 'hidden', 'conversationId': 'a'})!;
      expect(next.map((c) => c['id']), ['b']);
    });

    test('ห้องที่ยังไม่อยู่ในรายการ (ห้องใหม่) = null ให้ดึงใหม่ เพราะไม่มีชื่อ/รูปคู่สนทนา', () {
      expect(applyInboxNotification(chats, {'type': 'message', 'conversationId': 'new', 'room': _room()}), isNull);
    });

    test('server รุ่นก่อนไม่แนบ room = null ให้ดึงใหม่แบบเดิม', () {
      expect(applyInboxNotification(chats, {'type': 'message', 'conversationId': 'a'}), isNull);
    });

    test('กล่องข้อความที่กรองเฉพาะสัตว์ตัวหนึ่ง: ห้องของตัวอื่นไม่เกี่ยว ไม่ต้องดึงใหม่', () {
      final next = applyInboxNotification(chats, {'type': 'message', 'conversationId': 'x', 'room': _room(pet: 'แมว')},
          petName: 'หมู');
      expect(next, same(chats));
    });
  });

  group('หาห้องแชทเดิม (ปุ่ม "ทักแชท")', () {
    test('ใช้ GET /chats/lookup คำขอเดียว ไม่โหลดกล่องข้อความทั้งก้อน', () async {
      final calls = <String>[];
      await http.runWithClient(() async {
        final id = await ChatService.instance.findChatForPet(petId: 'p1', otherUserId: 'o1');
        expect(id, 'c9');
      }, () => MockClient((req) async {
            calls.add('${req.url.path}?${req.url.query}');
            return _json({'chatId': 'c9'});
          }));

      expect(calls, ['/chats/lookup?petId=p1&otherUserId=o1']);
    });

    test('backend รุ่นก่อนไม่มี /chats/lookup ถอยไปหาจากรายการห้องแบบเดิม', () async {
      await http.runWithClient(() async {
        final id = await ChatService.instance.findChatForPet(petId: 'p1', otherUserId: 'o1');
        expect(id, 'c2');
      }, () => MockClient((req) async {
            if (req.url.path == '/chats/lookup') {
              return _json({'error': {'code': 'INTERNAL', 'message': 'x'}}, 500);
            }
            return _json([
              {'id': 'c1', 'petId': 'p1', 'otherUserId': 'someone-else'},
              {'id': 'c2', 'petId': 'p1', 'otherUserId': 'o1'},
            ]);
          }));
    });
  });

  group('เปิดห้องแชท', () {
    final msgs = [
      {'id': 'm1', 'senderId': 'other', 'text': 'ยังอยู่ไหมครับ', 'kind': 'user', 'createdAt': '2026-10-01T10:00:00.000Z'},
      {'id': 's1', 'senderId': 'me', 'text': 'มีคนรับเลี้ยงสัตว์ตัวนี้แล้ว', 'kind': 'system', 'createdAt': '2026-10-01T10:05:00.000Z'},
    ];

    testWidgets('สถานะห้องมากับหน้าแรกของข้อความ — ไม่ยิง GET /chats/:id แยก', (tester) async {
      final calls = <String>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(
          home: ChatScreen(
              chatId: 'c1', petId: 'p1', dogName: 'หมู', otherUserName: 'สมชาย', otherUserAvatar: '', otherUserId: 'o'),
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('chat-closed')), findsOneWidget);
        expect(calls, contains('GET /chats/c1/messages?limit=50&include=room'));
        expect(calls, isNot(contains('GET /chats/c1')));
        // ส่ง otherUserAvatar มาแล้ว (แม้เป็นค่าว่าง) = ไม่ต้องดึงโปรไฟล์คู่สนทนา
        expect(calls.where((c) => c.startsWith('GET /users/')), isEmpty);

        // ปิดจอแล้วตัด WebSocket ก่อนจบเทสต์ — socket เปิด timer ค้างไว้
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 300));
        ChatSocket.instance.disconnect();
      }, () => MockClient((req) async {
            calls.add('${req.method} ${req.url.path}${req.url.query.isEmpty ? '' : '?${req.url.query}'}');
            if (req.url.path == '/chats/c1/messages') {
              return _json({
                'messages': msgs,
                'room': {'id': 'c1', 'status': 'closed', 'closedReason': 'pet_adopted', 'blockedByMe': false},
              });
            }
            return _json({'success': true});
          }));
    });
  });

  group('AppUser.province', () {
    test('ผลล็อกอินจาก backend ใหม่: รู้จังหวัด ("" = ไม่ได้ตั้ง)', () {
      final base = {'id': 'u', 'username': 'u', 'email': 'u@x.com'};
      expect(AppUser.fromJson({...base, 'province': 'เชียงใหม่'}).province, 'เชียงใหม่');
      expect(AppUser.fromJson({...base, 'province': null}).province, '');
    });

    test('backend รุ่นก่อนไม่ส่งมา = null (หน้าลงประกาศจะถามเซิร์ฟเวอร์เอง)', () {
      expect(AppUser.fromJson({'id': 'u', 'username': 'u', 'email': 'u@x.com'}).province, isNull);
    });
  });
}
