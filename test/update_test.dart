import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/services/update_service.dart';
import 'package:petpaws/widgets/update_gate.dart';

http.Response _release(String tag, {List<Map<String, String>>? assets, int status = 200}) => http.Response(
      jsonEncode({
        'tag_name': tag,
        'assets': assets ??
            [
              {'name': 'notes.txt', 'browser_download_url': 'https://github.com/x/notes.txt'},
              {'name': 'app-release.apk', 'browser_download_url': 'https://github.com/x/app-release.apk'},
            ],
      }),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<UpdateInfo?> _check(http.Response Function(http.Request) respond, {int current = 10}) =>
    http.runWithClient(
      () => UpdateService.instance.checkForUpdate(currentBuild: current),
      () => MockClient((req) async => respond(req)),
    );

void main() {
  group('UpdateService.buildFromTag', () {
    test('อ่านเลข build จาก tag ของ release แอป', () {
      expect(UpdateService.buildFromTag('v1.0.25'), 25);
      expect(UpdateService.buildFromTag('1.0.7'), 7);
      expect(UpdateService.buildFromTag(' v2.3.140 '), 140);
    });
    test('tag รูปแบบอื่นไม่ใช่ release ของแอป', () {
      for (final t in ['', 'latest', 'v1.0', 'v1.0.x', 'nightly-5', 'v1.0.2-beta']) {
        expect(UpdateService.buildFromTag(t), isNull, reason: t);
      }
    });
  });

  group('UpdateService.checkForUpdate', () {
    test('release ใหม่กว่า → คืนข้อมูล พร้อมลิงก์ APK (ข้ามไฟล์ที่ไม่ใช่ .apk)', () async {
      final info = await _check((_) => _release('v1.0.25'));
      expect(info, isNotNull);
      expect(info!.buildNumber, 25);
      expect(info.versionName, '1.0.25');
      expect(info.apkUrl, 'https://github.com/x/app-release.apk');
    });

    test('เรียก GitHub API ของ repo เรา', () async {
      Uri? asked;
      await _check((req) {
        asked = req.url;
        return _release('v1.0.11');
      });
      expect(asked.toString(), 'https://api.github.com/repos/Jadsadar/Petpaws/releases/latest');
    });

    test('เลขเท่ากันหรือเก่ากว่า → ไม่มีอัพเดต', () async {
      expect(await _check((_) => _release('v1.0.10')), isNull);
      expect(await _check((_) => _release('v1.0.3')), isNull);
    });

    test('ตรวจไม่ได้ทุกกรณี → null เงียบๆ (ห้ามรบกวนการใช้แอป)', () async {
      expect(await _check((_) => _release('v1.0.25', status: 403)), isNull, reason: 'GitHub จำกัดคำขอ');
      expect(await _check((_) => _release('v1.0.25', status: 404)), isNull);
      expect(await _check((_) => http.Response('ไม่ใช่ json', 200)), isNull);
      expect(await _check((_) => _release('weekly', assets: [])), isNull);
      expect(await _check((_) => _release('v1.0.25', assets: [])), isNull, reason: 'ไม่มีไฟล์ APK');
      expect(
        await _check((_) => _release('v1.0.25', assets: [
              {'name': 'app-release.apk', 'browser_download_url': 'http://insecure.example/app.apk'}
            ])),
        isNull,
        reason: 'ลิงก์ไม่ใช่ https',
      );
    });

    test('เน็ตล้ม (exception) → null', () async {
      final r = await http.runWithClient(
        () => UpdateService.instance.checkForUpdate(currentBuild: 10),
        () => MockClient((_) async => throw Exception('offline')),
      );
      expect(r, isNull);
    });
  });

  group('UpdateGate (กล่อง "Petpaws มีเวอร์ชั่นใหม่แล้ว ...")', () {
    const info = UpdateInfo(buildNumber: 25, versionName: '1.0.25', apkUrl: 'https://github.com/x/app-release.apk');

    Future<void> pump(
      WidgetTester tester, {
      required Future<UpdateInfo?> Function() check,
      Future<bool> Function(Uri)? launch,
      bool enabled = true,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UpdateGate(enabled: enabled, check: check, launch: launch, child: const Text('หน้าแรก')),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('มีเวอร์ชันใหม่ → ขึ้นข้อความตามที่กำหนด พร้อมเลขเวอร์ชัน', (tester) async {
      await pump(tester, check: () async => info);
      expect(find.text('หน้าแรก'), findsOneWidget);
      expect(find.textContaining('Petpaws มีเวอร์ชั่นใหม่แล้ว ต้องการอัพเดตเวอร์ชั่นหรือไม่'), findsOneWidget);
      expect(find.textContaining('1.0.25'), findsOneWidget);
      expect(find.text('ภายหลัง'), findsOneWidget);
      expect(find.text('อัพเดต'), findsOneWidget);
    });

    testWidgets('กด "ภายหลัง" → ปิดกล่อง ไม่เปิดลิงก์', (tester) async {
      final launched = <Uri>[];
      await pump(tester, check: () async => info, launch: (u) async {
        launched.add(u);
        return true;
      });
      await tester.tap(find.byKey(const ValueKey('update-later')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-message')), findsNothing);
      expect(launched, isEmpty);
    });

    testWidgets('กด "อัพเดต" → เปิดลิงก์ดาวน์โหลด APK', (tester) async {
      final launched = <Uri>[];
      await pump(tester, check: () async => info, launch: (u) async {
        launched.add(u);
        return true;
      });
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pumpAndSettle();
      expect(launched.single.toString(), 'https://github.com/x/app-release.apk');
      expect(find.byKey(const ValueKey('update-message')), findsNothing);
    });

    testWidgets('เปิดลิงก์ไม่ได้ → แจ้งผู้ใช้', (tester) async {
      await pump(tester, check: () async => info, launch: (_) async => false);
      await tester.tap(find.byKey(const ValueKey('update-now')));
      await tester.pumpAndSettle();
      expect(find.textContaining('เปิดลิงก์ดาวน์โหลดไม่สำเร็จ'), findsOneWidget);
    });

    testWidgets('ไม่มีเวอร์ชันใหม่ → ไม่ขึ้นอะไร', (tester) async {
      await pump(tester, check: () async => null);
      expect(find.byKey(const ValueKey('update-message')), findsNothing);
      expect(find.text('หน้าแรก'), findsOneWidget);
    });

    testWidgets('ปิดไว้ (เว็บ/แพลตฟอร์มอื่น) → ไม่ตรวจเลย', (tester) async {
      var calls = 0;
      await pump(tester, enabled: false, check: () async {
        calls++;
        return info;
      });
      expect(calls, 0);
      expect(find.byKey(const ValueKey('update-message')), findsNothing);
    });

    testWidgets('ถามครั้งเดียวต่อการเปิดแอป แม้หน้าถูกวาดใหม่', (tester) async {
      var calls = 0;
      Future<UpdateInfo?> check() async {
        calls++;
        return info;
      }

      await pump(tester, check: check);
      await tester.tap(find.byKey(const ValueKey('update-later')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: UpdateGate(enabled: true, check: check, child: const Text('หน้าแรก')))));
      await tester.pumpAndSettle();
      expect(calls, 1);
    });
  });
}
