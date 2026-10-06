import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/chat/chat_inbox_screen.dart';
import 'package:petpaws/screens/chat/chat_screen.dart';
import 'package:petpaws/screens/favorites/favorites_screen.dart';
import 'package:petpaws/services/chat_socket.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _dog(String id, String name) =>
    {'id': id, 'name': name, 'province': 'เชียงใหม่', 'breed': 'พันทาง', 'imageUrl': ''};

/// ปิดหน้าจอแล้วตัด WebSocket ก่อนจบเทสต์ — socket เปิด timer ค้างซึ่งทำให้เทสต์ล้มถ้าทิ้งไว้
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 300)); // timer เลื่อนลงล่างสุดของห้องแชทยังค้างอยู่
  ChatSocket.instance.disconnect();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => ChatSocket.instance.disconnect());

  group('รายการที่สนใจ', () {
    testWidgets('โหมดเลือก: เลือกหลายตัว → เลิกถูกใจ เรียก onToggleFavorite ตามที่เลือกเท่านั้น', (tester) async {
      final dogs = [_dog('a', 'หมู'), _dog('b', 'บีม'), _dog('c', 'มะม่วง')];
      final toggled = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: FavoritesScreen(likedDogs: dogs, onToggleFavorite: (d) => toggled.add(d['id'] as String)),
      ));

      expect(find.byKey(const ValueKey('fav-unlike')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('fav-select')));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(find.byKey(const ValueKey('fav-unlike'))).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('fav-check-a')));
      await tester.tap(find.byKey(const ValueKey('fav-check-c')));
      await tester.pumpAndSettle();
      expect(find.text('เลือกแล้ว 2 ตัว'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('fav-unlike')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'เลิกถูกใจ'));
      await tester.pumpAndSettle();

      expect(toggled, ['a', 'c']);
      expect(find.byKey(const ValueKey('fav-unlike')), findsNothing, reason: 'ออกจากโหมดเลือกแล้ว');
    });

    testWidgets('เลือกทั้งหมด / ยกเลิกโหมดเลือก', (tester) async {
      final dogs = [_dog('a', 'หมู'), _dog('b', 'บีม')];
      await tester.pumpWidget(MaterialApp(
        home: FavoritesScreen(likedDogs: dogs, onToggleFavorite: (_) {}),
      ));
      await tester.tap(find.byKey(const ValueKey('fav-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fav-select-all')));
      await tester.pumpAndSettle();
      expect(find.text('เลือกแล้ว 2 ตัว'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fav-cancel-select')));
      await tester.pumpAndSettle();
      expect(find.text('รายการที่สนใจ'), findsOneWidget);
    });
  });

  group('กล่องข้อความ', () {
    final chats = [
      {
        'id': 'c1',
        'petId': 'p1',
        'petName': 'หมู',
        'petImageUrl': '',
        'otherUserId': 'u1',
        'otherUserName': 'สมชาย',
        'lastMessage': 'ยังอยู่ไหมครับ',
        'lastMessageAt': '2026-10-01T10:00:00.000Z',
        'unreadCount': 0,
      },
      {
        'id': 'c2',
        'petId': 'p2',
        'petName': 'บีม',
        'petImageUrl': '',
        'otherUserId': 'u2',
        'otherUserName': 'สมหญิง',
        'lastMessage': 'ขอบคุณค่ะ',
        'lastMessageAt': '2026-10-01T11:00:00.000Z',
        'unreadCount': 0,
      },
    ];

    testWidgets('ค้นหาแชทตามชื่อ/สัตว์/ข้อความ และแจ้งเมื่อไม่พบ', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: ChatInboxScreen()));
        await tester.pumpAndSettle();
        expect(find.text('สมชาย'), findsOneWidget);
        expect(find.text('สมหญิง'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('inbox-search-toggle')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('inbox-search')), 'ขอบคุณ');
        await tester.pumpAndSettle();
        expect(find.text('สมชาย'), findsNothing);
        expect(find.text('สมหญิง'), findsOneWidget);

        await tester.enterText(find.byKey(const ValueKey('inbox-search')), 'ไม่มีแน่นอน');
        await tester.pumpAndSettle();
        expect(find.text('ไม่พบแชทที่ค้นหา'), findsOneWidget);
        await _finish(tester);
      }, () => MockClient((req) async => _json(chats)));
    });

    testWidgets('โหมดเลือก: ติ๊กแชท → ลบแชท → ยืนยัน → เรียก DELETE /chats/:id', (tester) async {
      final calls = <String>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: ChatInboxScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('inbox-select')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('inbox-check-c1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('inbox-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'ลบ'));
        await tester.pumpAndSettle();
        expect(calls, contains('DELETE /chats/c1'));
        await _finish(tester);
      }, () => MockClient((req) async {
            calls.add('${req.method} ${req.url.path}');
            return req.method == 'DELETE' ? _json({'success': true}) : _json(chats);
          }));
    });
  });

  group('ห้องแชท', () {
    http.Response handle(http.Request req, {required Map<String, dynamic> detail, required List<Map<String, dynamic>> msgs, List<String>? calls}) {
      calls?.add('${req.method} ${req.url.path}');
      final path = req.url.path;
      if (path == '/chats/c1/messages') return _json(msgs);
      if (path == '/chats/c1' && req.method == 'GET') return _json(detail);
      if (path == '/chats/c1/read') return _json({'success': true});
      return _json({'success': true});
    }

    final base = [
      {'id': 'm1', 'senderId': 'other', 'text': 'ยังอยู่ไหมครับ', 'kind': 'user', 'createdAt': '2026-10-01T10:00:00.000Z'},
      {'id': 's1', 'senderId': 'me', 'text': 'มีคนรับเลี้ยงสัตว์ตัวนี้แล้ว', 'kind': 'system', 'createdAt': '2026-10-01T10:05:00.000Z'},
    ];

    Future<void> pumpChat(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: ChatScreen(chatId: 'c1', petId: 'p1', dogName: 'หมู', otherUserName: 'สมชาย', otherUserId: 'other'),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('ข้อความระบบอยู่กลางจอ และห้องที่ปิดแล้วแทนช่องพิมพ์ด้วยคำอธิบาย', (tester) async {
      await http.runWithClient(() async {
        await pumpChat(tester);
        expect(find.byKey(const ValueKey('system-s1')), findsOneWidget);
        expect(find.text('มีคนรับเลี้ยงสัตว์ตัวนี้แล้ว'), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-closed')), findsOneWidget);
        expect(find.text('สัตว์ตัวนี้มีบ้านแล้ว ห้องแชทนี้ถูกปิด'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        await _finish(tester);
      }, () => MockClient((req) async => handle(req,
          detail: {'status': 'closed', 'closedReason': 'pet_adopted', 'blockedByMe': false}, msgs: base)));
    });

    testWidgets('ห้องที่ยัง active มีช่องพิมพ์ และข้อความระบบรายงานไม่ได้ (ไม่มีเมนูกดค้าง)', (tester) async {
      await http.runWithClient(() async {
        await pumpChat(tester);
        expect(find.byKey(const ValueKey('chat-closed')), findsNothing);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.byKey(const ValueKey('msg-m1')), findsOneWidget);
        expect(find.byKey(const ValueKey('msg-s1')), findsNothing);
        await _finish(tester);
      }, () => MockClient((req) async => handle(req,
          detail: {'status': 'active', 'closedReason': null, 'blockedByMe': false}, msgs: base)));
    });

    testWidgets('บล็อก: เรียก POST /blocks แล้วดึงสถานะใหม่ (ห้องปิด + ปุ่มปลดบล็อก)', (tester) async {
      final calls = <String>[];
      var blocked = false;
      await http.runWithClient(() async {
        await pumpChat(tester);
        await tester.tap(find.byKey(const ValueKey('chat-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('บล็อก'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'บล็อก'));
        await tester.pumpAndSettle();

        expect(calls, contains('POST /blocks'));
        expect(find.text('คุณบล็อกผู้ใช้นี้อยู่ ปลดบล็อกเพื่อคุยต่อ'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'ปลดบล็อก'), findsOneWidget);
        await _finish(tester);
      }, () => MockClient((req) async {
            if (req.method == 'POST' && req.url.path == '/blocks') blocked = true;
            return handle(req,
                calls: calls,
                detail: blocked
                    ? {'status': 'closed', 'closedReason': 'blocked', 'blockedByMe': true}
                    : {'status': 'active', 'closedReason': null, 'blockedByMe': false},
                msgs: base);
          }));
    });

    testWidgets('ลบแชทในห้อง → DELETE แล้วกลับหน้าก่อน', (tester) async {
      final calls = <String>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ChatScreen(
                      chatId: 'c1', petId: 'p1', dogName: 'หมู', otherUserName: 'สมชาย', otherUserId: 'other'),
                ),
              ),
              child: const Text('เข้าห้อง'),
            ),
          ),
        ));
        await tester.tap(find.text('เข้าห้อง'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ลบแชท'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'ลบ'));
        await tester.pumpAndSettle();
        expect(calls, contains('DELETE /chats/c1'));
        expect(find.text('เข้าห้อง'), findsOneWidget);
        await _finish(tester);
      }, () => MockClient((req) async => handle(req,
          calls: calls, detail: {'status': 'active', 'closedReason': null, 'blockedByMe': false}, msgs: base)));
    });

    testWidgets('ค้นหาข้อความในห้อง กรองเฉพาะที่ตรง', (tester) async {
      await http.runWithClient(() async {
        await pumpChat(tester);
        await tester.tap(find.byKey(const ValueKey('chat-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('ค้นหาข้อความ'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('chat-search')), 'ยังอยู่');
        await tester.pumpAndSettle();
        expect(find.text('ยังอยู่ไหมครับ'), findsOneWidget);
        expect(find.byKey(const ValueKey('system-s1')), findsNothing);
        await _finish(tester);
      }, () => MockClient((req) async => handle(req,
          detail: {'status': 'active', 'closedReason': null, 'blockedByMe': false}, msgs: base)));
    });
  });
}
