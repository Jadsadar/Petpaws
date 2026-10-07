// ตรวจ layout บนมือถือ (แนวตั้ง — แอปล็อกแนวตั้งบนมือถือ): เปิดทุกหน้า/กล่องข้อความในจอเล็ก-กลาง-ใหญ่ × ตัวอักษรปกติ/ใหญ่/ใหญ่มาก
// แล้วเก็บทุกอย่างที่ล้นจอ (RenderFlex overflowed) หรือโยน exception ตอนวาด
// ข้อมูลจำลองใช้ข้อความไทยยาวๆ เพื่อให้เจอจุดที่ตัดไม่ได้จริง
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/data/mock_data.dart';
import 'package:petpaws/screens/admin/admin_cache_stats_screen.dart';
import 'package:petpaws/screens/admin/admin_monitoring_screen.dart';
import 'package:petpaws/screens/admin/admin_screen.dart';
import 'package:petpaws/screens/admin/admin_user_profile_screen.dart';
import 'package:petpaws/screens/admin/admin_user_reports_screen.dart';
import 'package:petpaws/screens/auth/create_profile_screen.dart';
import 'package:petpaws/screens/auth/forgot_password_screen.dart';
import 'package:petpaws/screens/auth/login_screen.dart';
import 'package:petpaws/screens/auth/register_screen.dart';
import 'package:petpaws/screens/auth/verify_email_screen.dart';
import 'package:petpaws/screens/chat/chat_inbox_screen.dart';
import 'package:petpaws/screens/chat/chat_screen.dart';
import 'package:petpaws/screens/detail/pet_detail_screen.dart';
import 'package:petpaws/screens/discover/discover_screen.dart';
import 'package:petpaws/screens/favorites/favorites_screen.dart';
import 'package:petpaws/screens/main_screen.dart';
import 'package:petpaws/screens/profile/profile_screen.dart';
import 'package:petpaws/screens/profile/user_profile_screen.dart';
import 'package:petpaws/screens/upload/edit_dog_screen.dart';
import 'package:petpaws/screens/upload/pet_post_preview_screen.dart';
import 'package:petpaws/screens/upload/upload_screen.dart';
import 'package:petpaws/services/admin_service.dart';
import 'package:petpaws/services/chat_socket.dart';
import 'package:petpaws/services/update_service.dart';
import 'package:petpaws/theme/app_theme.dart';
import 'package:petpaws/widgets/province_picker.dart';
import 'package:petpaws/widgets/swipeable_card.dart';
import 'package:petpaws/widgets/update_gate.dart';
import 'package:petpaws/widgets/report_dialog.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

const _longName = 'สมชาย ใจดีมากๆ เลยครับผมท่านผู้ชม';
const _longStory =
    'น้องเป็นสุนัขที่น่ารักมาก เชื่องกับคนทุกคน กินเก่ง นอนเก่ง ชอบเล่นกับเด็กๆ ฉีดวัคซีนครบแล้ว ทำหมันแล้ว กำลังมองหาบ้านที่อบอุ่นและมีใจรักสัตว์จริงๆ ถ้าสนใจทักแชทมาคุยกันได้เลยนะคะ ไม่รีบร้อน อยากให้น้องได้บ้านที่ดีที่สุด';

Map<String, dynamic> _dog(String id,
        {String status = 'ยังไม่ถูกรับเลี้ยง', String species = 'dog'}) =>
    {
      'id': id,
      'ownerId': 'u2',
      'ownerName': _longName,
      'ownerAvatar': '',
      'name': 'มะม่วงทองคำขาวนวลน้อย',
      'species': species,
      'breed': 'ชิวาวาผสมปอมเมอเรเนียนสายพันธุ์ผสม',
      'province': 'นครศรีธรรมราช',
      'age': '1 ปี 3 เดือน',
      'gender': 'ผู้',
      'weight': '12.5',
      'tags': ['chill', 'foodie', 'playful', 'cuddly'],
      'story': _longStory,
      'imageUrl': '',
      'status': status,
      'engagementLikes': 12,
    };

Map<String, dynamic> _chat(String id, {int unread = 0}) => {
      'id': id,
      'petId': 'p1',
      'petName': 'มะม่วงทองคำขาวนวลน้อย',
      'petImageUrl': '',
      'otherUserId': 'u2',
      'otherUserName': _longName,
      'otherUserAvatarUrl': '',
      'lastMessage': _longStory,
      'lastMessageAt': '2026-10-06T12:00:00.000Z',
      'unreadCount': unread,
      'status': 'active',
    };

Map<String, dynamic> _msg(String id, String sender, String text,
        {String kind = 'text'}) =>
    {
      'id': id,
      'senderId': sender,
      'text': text,
      'kind': kind,
      'media': null,
      'createdAt': '2026-10-06T12:0${id.length}:00.000Z',
      'readAt': sender == 'me' ? '2026-10-06T12:30:00.000Z' : null,
      'clientId': id,
    };

final _adminPets = [
  {
    'id': 'ap1',
    'name': 'มะม่วงทองคำขาวนวลน้อย',
    'species': 'dog',
    'status': 'ยังไม่ถูกรับเลี้ยง',
    'description': _longStory,
    'deleted': false,
    'photos': [
      {'url': 'http://localhost/1.jpg', 'thumbUrl': null}
    ],
    'location': 'นครศรีธรรมราช',
    'createdAt': '2026-10-01T10:00:00.000Z',
  }
];

Map<String, dynamic> _reportedUser() => {
      'id': 'u2',
      'username': 'somchai_jaidee_mak_mak_kub',
      'email': 'somchai.jaidee.mak.mak@example-long-domain.co.th',
      'displayName': _longName,
      'avatarUrl': '',
      'reportCount': 12,
      'lastReportedAt': '2026-10-01T10:00:00.000Z',
      'isSuspended': false,
      'suspendedUntil': null,
    };

/// normal = ข้อมูลเต็ม | empty = ไม่มีข้อมูลเลย | fail = server ล่ม (หน้า error) | unverified = ล็อกอินติด "ยังไม่ยืนยันอีเมล"
String _mode = 'normal';

http.Response _handle(http.Request req) {
  final p = req.url.path;
  final m = req.method;
  if (_mode == 'fail' && m == 'GET') {
    return _json({
      'error': {
        'code': 'SERVER_ERROR',
        'message':
            'เซิร์ฟเวอร์ขัดข้องชั่วคราว กรุณาลองใหม่อีกครั้งในอีกสักครู่ ถ้ายังไม่หายให้ติดต่อผู้ดูแลระบบของ Petpaws'
      }
    }, 500);
  }
  if (_mode == 'unverified' && p == '/auth/login') {
    return _json({
      'error': {
        'code': 'EMAIL_NOT_VERIFIED',
        'message':
            'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ เราส่งลิงก์ยืนยันไปที่อีเมลของคุณแล้ว'
      }
    }, 403);
  }
  if (_mode == 'empty' && m == 'GET') {
    if (p == '/pets/deck') {
      return _json({'dogs': [], 'nextCursor': null, 'hasMore': false});
    }
    if (['/pets/mine', '/pets/likes', '/chats'].contains(p) ||
        p.startsWith('/pets/by-owner/')) {
      return _json([]);
    }
    if (p == '/chats/c1/messages') {
      return _json({
        'messages': [],
        'room': {
          'status': 'active',
          'closedReason': null,
          'blockedByMe': false
        },
      });
    }
    if (p.startsWith('/admin/') &&
        p != '/admin/summary' &&
        p != '/admin/cache-stats' &&
        p != '/admin/perf-stats' &&
        !RegExp(r'^/admin/users/[^/]+$').hasMatch(p)) {
      return _json({'items': [], 'total': 0, 'page': 1, 'pageSize': 20});
    }
  }
  if (m == 'GET') {
    if (p == '/admin/perf-stats') {
      return _json({
        'scope': 'shared',
        'since': '2026-10-07T00:00:00Z',
        'slowThresholdMs': 500,
        'routes': [
          {
            'route': 'GET /pets/deck',
            'count': 12840,
            'avgMs': 42.5,
            'maxMs': 812,
            'totalMs': 545700,
            'slowCount': 12
          }
        ],
        'queries': {
          'available': true,
          'items': [
            {
              'query':
                  'SELECT id, name FROM pets WHERE status = \$1 ORDER BY created_at DESC LIMIT \$2',
              'calls': 2400,
              'totalMs': 8500,
              'meanMs': 3.54,
              'rows': 48000
            }
          ]
        },
      });
    }
    if (p == '/pets/deck') {
      return _json({
        'dogs': [_dog('d1'), _dog('d2')],
        'nextCursor': null,
        'hasMore': false
      });
    }
    if (p == '/pets/mine') {
      return _json([
        _dog('d1'),
        _dog('d2', status: 'ถูกรับเลี้ยงแล้ว'),
        _dog('d3', status: 'ยกเลิกประกาศ')
      ]);
    }
    if (p == '/pets/likes') return _json([_dog('d1'), _dog('d2')]);
    if (p.startsWith('/pets/by-owner/')) {
      return _json([_dog('d1'), _dog('d2', status: 'ถูกรับเลี้ยงแล้ว')]);
    }
    if (p.startsWith('/pets/')) return _json(_dog('d1'));
    if (p == '/chats/unread-count') return _json({'count': 7});
    if (p == '/chats/lookup') return _json({'chatId': 'c1'});
    if (p == '/chats') {
      return _json(
          [_chat('c1', unread: 120), _chat('c2'), _chat('c3', unread: 3)]);
    }
    if (p == '/chats/c1/messages') {
      return _json({
        'messages': [
          _msg('m1', 'u2', _longStory),
          _msg('m22', 'me', _longStory),
          _msg('m3', 'u2', 'สวัสดีครับ'),
          _msg('m4', 'me',
              'ห้อง https://example.com/very/long/link/that/should/not/overflow/the/bubble/at/all/ok'),
          {
            ..._msg('m5', 'u2', ''),
            'kind': 'image',
            'media': {
              'type': 'image',
              'url': 'http://localhost/x.jpg',
              'thumbnailUrl': 'http://localhost/t.jpg',
              'width': 1600,
              'height': 900
            },
          },
          {
            ..._msg('m66', 'me', ''),
            'kind': 'video',
            'media': {
              'type': 'video',
              'url': 'http://localhost/x.mp4',
              'thumbnailUrl': 'http://localhost/t.jpg',
              'width': 720,
              'height': 1280,
              'durationMs': 95000
            },
          },
          _msg('m7', 'system',
              'มีคนรับเลี้ยงสัตว์ตัวนี้แล้ว ห้องแชทนี้ถูกปิดและไม่สามารถส่งข้อความได้อีก',
              kind: 'system'),
        ],
        'room': {
          'status': 'active',
          'closedReason': null,
          'blockedByMe': false
        },
      });
    }
    if (p.startsWith('/chats/')) {
      return _json(
          {'status': 'active', 'closedReason': null, 'blockedByMe': false});
    }
    if (p == '/users/me') {
      return _json({
        'id': 'me',
        'username': 'me',
        'email': 'somchai.jaidee.mak.mak@example-long-domain.co.th',
        'displayName': _longName,
        'profileImageUrl': '',
        'province': 'นครศรีธรรมราช',
        'phone': '0812345678',
        'lineId': 'line_id_ที่ยาวมากมายก่ายกอง',
        'fbLink':
            'https://facebook.com/some.very.long.profile.name.that.goes.on',
        'homeType': 'ทาวน์โฮม/ทาวน์เฮ้าส์',
        'traits': ['chill', 'foodie', 'playful'],
        'profileCompleted': true,
      });
    }
    if (p.startsWith('/users/')) {
      return _json({
        'id': 'u2',
        'displayName': _longName,
        'profileImageUrl': '',
        'province': 'นครศรีธรรมราช',
        'lineId': 'line_id_ที่ยาวมากมายก่ายกอง',
        'fbLink':
            'https://facebook.com/some.very.long.profile.name.that.goes.on',
        'homeType': 'ทาวน์โฮม/ทาวน์เฮ้าส์',
        'traits': ['chill', 'foodie', 'playful'],
      });
    }
    if (p == '/admin/summary') {
      return _json({'reported': 128, 'temporary': 7, 'permanent': 1034});
    }
    if (p == '/admin/reported-users') {
      return _json({
        'items': [_reportedUser(), _reportedUser()],
        'total': 45,
        'page': 1,
        'pageSize': 20
      });
    }
    if (p == '/admin/banned-users') {
      return _json({
        'items': [
          {
            ..._reportedUser(),
            'suspendedUntil': '2027-01-01T00:00:00.000Z',
            'permanent': false,
          },
          {..._reportedUser(), 'suspendedUntil': null, 'permanent': true},
        ],
        'total': 2,
        'page': 1,
        'pageSize': 20,
      });
    }
    if (RegExp(r'^/admin/users/[^/]+/reports$').hasMatch(p)) {
      return _json({
        'items': [
          {
            'id': 'r1',
            'reason': 'inappropriate',
            'detail': _longStory,
            'createdAt': '2026-10-01T10:00:00.000Z',
            'reporter': {
              'id': 'u9',
              'username': 'reporter_with_a_long_username_x',
              'displayName': _longName
            },
            'targetType': 'message',
            'messageBody': _longStory,
            'messageCreatedAt': '2026-10-01T10:00:00.000Z',
          },
          {
            'id': 'r2',
            'reason': 'other',
            'detail': 'ข้อความสั้น',
            'createdAt': '2026-10-02T10:00:00.000Z',
            'reporter': {'id': 'u8', 'username': 'x', 'displayName': 'ก'},
            'targetType': 'pet',
            'petName': 'มะม่วงทองคำขาวนวลน้อย',
            'pet': _adminPets.first,
          },
        ],
        'total': 2,
        'page': 1,
        'pageSize': 20,
      });
    }
    if (p.startsWith('/admin/users/')) {
      return _json({
        ..._reportedUser(),
        'bio': _longStory,
        'province': 'นครศรีธรรมราช',
        'homeType': 'ทาวน์โฮม/ทาวน์เฮ้าส์',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'lastLoginAt': '2026-10-01T00:00:00.000Z',
        'pendingReportCount': 12,
        'pets': _adminPets,
      });
    }
    if (p == '/admin/cache-stats') {
      return _json({
        'enabled': true,
        'available': true,
        'since': '2026-10-01T00:00:00.000Z',
        'errors': 123456,
        'overall': {'hits': 1234567, 'misses': 234567, 'hitRatio': 0.8412},
        'namespaces': [
          {
            'name': 'userPublic',
            'ttlSeconds': 3600,
            'hits': 123456,
            'misses': 12345,
            'hitRatio': 0.91
          },
          {
            'name': 'petsByOwner',
            'ttlSeconds': 60,
            'hits': 0,
            'misses': 0,
            'hitRatio': null
          },
        ],
        'redis': {
          'keys': 123456,
          'keyspaceHits': 1234567,
          'keyspaceMisses': 234567,
          'hitRatio': 0.84,
          'evictedKeys': 12,
          'expiredKeys': 345678,
          'usedMemoryBytes': 123456789,
          'maxMemoryBytes': 268435456,
          'maxMemoryPolicy': 'allkeys-lru',
          'uptimeSeconds': 8640000,
        },
      });
    }
  }
  if (m == 'POST' && p == '/auth/login') {
    return _json({
      'error': {
        'code': 'INVALID_CREDENTIALS',
        'message': 'ชื่อผู้ใช้/อีเมลหรือรหัสผ่านไม่ถูกต้อง กรุณาตรวจสอบอีกครั้ง'
      }
    }, 400);
  }
  if (m == 'POST' && p == '/auth/resend-verification') {
    return _json({'message': 'ส่งลิงก์ยืนยันแล้ว'});
  }
  return _json({});
}

class _Size {
  const _Size(this.name, this.size);
  final String name;
  final Size size;
}

const _sizes = [
  _Size('320x568', Size(320, 568)), // iPhone SE รุ่นแรก / Android จอเล็ก
  _Size('360x640', Size(360, 640)),
  _Size('393x852', Size(393, 852)),
  _Size('411x915', Size(411, 915)),
  _Size('768x1024', Size(768, 1024)), // tablet
  _Size('1440x900', Size(1440, 900)), // desktop: keep forms/cards readable
];
// 1.3 = ตัวอักษร "ใหญ่" ที่พบบ่อย, 2.0 = ใหญ่สุดของระบบ (แอปจำกัดไว้ที่ AppTheme.maxTextScale)
const _scales = [1.0, 1.3, 2.0];

/// ห่อเหมือน main.dart (ขยายตัวอักษรทั้งแอป + พื้นหลัง) เพื่อให้ตรงกับของจริง
Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: AppTheme.appTextScaler(mq.textScaler)),
          child: AppBackground(child: child!),
        );
      },
      home: home,
    );

/// ตั้ง --dart-define=SHOT_DIR=<โฟลเดอร์> เพื่อบันทึกภาพหน้าจอ (PNG) ของทุกขั้นแทนการตรวจล้นจอเท่านั้น
/// ไว้เปิดดูด้วยตาว่าหน้าตาบนจอเล็กเป็นอย่างไร (ใช้ฟอนต์จริง แต่รูปสัตว์เป็นช่องว่าง) รันเช่น
///   flutter test test/responsive_test.dart --plain-name "LoginScreen" --dart-define=SHOT_DIR=C:/tmp/shots
const _shotDir = String.fromEnvironment('SHOT_DIR');
final _shotKey = GlobalKey();

Future<void> _shot(WidgetTester tester, String label) async {
  await tester.runAsync(() async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final safe =
        label.replaceAll(RegExp(r'[^\w฀-๿×.{} -]'), '_').replaceAll(' ', '_');
    await Directory(_shotDir).create(recursive: true);
    await File('$_shotDir/$safe.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

/// ข้อความที่ชิดขอบจอ (ห่างขอบ < 6px) = ลืมเว้นขอบซ้าย-ขวา (ล้นจอไม่ได้ แต่ดูแย่และตัวอักษรโดนตัดขอบ)
/// ข้ามข้อความที่อยู่นอกจอ/อยู่ในแถบเลื่อนแนวนอน
void _checkEdges(WidgetTester tester, String current, List<String> problems) {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final texts = find.byType(RichText).evaluate();
  for (final e in texts) {
    final box = e.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.width < 24 || rect.bottom < 0 || rect.top > height) continue;
    var skip = false;
    e.visitAncestorElements((a) {
      if (a.widget is FittedBox || a.widget is InputDecorator) {
        skip = true;
        return false;
      }
      return true;
    });
    if (skip) continue;
    final span = (e.widget as RichText).text.toPlainText();
    if (span.trim().length < 6) continue;
    if (rect.left < 6 || rect.right > width - 6) {
      final key =
          '$current → ข้อความชิดขอบจอ "${span.length > 24 ? span.substring(0, 24) : span}" (${rect.left.toStringAsFixed(0)}..${rect.right.toStringAsFixed(0)} จาก ${width.toStringAsFixed(0)})';
      if (!problems.contains(key)) problems.add(key);
    }
  }
}

typedef _Step = Future<void> Function(WidgetTester tester);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
  } catch (_) {
    // มี animation วนไม่จบ (spinner) ก็ข้ามไป
  }
}

/// เปิด [home] ทุกขนาดจอ × ขนาดตัวอักษร แล้วรวมข้อผิดพลาดการวาดทั้งหมด
/// [steps] = ขั้นตอนต่อจากเปิดหน้า (เช่น กดแท็บ เปิดกล่อง) แต่ละขั้นตรวจแยกกัน
void _responsive(
  String name,
  Widget Function() home, {
  Map<String, _Step> steps = const {},
  bool keyboard = false,
  List<String> modes = const ['normal'],
}) {
  testWidgets(name, (tester) async {
    final problems = <String>[];
    final oldHandler = FlutterError.onError;
    var current = '';
    var iterErrors = 0;
    FlutterError.onError = (d) {
      iterErrors++;
      // error แรกของแต่ละรอบเท่านั้น (ตัวถัดไปมักเป็นผลต่อเนื่อง เช่น "was not laid out")
      if (iterErrors > 1 && !d.exceptionAsString().contains('overflowed')) {
        return;
      }
      final text = d.toString();
      if (const bool.fromEnvironment('FULL') && problems.length < 2) {
        debugPrint(text);
      }
      final msg = d.exceptionAsString().split('\n').first;
      final where = RegExp(r'(lib/[\w/]+\.dart:\d+:\d+)')
              .firstMatch(text.replaceAll(r'\', '/'))
              ?.group(1) ??
          '';
      final key = '$current → $msg $where';
      if (!problems.contains(key)) problems.add(key);
    };
    try {
      await http.runWithClient(() async {
        for (final mode in modes) {
          _mode = mode;
          for (final s in _sizes) {
            final landscape = s.size.width > s.size.height;
            for (final scale in _scales) {
              if (_shotDir.isNotEmpty &&
                  (scale > 1.5 ||
                      s.name.startsWith('360') ||
                      s.name.startsWith('411'))) {
                continue;
              }
              // แนวนอนตรวจแค่ตัวอักษรปกติ/ใหญ่ (จอเตี้ยมากจนตัวอักษรใหญ่สุดไม่สมจริง)
              if (landscape && scale > 1.5) continue;
              for (final kb in [
                false,
                if (keyboard && !landscape && scale <= 1.5) true
              ]) {
                tester.view.physicalSize = s.size;
                tester.view.devicePixelRatio = 1.0;
                tester.platformDispatcher.textScaleFactorTestValue = scale;
                // รอยบาก/แถบสถานะด้านบน และแถบ home ด้านล่าง เหมือนมือถือสมัยใหม่
                final pad = FakeViewPadding(
                    top: landscape ? 0 : 44, bottom: landscape ? 0 : 34);
                tester.view.padding = pad;
                tester.view.viewPadding = pad;
                tester.view.viewInsets = kb
                    ? const FakeViewPadding(bottom: 280)
                    : FakeViewPadding.zero;
                for (final entry
                    in <String, _Step?>{'': null, ...steps}.entries) {
                  current =
                      '${mode == 'normal' ? '' : '{$mode} '}${s.name} ×$scale${kb ? ' คีย์บอร์ด' : ''}${entry.key.isEmpty ? '' : ' [${entry.key}]'}';
                  iterErrors = 0;
                  await tester.pumpWidget(
                      RepaintBoundary(key: _shotKey, child: _app(home())));
                  await _settle(tester);
                  if (entry.value != null) {
                    await entry.value!(tester);
                    await _settle(tester);
                  }
                  _checkEdges(tester, current, problems);
                  if (_shotDir.isNotEmpty) {
                    await _shot(tester, '$name $current');
                  }
                  await tester.pumpWidget(const SizedBox());
                  await tester.pump(const Duration(milliseconds: 300));
                  ChatSocket.instance.disconnect();
                }
              }
            }
          }
        }
      }, () => MockClient((req) async => _handle(req)));
    } finally {
      _mode = 'normal';
      FlutterError.onError = oldHandler;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    }
    expect(problems, isEmpty, reason: '\n${problems.join('\n')}');
  });
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) return;
  await tester.tap(f.first, warnIfMissed: false);
}

/// เลื่อนหน้าลงจนสุด เพื่อให้ ListView สร้างและวัดทุกส่วน (ไม่งั้นส่วนล่างที่อยู่นอกจอไม่ถูกตรวจ)
Future<void> _scrollAll(WidgetTester t) async {
  final vertical = find
      .byWidgetPredicate((w) => w is Scrollable && (w.axis == Axis.vertical));
  if (vertical.evaluate().isEmpty) return;
  for (var i = 0; i < 14; i++) {
    await t.drag(vertical.first, const Offset(0, -320), warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 120));
  }
}

class _Open extends StatelessWidget {
  const _Open(this.open);
  final Future<void> Function(BuildContext) open;
  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: TextButton(
              onPressed: () => open(context), child: const Text('เปิด'))));
}

/// เทสต์ใช้ฟอนต์สี่เหลี่ยม (Ahem) แทนฟอนต์ที่ฝังในแอป ทำให้ข้อความไทยกว้างเกินจริง 1-2 เท่า
/// ต้องโหลด Sarabun/TitanOne จริงก่อน ไม่งั้นผลวัดล้นจอจะผิดจากเครื่องจริง
Future<void> _loadFonts() async {
  Future<ByteData> read(String f) async =>
      ByteData.view((await File('assets/fonts/$f').readAsBytes()).buffer);
  final sarabun = FontLoader('Sarabun');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    sarabun.addFont(read('Sarabun-$f.ttf'));
  }
  await sarabun.load();
  final titan = FontLoader('TitanOne')..addFont(read('TitanOne-Regular.ttf'));
  await titan.load();
  // ไอคอน Material (ไม่งั้นภาพหน้าจอเป็นสี่เหลี่ยมโล่ง) — ไฟล์อยู่ใน Flutter SDK
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final f = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (f.existsSync()) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await icons.load();
    }
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    currentUserProfile['name'] = _longName;
    currentUserProfile['email'] =
        'somchai.jaidee.mak.mak@example-long-domain.co.th';
  });
  tearDown(() => ChatSocket.instance.disconnect());

  // ---------- เข้าสู่ระบบ / สมัคร ----------
  _responsive('LoginScreen', () => const LoginScreen(), keyboard: true, modes: [
    'normal',
    'unverified'
  ], steps: {
    'กดเข้าสู่ระบบว่าง': (t) =>
        _tap(t, find.byKey(const ValueKey('login-submit'))),
    'ล็อกอิน (ถูกปฏิเสธ)': (t) async {
      await t.enterText(
          find.byKey(const ValueKey('login-identifier')), 'somchai');
      await t.enterText(
          find.byKey(const ValueKey('login-password')), 'Petpaws1!');
      await _tap(t, find.byKey(const ValueKey('login-submit')));
    },
  });
  _responsive('RegisterScreen', () => const RegisterScreen(),
      keyboard: true,
      steps: {
        'กดสมัครว่าง': (t) => _tap(t, find.byType(ElevatedButton)),
        'พิมพ์ยาว': (t) async {
          final fields = find.byType(TextField);
          for (var i = 0; i < fields.evaluate().length; i++) {
            await t.enterText(fields.at(i),
                'ข้อความที่ยาวมากๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆๆ');
          }
          await _tap(t, find.byType(ElevatedButton));
        },
        'เลื่อนลงสุด': _scrollAll,
      });
  _responsive(
      'VerifyEmailScreen',
      () => const VerifyEmailScreen(
          email: 'somchai.jaidee.mak.mak.mak.mak@example-long-domain.co.th',
          identifier: 'somchai'),
      steps: {'กดส่งซ้ำ': (t) => _tap(t, find.byType(ElevatedButton))});
  _responsive('CreateProfileScreen', () => const CreateProfileScreen(),
      keyboard: true,
      steps: {
        'กดบันทึกว่าง': (t) => _tap(t, find.byType(ElevatedButton)),
        'เลื่อนลงสุด': _scrollAll,
        'เลือกจังหวัด': (t) => _tap(t, find.byType(ProvinceField)),
      });

  // ---------- หน้าหลัก + แท็บ ----------
  _responsive('MainScreen', () => const MainScreen(), modes: [
    'normal',
    'empty',
    'fail'
  ], steps: {
    'แท็บถูกใจ': (t) => _tap(t, find.text('ถูกใจ')),
    'แท็บแชท': (t) => _tap(t, find.text('แชท')),
    'แท็บลงประกาศ': (t) async {
      await _tap(t, find.text('ลงประกาศ'));
      await t.pump(const Duration(milliseconds: 300));
      await _scrollAll(t);
    },
    'แท็บโปรไฟล์': (t) async {
      await _tap(t, find.text('โปรไฟล์'));
      await t.pump(const Duration(milliseconds: 300));
      await _scrollAll(t);
    },
  });

  _responsive(
    'DiscoverScreen',
    () => DiscoverScreen(
      dogs: [_dog('d1'), _dog('d2')],
      onLike: (_) {},
      onPass: (_) {},
      onUndoPass: () {},
      canUndo: true,
      likedDogs: const [],
      onToggleFavorite: (_) {},
      speciesFilter: '',
      onSpeciesFilterChanged: (_) {},
    ),
    steps: {
      'กดรายงาน': (t) => _tap(t, find.byIcon(Icons.flag_outlined)),
      'เปิดรายละเอียด': (t) => _tap(t, find.byType(SwipeableCard)),
    },
  );
  _responsive(
    'DiscoverScreen ไม่มีสัตว์',
    () => DiscoverScreen(
      dogs: const [],
      onLike: (_) {},
      onPass: (_) {},
      onUndoPass: () {},
      canUndo: false,
      likedDogs: const [],
      onToggleFavorite: (_) {},
      speciesFilter: 'dog',
      onSpeciesFilterChanged: (_) {},
    ),
  );
  _responsive(
      'FavoritesScreen',
      () => FavoritesScreen(
          likedDogs: [_dog('d1'), _dog('d2'), _dog('d3')],
          onToggleFavorite: (_) {}),
      steps: {
        'เลื่อนลงสุด': _scrollAll,
        'โหมดเลือก': (t) => _tap(t, find.byKey(const ValueKey('fav-select'))),
        'เลือก → เลิกถูกใจ': (t) async {
          await _tap(t, find.byKey(const ValueKey('fav-select')));
          await t.pump(const Duration(milliseconds: 300));
          await _tap(t, find.byKey(const ValueKey('fav-select-all')));
          await t.pump(const Duration(milliseconds: 300));
          await _tap(t, find.byKey(const ValueKey('fav-unlike')));
        },
      });
  _responsive('FavoritesScreen ว่าง',
      () => FavoritesScreen(likedDogs: const [], onToggleFavorite: (_) {}));

  // ---------- แชท ----------
  _responsive('ChatInboxScreen', () => const ChatInboxScreen(), modes: [
    'normal',
    'empty',
    'fail'
  ], steps: {
    'เลื่อนลงสุด': _scrollAll,
    'ค้นหา': (t) async {
      await _tap(t, find.byKey(const ValueKey('inbox-search-toggle')));
      await t.pump(const Duration(milliseconds: 300));
      await t.enterText(find.byKey(const ValueKey('inbox-search')),
          'ไม่มีข้อความนี้แน่นอนในกล่องข้อความทั้งหมดของฉันเลย');
    },
    'โหมดเลือก': (t) async {
      await _tap(t, find.byKey(const ValueKey('inbox-select')));
      await t.pump(const Duration(milliseconds: 300));
      await _tap(t, find.byKey(const ValueKey('inbox-select-all')));
      await t.pump(const Duration(milliseconds: 300));
      await _tap(t, find.byKey(const ValueKey('inbox-delete')));
    },
  });
  _responsive(
    'ChatScreen',
    () => const ChatScreen(
      chatId: 'c1',
      petId: 'p1',
      dogName: 'มะม่วงทองคำขาวนวลน้อย',
      otherUserName: _longName,
      otherUserId: 'u2',
    ),
    keyboard: true,
    modes: ['normal', 'empty', 'fail'],
    steps: {
      'พิมพ์ยาว': (t) async {
        final f = find.byType(TextField);
        if (f.evaluate().isNotEmpty) await t.enterText(f.first, _longStory * 3);
      },
      'แนบไฟล์': (t) =>
          _tap(t, find.byIcon(Icons.add_photo_alternate_outlined)),
      'เมนู ⋮': (t) => _tap(t, find.byType(PopupMenuButton<String>)),
      'เมนู → รายงาน': (t) async {
        await _tap(t, find.byType(PopupMenuButton<String>));
        await t.pump(const Duration(milliseconds: 400));
        await _tap(t, find.text('รายงานผู้ใช้'));
      },
      'เมนู → ลบแชท': (t) async {
        await _tap(t, find.byType(PopupMenuButton<String>));
        await t.pump(const Duration(milliseconds: 400));
        await _tap(t, find.text('ลบแชท'));
      },
      'เมนู → ค้นหา': (t) async {
        await _tap(t, find.byType(PopupMenuButton<String>));
        await t.pump(const Duration(milliseconds: 400));
        await _tap(t, find.text('ค้นหาข้อความ'));
        await t.pump(const Duration(milliseconds: 300));
        final f = find.byType(TextField);
        if (f.evaluate().isNotEmpty) {
          await t.enterText(f.first, 'ไม่มีข้อความนี้');
        }
      },
    },
  );
  _responsive(
    'ChatScreen ห้องใหม่',
    () => const ChatScreen(
        petId: 'p1',
        dogName: 'มะม่วงทองคำขาวนวลน้อย',
        otherUserName: _longName,
        otherUserId: 'u9'),
    keyboard: true,
  );

  // ---------- รายละเอียด / โปรไฟล์ ----------
  _responsive(
      'PetDetailScreen',
      () => PetDetailScreen(
          dog: _dog('d1'),
          isMyPost: false,
          isFavorited: false,
          onToggleFavorite: () {}),
      steps: {'เลื่อนลงสุด': _scrollAll});
  _responsive(
      'PetDetailScreen โพสต์ตัวเอง',
      () => PetDetailScreen(
          dog: _dog('d1'),
          isMyPost: true,
          isFavorited: true,
          onToggleFavorite: () {}),
      steps: {'เลื่อนลงสุด': _scrollAll});
  _responsive('UserProfileScreen',
      () => const UserProfileScreen(uid: 'u2', fallbackName: _longName),
      modes: ['normal', 'empty', 'fail'], steps: {'เลื่อนลงสุด': _scrollAll});
  _responsive('ProfileScreen', () => const ProfileScreen(),
      keyboard: true,
      modes: [
        'normal',
        'fail'
      ],
      steps: {
        'เลื่อนลงสุด': _scrollAll,
        'กดแก้ไข': (t) async {
          await _tap(t, find.byIcon(Icons.edit));
          await t.pump(const Duration(milliseconds: 300));
          await _scrollAll(t);
        },
        'ออกจากระบบ': (t) async {
          await _scrollAll(t);
          await _tap(t, find.textContaining('ออกจากระบบ'));
        },
      });

  // ---------- ลงประกาศ ----------
  _responsive(
    'UploadScreen',
    () => UploadScreen(
      onAddDog: (_) {},
      myPostedDogs: [
        _dog('d1'),
        _dog('d2', status: 'ถูกรับเลี้ยงแล้ว'),
        _dog('d3', status: 'ยกเลิกประกาศ')
      ],
      onDeleteDog: (_) {},
      onChangeStatus: (_, __) {},
      onEditDog: (_) {},
      likedDogs: const [],
      onToggleFavorite: (_) {},
    ),
    keyboard: true,
    steps: {
      'กดโพสต์ว่าง': (t) async {
        await _tap(t, find.text('โพสต์หาบ้าน'));
        await _scrollAll(t);
      },
      'เลื่อนลงสุด': _scrollAll,
      'ลบประกาศ': (t) async {
        await _scrollAll(t);
        await _tap(t, find.byIcon(Icons.delete_outline));
      },
      'เปลี่ยนสถานะ': (t) async {
        await _scrollAll(t);
        await _tap(t, find.byType(DropdownButton<String>));
      },
      'เลือกจังหวัด': (t) => _tap(t, find.byType(ProvinceField)),
    },
  );
  _responsive(
    'UploadScreen ยังไม่มีประกาศ',
    () => UploadScreen(
      onAddDog: (_) {},
      myPostedDogs: const [],
      onDeleteDog: (_) {},
      onChangeStatus: (_, __) {},
      onEditDog: (_) {},
      likedDogs: const [],
      onToggleFavorite: (_) {},
    ),
    steps: {'เลื่อนลงสุด': _scrollAll},
  );
  _responsive(
      'EditDogScreen', () => EditDogScreen(dog: _dog('d1'), onSave: (_) {}),
      keyboard: true,
      steps: {
        'เลื่อนลงสุด': _scrollAll,
        'เลือกจังหวัด': (t) => _tap(t, find.byType(ProvinceField)),
      });
  _responsive(
    'PetPostPreviewScreen',
    () => PetPostPreviewScreen(
        dog: _dog('d1'),
        imageBytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')),
    steps: {'เลื่อนลงสุด': _scrollAll},
  );

  // ---------- แอดมิน ----------
  _responsive('AdminScreen', () => const AdminScreen(), modes: [
    'normal',
    'empty',
    'fail'
  ], steps: {
    'แท็บที่ 2': (t) => _tap(t, find.byType(Tab).last),
    'เลื่อนลงสุด': _scrollAll,
    'เปิดผู้ใช้ที่ถูกรายงาน': (t) => _tap(t, find.textContaining('somchai')),
  });
  _responsive('ForgotPasswordScreen', () => const ForgotPasswordScreen(),
      keyboard: true);
  _responsive('AdminMonitoringScreen', () => const AdminMonitoringScreen(),
      steps: {
        'SQL': (t) => _tap(t, find.text('SQL')),
        'Cache': (t) => _tap(t, find.text('Cache')),
      });
  _responsive('AdminCacheStatsScreen', () => const AdminCacheStatsScreen(),
      modes: [
        'normal',
        'fail'
      ],
      steps: {
        'เลื่อนลงสุด': _scrollAll,
        'กดรีเซ็ต': (t) => _tap(t, find.byIcon(Icons.restart_alt)),
      });
  _responsive(
      'AdminUserProfileScreen',
      () =>
          const AdminUserProfileScreen(userId: 'u2', fallbackTitle: _longName),
      modes: ['normal', 'fail'],
      steps: {'เลื่อนลงสุด': _scrollAll});
  _responsive(
    'AdminUserReportsScreen',
    () => AdminUserReportsScreen(user: ReportedUser.fromJson(_reportedUser())),
    modes: ['normal', 'empty', 'fail'],
    keyboard: true,
    steps: {
      'เลื่อนลงสุด': _scrollAll,
      'กดแบนชั่วคราว': (t) => _tap(t, find.text('แบนชั่วคราว')),
      'กดแบนถาวร': (t) => _tap(t, find.text('แบนถาวร')),
      'กดปัดตก': (t) => _tap(t, find.text('ปัดตก')),
    },
  );

  // ---------- กล่องข้อความ ----------
  _responsive(
      'ReportDialog',
      () => _Open((c) async {
            await showReportDialog(c,
                title: 'รายงานผู้ใช้ $_longName ที่ยาวมากๆ');
          }),
      keyboard: true,
      steps: {
        'เปิดกล่อง': (t) => _tap(t, find.text('เปิด')),
        'เปิดกล่อง → เลือกเหตุผล': (t) async {
          await _tap(t, find.text('เปิด'));
          await t.pump(const Duration(milliseconds: 400));
          await _tap(t, find.byType(RadioListTile<String>));
        },
      });
  _responsive(
    'UpdateGate กล่องอัพเดต',
    () => UpdateGate(
      enabled: true,
      check: () async => const UpdateInfo(
          buildNumber: 99,
          versionName: '1.0.99',
          apkUrl: 'https://example.com/app.apk'),
      child: const Scaffold(body: Center(child: Text('หน้าแรก'))),
    ),
  );
}
