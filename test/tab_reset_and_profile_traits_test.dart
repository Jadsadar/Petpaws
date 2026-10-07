import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/main_screen.dart';
import 'package:petpaws/screens/profile/profile_screen.dart';
import 'package:petpaws/services/chat_socket.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _me(List<String> traits) => {
      'id': 'me',
      'username': 'me',
      'email': 'me@petpaws.app',
      'displayName': 'แพรว',
      'profileImageUrl': '',
      'province': 'สงขลา',
      'phone': '',
      'lineId': '',
      'fbLink': '',
      'homeType': 'บ้านเดี่ยว',
      'traits': traits,
      'profileCompleted': true,
    };

Finder _petNameField() => find.widgetWithText(TextField, 'ชื่อสัตว์เลี้ยง *');

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('สลับแท็บแล้วกลับมา → หน้าเดิมเริ่มใหม่ ไม่ค้างสิ่งที่กรอกไว้',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: MainScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ลงประกาศ'));
      await tester.pumpAndSettle();
      await tester.enterText(_petNameField(), 'ข้าวตัง');
      expect(find.text('ข้าวตัง'), findsOneWidget);

      await tester.tap(find.text('โปรไฟล์'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลงประกาศ'));
      await tester.pumpAndSettle();

      expect(find.text('ข้าวตัง'), findsNothing,
          reason: 'ฟอร์มต้องว่างเหมือนเพิ่งเปิด');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      ChatSocket.instance.disconnect();
    },
        () => MockClient((req) async {
              final p = req.url.path;
              if (p == '/pets/deck') {
                return _json(
                    {'dogs': [], 'nextCursor': null, 'hasMore': false});
              }
              if (p == '/chats/unread-count') return _json({'count': 0});
              if (p == '/users/me') return _json(_me(['chill']));
              return _json([]);
            }));
  });

  group('โปรไฟล์: ต้องเหลือแท็กนิสัยอย่างน้อย 1 แท็ก', () {
    Future<List<String>> run(WidgetTester tester, List<String> traits,
        Future<void> Function() body) async {
      final sent = <String>[];
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('แก้ไขข้อมูล'));
        await tester.pumpAndSettle();
        await body();
      },
          () => MockClient((req) async {
                if (req.method == 'PATCH' || req.method == 'PUT') {
                  sent.add(req.body);
                  return _json(_me(traits));
                }
                return _json(_me(traits));
              }));
      return sent;
    }

    testWidgets('เอาแท็กสุดท้ายออกไม่ได้ และขึ้นข้อความเตือน', (tester) async {
      await run(tester, ['chill'], () async {
        await tester.tap(find.byKey(const ValueKey('tag-chill')));
        await tester.pumpAndSettle();
        final chip =
            tester.widget<ChoiceChip>(find.byKey(const ValueKey('tag-chill')));
        expect(chip.selected, isTrue, reason: 'แท็กสุดท้ายต้องยังถูกเลือกอยู่');
        expect(find.textContaining('อย่างน้อย 1 แท็ก'), findsOneWidget);

        // เลือกแท็กอื่นเพิ่มแล้ว จึงเอาแท็กเดิมออกได้
        await tester.tap(find.byKey(const ValueKey('tag-foodie')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('tag-chill')));
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<ChoiceChip>(find.byKey(const ValueKey('tag-chill')))
                .selected,
            isFalse);
        expect(find.textContaining('อย่างน้อย 1 แท็ก'), findsNothing);
      });
    });

    testWidgets('บัญชีที่ยังไม่มีแท็ก กดบันทึก → เตือน ไม่ส่งไป backend',
        (tester) async {
      final sent = await run(tester, [], () async {
        await tester.tap(find.text('บันทึกข้อมูล'));
        await tester.pumpAndSettle();
        expect(find.textContaining('อย่างน้อย 1 แท็ก'), findsOneWidget);
      });
      expect(sent, isEmpty);
    });
  });
}
