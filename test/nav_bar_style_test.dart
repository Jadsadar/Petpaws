import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/main_screen.dart';
import 'package:petpaws/services/chat_socket.dart';

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('แถบเมนูล่าง: แท็บที่เลือกชมพู/ใหญ่ขึ้น แท็บอื่นเทา/ขนาดปกติ', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: MainScreen()));
      await tester.pumpAndSettle();

      BottomNavigationBar bar() => tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));
      expect(bar().selectedIconTheme!.size, greaterThan(bar().unselectedIconTheme!.size!));
      expect(bar().selectedItemColor, isNot(bar().unselectedItemColor));
      expect(bar().unselectedItemColor, Colors.grey.shade500);

      // ขนาดไอคอนจริงบนจอ: แท็บที่เลือก (ค้นหา) ใหญ่กว่าแท็บอื่น (ถูกใจ)
      double sizeOf(IconData icon) => tester.getSize(find.descendant(
          of: find.byType(BottomNavigationBar), matching: find.byIcon(icon))).width;
      expect(sizeOf(Icons.search), greaterThan(sizeOf(Icons.favorite)));

      await tester.tap(find.text('ถูกใจ'));
      await tester.pumpAndSettle();
      expect(sizeOf(Icons.favorite), greaterThan(sizeOf(Icons.search)));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      ChatSocket.instance.disconnect();
    }, () => MockClient((req) async {
          final p = req.url.path;
          if (p == '/pets/deck') return _json({'dogs': [], 'nextCursor': null, 'hasMore': false});
          if (p == '/chats/unread-count') return _json({'count': 0});
          if (p == '/chats') return _json([]);
          return _json([]);
        }));
  });
}
