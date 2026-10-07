import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/admin/admin_monitoring_screen.dart';
import 'package:petpaws/screens/admin/admin_screen.dart';

Map<String, dynamic> _perf({bool sqlAvailable = true}) => {
      'since': '2026-10-07T00:00:00Z',
      'scope': 'shared',
      'slowThresholdMs': 500,
      'routes': [
        {
          'route': 'GET /slow',
          'count': 1,
          'avgMs': 900,
          'maxMs': 900,
          'totalMs': 900,
          'slowCount': 1
        },
        {
          'route': 'GET /frequent',
          'count': 42,
          'avgMs': 10,
          'maxMs': 30,
          'totalMs': 420,
          'slowCount': 0
        },
      ],
      'queries': {
        'available': sqlAvailable,
        'reason': sqlAvailable ? null : 'extension unavailable',
        'items': sqlAvailable
            ? [
                {
                  'query': 'SELECT * FROM deck_feed(\$1)',
                  'calls': 8,
                  'totalMs': 1200,
                  'meanMs': 150,
                  'rows': 160
                }
              ]
            : []
      },
    };

Map<String, dynamic> _cache() => {
      'enabled': true,
      'available': true,
      'since': '2026-10-07T00:00:00Z',
      'errors': 0,
      'overall': {'hits': 90, 'misses': 10, 'hitRatio': 0.9},
      'namespaces': [
        {
          'name': 'pet',
          'ttlSeconds': 300,
          'hits': 90,
          'misses': 10,
          'hitRatio': 0.9
        }
      ],
      'redis': {
        'keys': 4,
        'usedMemoryBytes': 1024,
        'maxMemoryBytes': 65536,
        'keyspaceHits': 90,
        'keyspaceMisses': 10,
        'hitRatio': 0.9,
        'evictedKeys': 0,
        'expiredKeys': 1,
        'maxMemoryPolicy': 'volatile-lru',
        'uptimeSeconds': 60
      },
    };

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets(
      'เปิด Monitoring จากแดชบอร์ด และเรียง API ตามจำนวนครั้งแทนเวลารวม',
      (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AdminScreen()));
      await tester.pumpAndSettle();
      expect(find.byTooltip('สถิติ cache'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('admin-monitoring')));
      await tester.pumpAndSettle();
      expect(find.text('Monitoring'), findsOneWidget);
      expect(find.text('43 คำขอ · 2 endpoints'), findsOneWidget);
      final frequent = find.byKey(const ValueKey('api-route-GET /frequent'));
      final slow = find.byKey(const ValueKey('api-route-GET /slow'));
      expect(
          tester.getTopLeft(frequent).dy, lessThan(tester.getTopLeft(slow).dy));
      await tester.tap(find.byKey(const ValueKey('api-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เวลารวมมากที่สุด').last);
      await tester.pumpAndSettle();
      expect(
          tester.getTopLeft(slow).dy, lessThan(tester.getTopLeft(frequent).dy));
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((req) async {
              if (req.url.path == '/admin/perf-stats') return _json(_perf());
              if (req.url.path == '/admin/summary') {
                return _json({'reported': 0, 'temporary': 0, 'permanent': 0});
              }
              return _json(
                  {'items': [], 'total': 0, 'page': 1, 'pageSize': 20});
            }));
  });

  testWidgets(
      'Cache อยู่ใน Monitoring พร้อมข้อมูลกลุ่ม Redis และการเริ่มนับใหม่ครบ',
      (tester) async {
    final calls = <String>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AdminMonitoringScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cache'));
      await tester.pumpAndSettle();
      expect(find.text('ประกาศ (รายตัว)'), findsOneWidget);
      expect(find.text('90.0%'), findsWidgets);
      expect(find.text('volatile-lru'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cache-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'เริ่มนับใหม่'));
      await tester.pumpAndSettle();
      expect(calls, contains('POST /admin/cache-stats/reset'));
      expect(calls.where((c) => c == 'GET /admin/cache-stats').length,
          greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((req) async {
              calls.add('${req.method} ${req.url.path}');
              if (req.url.path == '/admin/perf-stats') return _json(_perf());
              if (req.url.path.endsWith('/reset')) {
                return _json({'success': true});
              }
              return _json(_cache());
            }));
  });

  testWidgets('SQL แสดงจำนวนครั้ง เวลาเฉลี่ย และข้อความ query', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AdminMonitoringScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SQL'));
      await tester.pumpAndSettle();
      expect(find.textContaining('pg_stat_statements'), findsOneWidget);
      expect(find.text('1. 8 ครั้ง · รวม 1.20 s'), findsOneWidget);
      await tester.tap(find.text('1. 8 ครั้ง · รวม 1.20 s'));
      await tester.pumpAndSettle();
      expect(find.text('SELECT * FROM deck_feed(\$1)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((req) async =>
            _json(req.url.path == '/admin/perf-stats' ? _perf() : _cache())));
  });

  testWidgets('SQL ใช้ไม่ได้ยังดู API ได้ และรีเฟรชล้มเหลวยังเก็บข้อมูลเดิม',
      (tester) async {
    var fail = false;
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AdminMonitoringScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SQL'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ยังอ่าน pg_stat_statements ไม่ได้'),
          findsOneWidget);
      await tester.tap(find.text('API'));
      await tester.pumpAndSettle();
      fail = true;
      await tester.tap(find.byKey(const ValueKey('monitoring-refresh')));
      await tester.pumpAndSettle();
      expect(find.textContaining('รีเฟรชไม่สำเร็จ'), findsOneWidget);
      expect(find.byKey(const ValueKey('api-route-GET /frequent')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
        () => MockClient((req) async {
              if (req.url.path != '/admin/perf-stats') return _json(_cache());
              if (fail) {
                return _json({
                  'error': {'code': 'SERVER', 'message': 'เซิร์ฟเวอร์ขัดข้อง'}
                }, 500);
              }
              return _json(_perf(sqlAvailable: false));
            }));
  });
}
