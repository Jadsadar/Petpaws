import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/auth/forgot_password_screen.dart';
import 'package:petpaws/screens/auth/login_screen.dart';

const _okMessage = 'ถ้ามีบัญชีนี้อยู่ในระบบ ระบบได้ออกลิงก์รีเซ็ตรหัสผ่านแล้ว';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('หน้าเข้าสู่ระบบมีลิงก์ "ลืมรหัสผ่าน?" กดแล้วไปหน้าลืมรหัสผ่าน พร้อมอีเมลที่พิมพ์ไว้',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.enterText(find.byKey(const ValueKey('login-identifier')), 'me@petpaws.app');
    await tester.tap(find.byKey(const ValueKey('login-forgot-link')));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text('me@petpaws.app'), findsOneWidget, reason: 'ใส่อีเมลให้ล่วงหน้า');
  });

  testWidgets('อีเมลว่าง/ผิดรูปแบบ → เตือนใต้ช่อง ไม่ยิง API', (tester) async {
    var called = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));

      await tester.tap(find.byKey(const ValueKey('forgot-submit')));
      await tester.pump();
      expect(find.text('กรุณากรอกอีเมลที่ใช้สมัคร'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('forgot-email')), 'not-an-email');
      await tester.tap(find.byKey(const ValueKey('forgot-submit')));
      await tester.pump();
      expect(find.text('รูปแบบอีเมลไม่ถูกต้อง'), findsOneWidget);
    }, () => MockClient((_) async {
          called++;
          return http.Response('{}', 200);
        }));
    expect(called, 0);
  });

  testWidgets('ส่งคำขอ → เรียก POST /auth/forgot-password แล้วแสดงข้อความจาก backend', (tester) async {
    final calls = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));
      await tester.enterText(find.byKey(const ValueKey('forgot-email')), 'me@petpaws.app');
      await tester.tap(find.byKey(const ValueKey('forgot-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('forgot-done')), findsOneWidget);
      expect(find.text(_okMessage), findsOneWidget);
    }, () => MockClient((req) async {
          calls.add('${req.method} ${req.url.path} ${req.body}');
          return http.Response(jsonEncode({'message': _okMessage}), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    expect(calls.single, 'POST /auth/forgot-password {"email":"me@petpaws.app"}');
  });
}
