import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/chat/chat_screen.dart';
import 'package:petpaws/services/chat_service.dart';
import 'package:petpaws/services/chat_socket.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

/// ห้อง c1 ที่ยังไม่มีข้อความ — POST ข้อความแต่ละครั้งรอ [respond] ตัดสินว่าจะตอบเมื่อไหร่/อย่างไร
class _FakeServer {
  final sent = <Map<String, dynamic>>[];
  final pending = <Completer<http.Response>>[];

  /// ตอบคำขอส่งข้อความที่ค้างอยู่ตัวแรก: สำเร็จ (คืนข้อความจริง) หรือ error ตาม [status]
  void respondNext({int status = 200}) {
    final i = sent.length - pending.length;
    final body = sent[i];
    final c = pending.removeAt(0);
    c.complete(status == 200
        ? _json({
            'success': true,
            'message': {
              'id': 'srv-$i',
              'senderId': 'me',
              'text': body['text'],
              'kind': 'user',
              'clientId': body['clientId'],
              'createdAt': '2026-10-07T10:00:0$i.000Z',
            },
          })
        : _json({'error': {'code': 'INTERNAL', 'message': 'เซิร์ฟเวอร์มีปัญหา'}}, status));
  }

  Future<http.Response> handle(http.Request req) {
    final path = req.url.path;
    if (path == '/chats/c1/messages' && req.method == 'POST') {
      sent.add(jsonDecode(req.body) as Map<String, dynamic>);
      final c = Completer<http.Response>();
      pending.add(c);
      return c.future;
    }
    if (path == '/chats/c1/messages') return Future.value(_json([]));
    if (path == '/chats/c1') {
      return Future.value(_json({'status': 'active', 'closedReason': null, 'blockedByMe': false}));
    }
    return Future.value(_json({'success': true}));
  }
}

Future<void> _pumpChat(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(
    home: ChatScreen(
        chatId: 'c1', petId: 'p1', dogName: 'หมู', otherUserName: 'สมชาย', otherUserAvatar: '', otherUserId: 'o'),
  ));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byKey(const ValueKey('chat-send')));
  await tester.pump();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 300));
  ChatSocket.instance.disconnect();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => ChatSocket.instance.disconnect());

  testWidgets('เซิร์ฟเวอร์ตอบช้า: ข้อความขึ้นทันที ช่องพิมพ์ไม่ล็อก ส่งต่อได้ และส่งทีละข้อความตามลำดับ',
      (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpChat(tester);

      await _type(tester, 'หนึ่ง');
      // ยังไม่ได้คำตอบ แต่ข้อความขึ้นแล้วพร้อมสถานะ "กำลังส่ง" และช่องพิมพ์ว่างให้พิมพ์ต่อ
      expect(find.text('หนึ่ง'), findsOneWidget);
      expect(find.byKey(const ValueKey('pending-sending')), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);

      await _type(tester, 'สอง');
      await _type(tester, 'สาม');
      expect(find.byKey(const ValueKey('pending-sending')), findsNWidgets(3));
      // ส่งทีละข้อความ: ข้อความที่สองยังไม่ถูกยิงจนกว่าข้อความแรกจะได้คำตอบ
      expect(server.sent.map((b) => b['text']), ['หนึ่ง']);

      server.respondNext();
      await tester.pumpAndSettle();
      expect(server.sent.map((b) => b['text']), ['หนึ่ง', 'สอง']);

      server.respondNext();
      await tester.pumpAndSettle();
      server.respondNext();
      await tester.pumpAndSettle();

      expect(server.sent.map((b) => b['text']), ['หนึ่ง', 'สอง', 'สาม']);
      expect(find.byKey(const ValueKey('pending-sending')), findsNothing);
      expect(find.text('สาม'), findsOneWidget);
      // ทุกข้อความมี clientId ไม่ซ้ำกัน
      expect(server.sent.map((b) => b['clientId']).toSet(), hasLength(3));
      await _finish(tester);
    }, () => MockClient(server.handle));
  });

  testWidgets('ส่งไม่สำเร็จ: ข้อความที่รอต่อถูกพักด้วย แตะลองใหม่ส่งตามลำดับเดิมด้วย clientId เดิม',
      (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpChat(tester);
      await _type(tester, 'หนึ่ง');
      await _type(tester, 'สอง');

      server.respondNext(status: 500);
      await tester.pumpAndSettle();
      // ไม่ยิงข้อความที่สองต่อทั้งที่ข้อความแรกยังค้าง (ลำดับจะสลับ) — พักไว้ทั้งคู่
      expect(server.sent, hasLength(1));
      expect(find.text('ส่งไม่สำเร็จ แตะเพื่อลองใหม่'), findsNWidgets(2));
      final firstClientId = server.sent.single['clientId'];

      await tester.tap(find.text('หนึ่ง'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลองส่งอีกครั้ง'));
      await tester.pumpAndSettle();
      server.respondNext();
      await tester.pumpAndSettle();
      server.respondNext();
      await tester.pumpAndSettle();

      expect(server.sent.map((b) => b['text']), ['หนึ่ง', 'หนึ่ง', 'สอง']);
      // ลองใหม่ใช้ clientId เดิม — ถ้าครั้งแรกบันทึกไปแล้วจริง server จะไม่บันทึกซ้ำ
      expect(server.sent[1]['clientId'], firstClientId);
      expect(find.text('ส่งไม่สำเร็จ แตะเพื่อลองใหม่'), findsNothing);
      await _finish(tester);
    }, () => MockClient(server.handle));
  });

  test('newMessageClientId เป็น UUID v4 ที่ server รับได้ และไม่ซ้ำกัน', () {
    final ids = {for (var i = 0; i < 1000; i++) newMessageClientId()};
    expect(ids, hasLength(1000));
    for (final id in ids.take(20)) {
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    }
  });
}
