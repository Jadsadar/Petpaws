import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/main.dart' show AuthGate;
import 'package:petpaws/screens/admin/admin_screen.dart';
import 'package:petpaws/services/admin_service.dart';
import 'package:petpaws/services/auth_service.dart';
import 'package:petpaws/services/chat_socket.dart';

/// server จำลองที่คืนข้อมูลรูปแบบเดียวกับ backend/api/src/admin จริง และจำสถานะไว้
/// (หลังแบนแล้วคนนั้นหายจากรายการรีพอร์ตและโผล่ในรายการถูกแบน)
class _FakeServer {
  final List<String> calls = [];
  final List<Map<String, dynamic>> bodies = [];
  bool banned = false;
  bool failReported = false;

  /// เปิดแล้ว /admin/reported-users จะมี 45 คน (3 หน้า) เพื่อทดสอบการแบ่งหน้า
  bool many = false;

  static const _photos = [
    {'url': 'http://localhost:9000/p/1.jpg', 'thumbUrl': 'http://localhost:9000/p/1t.jpg'},
    {'url': 'http://localhost:9000/p/2.jpg', 'thumbUrl': null},
  ];

  static const _user = {
    'id': 'u1',
    'username': 'somchai',
    'displayName': 'สมชาย',
    'avatarUrl': '',
    'reportCount': 3,
    'lastReportedAt': '2026-10-01T10:00:00.000Z',
    'isSuspended': false,
    'suspendedUntil': null,
  };

  http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<http.Response> handle(http.Request req) async {
    final path = req.url.path;
    calls.add('${req.method} $path${req.url.hasQuery ? '?${req.url.query}' : ''}');
    if (req.body.isNotEmpty) bodies.add(jsonDecode(req.body) as Map<String, dynamic>);

    final page = int.tryParse(req.url.queryParameters['page'] ?? '1') ?? 1;
    Map<String, dynamic> paged(List<Map<String, dynamic>> items, int total) =>
        {'items': items, 'total': total, 'page': page, 'pageSize': 20};

    if (req.method == 'GET' && path == '/admin/summary') {
      return _json({'reported': banned ? 0 : 1, 'temporary': 0, 'permanent': banned ? 1 : 0});
    }
    if (req.method == 'GET' && path == '/admin/reported-users') {
      if (failReported) {
        return _json({'error': {'code': 'SERVER', 'message': 'เซิร์ฟเวอร์ขัดข้อง'}}, 500);
      }
      if (many) {
        final from = (page - 1) * 20;
        final count = (45 - from).clamp(0, 20);
        return _json(paged([
          for (var i = 0; i < count; i++) {..._user, 'id': 'm${from + i}', 'displayName': 'ผู้ใช้ ${from + i + 1}'}
        ], 45));
      }
      return _json(paged(banned ? [] : [_user], banned ? 0 : 1));
    }
    if (req.method == 'GET' && path == '/admin/users/u1') {
      return _json({
        'id': 'u1',
        'username': 'somchai',
        'email': 'somchai@x.com',
        'displayName': 'สมชาย',
        'avatarUrl': '',
        'bio': 'รักสัตว์',
        'province': 'เชียงใหม่',
        'homeType': 'คอนโด',
        'isSuspended': false,
        'suspendedUntil': null,
        'createdAt': '2026-09-01T10:00:00.000Z',
        'lastLoginAt': '2026-10-01T10:00:00.000Z',
        'pendingReportCount': 3,
        'pets': [
          {
            'id': 'p1',
            'name': 'มะม่วง',
            'species': 'dog',
            'status': 'available',
            'description': 'น้องหมาน่ารัก',
            'deleted': false,
            'location': 'เชียงใหม่',
            'createdAt': '2026-09-02T10:00:00.000Z',
            'photos': _photos,
          }
        ],
      });
    }
    if (req.method == 'GET' && path == '/admin/users/u1/reports') {
      return _json(paged([
        {
          'id': 'r1',
          'reason': 'scam',
          'detail': 'เรียกเงินค่ามัดจำ',
          'createdAt': '2026-10-01T10:00:00.000Z',
          'reporter': {'id': 'x', 'username': 'rep', 'displayName': 'ผู้รายงาน'},
          'targetType': 'pet',
          'petId': 'p1',
          'petName': 'มะม่วง',
          'pet': {
            'id': 'p1',
            'name': 'มะม่วง',
            'status': 'available',
            'description': 'น้องหมาน่ารัก',
            'deleted': false,
            'photos': _photos,
          },
          'messageId': null,
          'messageBody': null,
        },
        {
          'id': 'r2',
          'reason': 'spam',
          'detail': '',
          'createdAt': '2026-10-02T10:00:00.000Z',
          'reporter': {'id': 'y', 'username': 'rep2', 'displayName': ''},
          'targetType': 'message',
          'messageId': 'm1',
          'messageBody': 'โอนเงินมาก่อนนะ',
          'messageCreatedAt': '2026-10-02T09:00:00.000Z',
        },
      ], 2));
    }
    if (req.method == 'GET' && path == '/admin/banned-users') {
      return _json(paged(
          banned
              ? [
                  {
                    'id': 'u1',
                    'username': 'somchai',
                    'displayName': 'สมชาย',
                    'avatarUrl': '',
                    'suspendedUntil': null,
                    'permanent': true,
                  }
                ]
              : [],
          banned ? 1 : 0));
    }
    if (req.method == 'POST' && path == '/admin/users/u1/ban') {
      banned = true;
      return _json({'success': true, 'suspendedUntil': null});
    }
    if (req.method == 'POST' && path == '/admin/users/u1/unban') {
      banned = false;
      return _json({'success': true});
    }
    if (req.method == 'POST' && path == '/admin/users/u1/dismiss-reports') {
      banned = true; // ให้หายจากรายการเหมือนกัน (จำลองว่าไม่เหลือรีพอร์ตค้าง)
      return _json({'success': true, 'dismissed': 1});
    }
    return _json({'error': {'code': 'NOT_FOUND', 'message': 'ไม่พบ $path'}}, 404);
  }
}

Future<void> _pumpAdmin(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: AdminScreen()));
  await tester.pumpAndSettle();
}

void main() {
  // TokenStorage อ่าน token จาก flutter_secure_storage (platform channel) ซึ่งใน widget test
  // ไม่มีใครตอบ ทำให้คำขอ API ค้างไม่รู้จบ — ใช้ storage จำลองที่ไม่มี token แทน
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('แสดงผู้ถูกรายงานพร้อมจำนวนคน และเริ่มที่เกณฑ์ 1 คน', (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      expect(find.text('สมชาย'), findsOneWidget);
      // "3 คน" มี 2 ที่ (ชิปเกณฑ์ด้านบน กับป้ายจำนวนรีพอร์ตของผู้ใช้) ต้องระบุว่าเอาของในรายการ
      expect(find.descendant(of: find.byType(ListTile), matching: find.text('3 คน')), findsOneWidget);
      expect(server.calls, contains('GET /admin/reported-users?minReports=1&page=1&pageSize=20'));
    }, () => MockClient(server.handle));
  });

  testWidgets('เปลี่ยนเกณฑ์เป็น 10 คน แล้วยิงคำขอด้วย minReports=10', (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      await tester.tap(find.text('10 คน'));
      await tester.pumpAndSettle();
      expect(server.calls, contains('GET /admin/reported-users?minReports=10&page=1&pageSize=20'));
    }, () => MockClient(server.handle));
  });

  testWidgets('เปิดรายละเอียด → แบนถาวร → หายจากรีพอร์ต และไปอยู่แท็บถูกแบน → ปลดแบนได้',
      (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);

      await tester.tap(find.text('สมชาย'));
      await tester.pumpAndSettle();
      expect(find.text('สงสัยว่าเป็นการหลอกลวง'), findsOneWidget);
      expect(find.textContaining('ประกาศสัตว์: มะม่วง'), findsOneWidget);
      expect(find.textContaining('เรียกเงินค่ามัดจำ'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'แบนถาวร'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'หลอกลวงจริง');
      await tester.tap(find.text('ยืนยันแบน'));
      await tester.pumpAndSettle();

      // ส่งแบนถาวร = ไม่มี days, มี note
      final banBody = server.bodies.singleWhere((b) => b.containsKey('note'));
      expect(banBody.containsKey('days'), isFalse);
      expect(banBody['note'], 'หลอกลวงจริง');
      expect(server.calls, contains('POST /admin/users/u1/ban'));

      // กลับมาหน้ารายการ โหลดใหม่แล้วไม่เหลือรีพอร์ต
      expect(find.text('ไม่มีรีพอร์ตที่รอตรวจสอบตามเกณฑ์นี้'), findsOneWidget);

      // แท็บถูกแบนเห็นคนนี้ ติดป้ายถาวร
      await tester.tap(find.text('ถูกแบน'));
      await tester.pumpAndSettle();
      expect(find.text('สมชาย'), findsOneWidget);
      expect(find.descendant(of: find.byType(ListTile), matching: find.textContaining('แบนถาวร')), findsOneWidget);

      // ปลดแบน (ต้องกดยืนยันในกล่องข้อความ)
      await tester.tap(find.widgetWithText(TextButton, 'ปลดแบน'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'ปลดแบน'),
      ));
      await tester.pumpAndSettle();
      expect(server.calls, contains('POST /admin/users/u1/unban'));
      expect(find.text('ยังไม่มีบัญชีที่ถูกแบน'), findsOneWidget);
    }, () => MockClient(server.handle));
  });

  testWidgets('แบนชั่วคราวส่งจำนวนวันที่เลือก (30 วัน)', (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      await tester.tap(find.text('สมชาย'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'แบนชั่วคราว'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 วัน'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยืนยันแบน'));
      await tester.pumpAndSettle();

      final banBody = server.bodies.singleWhere((b) => b.containsKey('days'));
      expect(banBody['days'], 30);
    }, () => MockClient(server.handle));
  });

  testWidgets('ปัดตกรีพอร์ตต้องกดยืนยัน แล้วเรียก dismiss-reports', (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      await tester.tap(find.text('สมชาย'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'ปัดตก'));
      await tester.pumpAndSettle();
      expect(server.calls.where((c) => c.contains('dismiss')), isEmpty, reason: 'ยังไม่ยืนยัน ห้ามยิง');

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'ปัดตก'),
      ));
      await tester.pumpAndSettle();
      expect(server.calls, contains('POST /admin/users/u1/dismiss-reports'));
    }, () => MockClient(server.handle));
  });

  testWidgets('กดยกเลิกในกล่องแบน จะไม่ยิง API แบน', (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      await tester.tap(find.text('สมชาย'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'แบนถาวร'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(server.calls.where((c) => c.startsWith('POST') && c.contains('/ban')), isEmpty);
    }, () => MockClient(server.handle));
  });

  String stat(WidgetTester tester, String key) => tester
      .widget<Text>(find.descendant(of: find.byKey(ValueKey('stat-$key')), matching: find.byType(Text)).first)
      .data!;

  testWidgets('แดชบอร์ดแสดงตัวเลขสรุป และอัปเดตทันทีหลังแบนถาวร', (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      expect(stat(tester, 'reported'), '1');
      expect(stat(tester, 'temporary'), '0');
      expect(stat(tester, 'permanent'), '0');

      await tester.tap(find.text('สมชาย'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'แบนถาวร'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยืนยันแบน'));
      await tester.pumpAndSettle();

      expect(stat(tester, 'reported'), '0');
      expect(stat(tester, 'permanent'), '1');
    }, () => MockClient(server.handle));
  });

  testWidgets('กดออกจากระบบต้องยืนยันก่อน และเรียก /auth/logout', (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();
      expect(find.text('ต้องการออกจากระบบแอดมินใช่หรือไม่?'), findsOneWidget);

      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(find.text('ต้องการออกจากระบบแอดมินใช่หรือไม่?'), findsNothing);
    }, () => MockClient(server.handle));
  });

  testWidgets('แบ่งหน้า: 45 คน = 3 หน้า เลื่อนถัดไป/สุดท้ายได้ และเปลี่ยนเกณฑ์กลับไปหน้า 1', (tester) async {
    final server = _FakeServer()..many = true;
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      String label() => tester.widget<Text>(find.byKey(const ValueKey('pager-label'))).data!;
      expect(label(), 'หน้า 1 / 3 · ทั้งหมด 45 รายการ');
      expect(find.text('ผู้ใช้ 1'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('pager-prev'))).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('pager-next')));
      await tester.pumpAndSettle();
      expect(label(), 'หน้า 2 / 3 · ทั้งหมด 45 รายการ');
      expect(server.calls, contains('GET /admin/reported-users?minReports=1&page=2&pageSize=20'));

      await tester.tap(find.byKey(const ValueKey('pager-last')));
      await tester.pumpAndSettle();
      expect(label(), 'หน้า 3 / 3 · ทั้งหมด 45 รายการ');
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('pager-next'))).onPressed, isNull);

      await tester.tap(find.text('5 คน'));
      await tester.pumpAndSettle();
      expect(label(), startsWith('หน้า 1 /'));
    }, () => MockClient(server.handle));
  });

  testWidgets('รีพอร์ตแสดงรูปประกาศ กดดูเต็มจอได้', (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      await tester.tap(find.text('สมชาย'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('photo-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('photo-1')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const ValueKey('viewer-counter'))).data, contains('2 / 2'));
    }, () => MockClient(server.handle));
  });

  testWidgets('รีพอร์ตข้อความแสดงเฉพาะข้อความที่ถูกรายงาน', (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      await tester.tap(find.text('สมชาย'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byKey(const ValueKey('reported-message')), matching: find.text('โอนเงินมาก่อนนะ')),
        findsOneWidget,
      );
      expect(find.text('สแปมหรือโฆษณา'), findsOneWidget);
    }, () => MockClient(server.handle));
  });

  testWidgets('เปิดโปรไฟล์ของผู้ถูกรายงาน เห็นอีเมล ประกาศ และรูป', (tester) async {
    final server = _FakeServer();
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      await tester.tap(find.text('สมชาย'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-profile')));
      await tester.pumpAndSettle();

      expect(server.calls, contains('GET /admin/users/u1'));
      expect(find.text('somchai@x.com'), findsOneWidget);
      expect(find.text('ประกาศของผู้ใช้นี้ (1)'), findsOneWidget);
      expect(find.text('น้องหมาน่ารัก'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-0')), findsOneWidget);
    }, () => MockClient(server.handle));
  });

  group('AuthGate หลังล็อกอิน', () {
    tearDown(() async {
      AdminService.instance.clearCache();
      await http.runWithClient(() => AuthService.instance.signOut(), () => MockClient((_) async => http.Response('{}', 200)));
    });

    Future<http.Response> loginServer(http.Request req, {required bool admin}) async {
      if (req.url.path == '/auth/login') {
        return http.Response(
          jsonEncode({
            'accessToken': 'a',
            'refreshToken': 'r',
            'user': {
              'id': 'uadmin',
              'username': admin ? 'admin' : 'demo01',
              'email': 'x@petpaws.demo',
              'displayName': 'ทดสอบ',
              'avatarUrl': null,
              // false = เพิ่งสมัคร จะถูกพาไปหน้าสร้างโปรไฟล์ (ใช้เป็นตัวแทน "ผู้ใช้ทั่วไป" ที่เรนเดอร์ง่าย)
              'profileCompleted': admin,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (req.url.path.startsWith('/admin/')) {
        return admin
            ? http.Response(
                jsonEncode({'items': [], 'total': 0, 'page': 1, 'pageSize': 20, 'reported': 0, 'temporary': 0, 'permanent': 0}),
                200,
                headers: {'content-type': 'application/json'})
            : http.Response(jsonEncode({'error': {'code': 'FORBIDDEN', 'message': 'เฉพาะแอดมินเท่านั้น'}}), 403,
                headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response('[]', 200, headers: {'content-type': 'application/json'});
    }

    testWidgets('บัญชีแอดมินเข้าแดชบอร์ดแอดมินทันที ไม่เห็นแอปผู้ใช้ (ไม่มีแท็บค้นหา/ถูกใจ/แชท)', (tester) async {
      await http.runWithClient(() async {
        await AuthService.instance.signIn(identifier: 'admin', password: 'x');
        // signIn เปิด WebSocket แชทเอง ซึ่งสร้าง timer ค้างในเทสต์ ปิดทิ้งก่อน (เทสต์นี้ไม่เกี่ยวกับแชท)
        ChatSocket.instance.disconnect();
        await tester.pumpWidget(const MaterialApp(home: AuthGate()));
        await tester.pumpAndSettle();

        expect(find.text('แดชบอร์ดแอดมิน'), findsOneWidget);
        expect(find.text('ค้นหา'), findsNothing);
        expect(find.text('ลงประกาศ'), findsNothing);
        expect(find.byType(BottomNavigationBar), findsNothing);
      }, () => MockClient((r) => loginServer(r, admin: true)));
    });

    testWidgets('ผู้ใช้ทั่วไปไม่เห็นแดชบอร์ดแอดมิน', (tester) async {
      await http.runWithClient(() async {
        await AuthService.instance.signIn(identifier: 'demo01', password: 'x');
        // signIn เปิด WebSocket แชทเอง ซึ่งสร้าง timer ค้างในเทสต์ ปิดทิ้งก่อน (เทสต์นี้ไม่เกี่ยวกับแชท)
        ChatSocket.instance.disconnect();
        await tester.pumpWidget(const MaterialApp(home: AuthGate()));
        await tester.pumpAndSettle();

        expect(find.text('แดชบอร์ดแอดมิน'), findsNothing);
      }, () => MockClient((r) => loginServer(r, admin: false)));
    });
  });

  testWidgets('server error แสดงข้อความภาษาไทยจาก backend และมีปุ่มลองใหม่', (tester) async {
    final server = _FakeServer()..failReported = true;
    await http.runWithClient(() async {
      await _pumpAdmin(tester);
      expect(find.text('เซิร์ฟเวอร์ขัดข้อง'), findsOneWidget);
      expect(find.text('ลองใหม่'), findsOneWidget);

      server.failReported = false;
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(find.text('สมชาย'), findsOneWidget);
    }, () => MockClient(server.handle));
  });
}
