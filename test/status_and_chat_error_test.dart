import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/chat/chat_screen.dart';
import 'package:petpaws/screens/upload/upload_screen.dart';
import 'package:petpaws/services/chat_socket.dart';
import 'package:petpaws/widgets/paw_loader.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _dog(String status) => {
      'id': 'p1',
      'name': 'หมู',
      'province': 'เชียงใหม่',
      'age': '1 ปี',
      'status': status,
      'imageUrl': '',
    };

Future<List<String>> _pumpUpload(WidgetTester tester, Map<String, dynamic> dog) async {
  final changes = <String>[];
  await http.runWithClient(() async {
    await tester.pumpWidget(MaterialApp(
      home: UploadScreen(
        onAddDog: (_) {},
        myPostedDogs: [dog],
        onDeleteDog: (_) {},
        onChangeStatus: (d, s) => changes.add(s),
        onEditDog: (_) {},
        likedDogs: const [],
        onToggleFavorite: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
  }, () => MockClient((_) async => _json({'province': 'เชียงใหม่'})));
  return changes;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('สถานะประกาศ', () {
    testWidgets('ตัวเลือกเหลือ 2 อัน ไม่มี "ยกเลิกประกาศ"', (tester) async {
      await _pumpUpload(tester, _dog('ยังไม่ถูกรับเลี้ยง'));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('status-p1')), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const ValueKey('status-p1')));
      await tester.pumpAndSettle();
      expect(find.text('ถูกรับเลี้ยงแล้ว'), findsWidgets);
      expect(find.text('ยกเลิกประกาศ'), findsNothing);
    });

    Future<void> chooseAdopted(WidgetTester tester) async {
      await tester.scrollUntilVisible(find.byKey(const ValueKey('status-p1')), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const ValueKey('status-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ถูกรับเลี้ยงแล้ว').last);
      await tester.pumpAndSettle();
    }

    testWidgets('เลือก "ถูกรับเลี้ยงแล้ว" → ขึ้นป๊อปอัป ยังไม่เปลี่ยนจนกว่าจะกดยืนยัน', (tester) async {
      final changes = await _pumpUpload(tester, _dog('ยังไม่ถูกรับเลี้ยง'));
      await chooseAdopted(tester);
      expect(find.text('ยืนยันการเปลี่ยนสถานะ'), findsOneWidget);
      expect(changes, isEmpty, reason: 'ยังไม่ยืนยัน ห้ามเปลี่ยน');

      await tester.tap(find.byKey(const ValueKey('status-confirm')));
      await tester.pumpAndSettle();
      expect(changes, ['ถูกรับเลี้ยงแล้ว']);
    });

    testWidgets('กดยกเลิกในป๊อปอัป → ไม่เปลี่ยนสถานะ', (tester) async {
      final changes = await _pumpUpload(tester, _dog('ยังไม่ถูกรับเลี้ยง'));
      await chooseAdopted(tester);
      await tester.tap(find.byKey(const ValueKey('status-cancel')));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
    });

    testWidgets('ประกาศเก่าที่เป็น "ยกเลิกประกาศ" ยังแสดงได้ ไม่ล้ม', (tester) async {
      await _pumpUpload(tester, _dog('ยกเลิกประกาศ'));
      await tester.scrollUntilVisible(find.byKey(const ValueKey('status-p1')), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('ยกเลิกประกาศ'), findsOneWidget);
    });
  });

  testWidgets('แชท: โหลดข้อความไม่สำเร็จ → แสดงข้อผิดพลาด + ลองใหม่ได้ (ไม่หมุนค้าง)', (tester) async {
    var healthy = false;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(
        home: ChatScreen(chatId: 'c1', petId: 'p1', dogName: 'หมู', otherUserName: 'สมชาย', otherUserId: 'o'),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-load-error')), findsOneWidget);
      expect(find.byType(PawLoader), findsNothing);

      healthy = true;
      await tester.tap(find.byKey(const ValueKey('chat-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-load-error')), findsNothing);
      expect(find.text('สวัสดี'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      ChatSocket.instance.disconnect();
    }, () => MockClient((req) async {
          final path = req.url.path;
          if (path == '/chats/c1/messages') {
            return healthy
                ? _json([
                    {'id': 'm1', 'senderId': 'o', 'text': 'สวัสดี', 'kind': 'user', 'createdAt': '2026-10-01T10:00:00.000Z'}
                  ])
                : _json({'error': {'code': 'X', 'message': 'พัง'}}, 500);
          }
          if (path == '/chats/c1') return _json({'status': 'active', 'closedReason': null, 'blockedByMe': false});
          return _json({'success': true});
        }));
  });
}
