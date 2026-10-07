import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/auth/login_screen.dart';
import 'package:petpaws/screens/auth/verify_email_screen.dart';
import 'package:petpaws/services/auth_service.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

const _generic = 'ถ้าบัญชีนี้ยังไม่ได้ยืนยัน ระบบส่งลิงก์ยืนยันไปที่อีเมลแล้ว';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('AuthService', () {
    test('register คืน true เมื่อ backend ส่งลิงก์ยืนยันแล้ว และ false เมื่อระบบอีเมลปิดอยู่', () async {
      Future<bool> run(bool required) => http.runWithClient(
            () => AuthService.instance.register(email: 'a@b.co', password: 'x', username: 'abc'),
            () => MockClient((_) async => _json({'id': 'u1', 'verificationRequired': required}, 201)),
          );
      expect(await run(true), isTrue);
      expect(await run(false), isFalse);
    });

    test('signIn ที่ยังไม่ยืนยันอีเมล โยน AuthFailure พร้อมรหัส EMAIL_NOT_VERIFIED', () async {
      await http.runWithClient(() async {
        await expectLater(
          AuthService.instance.signIn(identifier: 'abc', password: 'x'),
          throwsA(isA<AuthFailure>().having((e) => e.code, 'code', 'EMAIL_NOT_VERIFIED')),
        );
      }, () => MockClient((_) async => _json({'error': {'code': 'EMAIL_NOT_VERIFIED', 'message': 'ยืนยันก่อน'}}, 403)));
    });

    test('resendVerification ส่ง identifier และคืนข้อความจาก backend', () async {
      Map<String, dynamic>? sent;
      final msg = await http.runWithClient(
        () => AuthService.instance.resendVerification('abc'),
        () => MockClient((req) async {
          expect(req.url.path, '/auth/resend-verification');
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({'message': _generic});
        }),
      );
      expect(sent, {'identifier': 'abc'});
      expect(msg, _generic);
    });
  });

  group('หน้า "ตรวจอีเมลของคุณ"', () {
    Future<List<String>> pump(WidgetTester tester) async {
      final calls = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VerifyEmailScreen(email: 'somchai@example.com', identifier: 'somchai')),
            ),
            child: const Text('เปิด'),
          ),
        ),
      ));
      await tester.tap(find.text('เปิด'));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('โชว์อีเมลที่ส่งไป และปุ่มส่งซ้ำถูกพักไว้ 60 วินาทีแรก', (tester) async {
      await pump(tester);
      expect(find.text('ตรวจอีเมลของคุณ'), findsOneWidget);
      expect(find.textContaining('somchai@example.com'), findsOneWidget);
      final btn = find.byKey(const ValueKey('verify-resend-button'));
      expect(tester.widget<TextButton>(btn).onPressed, isNull);
      expect(find.textContaining('60 วินาที'), findsOneWidget);

      await tester.pump(const Duration(seconds: 20));
      expect(find.textContaining('40 วินาที'), findsOneWidget);
      await tester.pump(const Duration(seconds: 41));
      expect(tester.widget<TextButton>(btn).onPressed, isNotNull);
      expect(find.text('ส่งลิงก์ยืนยันอีกครั้ง'), findsOneWidget);
    });

    testWidgets('ครบเวลา → กดส่งซ้ำ → เรียก API แล้วเริ่มนับถอยหลังใหม่', (tester) async {
      final bodies = <Map<String, dynamic>>[];
      await http.runWithClient(() async {
        await pump(tester);
        await tester.pump(const Duration(seconds: 61));
        await tester.tap(find.byKey(const ValueKey('verify-resend-button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(bodies, [
          {'identifier': 'somchai'}
        ]);
        expect(find.text(_generic), findsOneWidget);
        expect(tester.widget<TextButton>(find.byKey(const ValueKey('verify-resend-button'))).onPressed, isNull);
        await tester.pump(const Duration(seconds: 61)); // ปล่อย timer ให้จบ
      }, () => MockClient((req) async {
            bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
            return _json({'message': _generic});
          }));
    });

    testWidgets('กด "ยืนยันแล้ว ไปเข้าสู่ระบบ" → ปิดหน้านี้', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('verify-done')));
      await tester.pumpAndSettle();
      expect(find.text('ตรวจอีเมลของคุณ'), findsNothing);
      expect(find.text('เปิด'), findsOneWidget);
    });
  });

  testWidgets('ล็อกอินก่อนยืนยันอีเมล → ขึ้นกล่องเสนอส่งลิงก์ใหม่ และกดแล้วส่งด้วย identifier ที่พิมพ์', (tester) async {
    final calls = <String>[];
    final bodies = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.enterText(find.byType(TextField).at(0), 'somchai');
      await tester.enterText(find.byType(TextField).at(1), 'Str0ng!Passw0rd#1');
      await tester.tap(find.widgetWithText(ElevatedButton, 'เข้าสู่ระบบ'));
      await tester.pumpAndSettle();

      expect(find.text('ยังไม่ได้ยืนยันอีเมล'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('verify-resend')));
      await tester.pumpAndSettle();

      expect(calls, ['POST /auth/login', 'POST /auth/resend-verification']);
      expect(bodies.last, {'identifier': 'somchai'});
      expect(find.text(_generic), findsOneWidget);
    }, () => MockClient((req) async {
          calls.add('${req.method} ${req.url.path}');
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          if (req.url.path == '/auth/login') {
            return _json({'error': {'code': 'EMAIL_NOT_VERIFIED', 'message': 'ยังไม่ได้ยืนยันอีเมล กรุณากดลิงก์'}}, 403);
          }
          return _json({'message': _generic});
        }));
  });

  testWidgets('รหัสผ่านผิดธรรมดา → ไม่ขึ้นกล่องยืนยันอีเมล', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.enterText(find.byType(TextField).at(0), 'somchai');
      await tester.enterText(find.byType(TextField).at(1), 'ผิด');
      await tester.tap(find.widgetWithText(ElevatedButton, 'เข้าสู่ระบบ'));
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่ได้ยืนยันอีเมล'), findsNothing);
      expect(find.text('ชื่อผู้ใช้/อีเมล หรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);
    }, () => MockClient((_) async => _json({'error': {'code': 'UNAUTHORIZED', 'message': 'ชื่อผู้ใช้/อีเมล หรือรหัสผ่านไม่ถูกต้อง'}}, 401)));
  });
}
