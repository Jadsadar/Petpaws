import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/admin/admin_cache_stats_screen.dart';
import 'package:petpaws/screens/admin/admin_cache_stats_widgets.dart';
import 'package:petpaws/services/admin_service.dart';
import 'package:petpaws/theme/app_theme.dart';

/// รูปทรงเดียวกับ CacheService.stats() ใน backend/api/src/cache/cache.service.ts
Map<String, dynamic> _stats({bool enabled = true, bool available = true, int petHits = 90}) => {
      'enabled': enabled,
      'available': available,
      'since': '2026-10-01T00:00:00.000Z',
      'errors': 0,
      'overall': {'hits': petHits + 6, 'misses': 10, 'hitRatio': (petHits + 6) / (petHits + 16)},
      'namespaces': [
        {'name': 'traits', 'ttlSeconds': 3600, 'hits': 6, 'misses': 0, 'hitRatio': 1},
        {'name': 'pet', 'ttlSeconds': 300, 'hits': petHits, 'misses': 10, 'hitRatio': petHits / (petHits + 10)},
        {'name': 'userPublic', 'ttlSeconds': 300, 'hits': 0, 'misses': 0, 'hitRatio': null},
      ],
      'redis': available
          ? {
              'keys': 42,
              'keyspaceHits': 300,
              'keyspaceMisses': 100,
              'hitRatio': 0.75,
              'evictedKeys': 3,
              'expiredKeys': 9,
              'usedMemoryBytes': 2 * 1024 * 1024,
              'maxMemoryBytes': 64 * 1024 * 1024,
              'maxMemoryPolicy': 'volatile-lru',
              'uptimeSeconds': 7200,
            }
          : null,
    };

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('CacheStats.fromJson', () {
    test('อ่านตัวนับแยกกลุ่ม รวม และของ Redis', () {
      final s = CacheStats.fromJson(_stats());
      expect(s.enabled, isTrue);
      expect(s.overall.hits, 96);
      expect(s.namespaces, hasLength(3));
      expect(s.namespaces[1].counter.hitRatio, closeTo(0.9, 1e-9));
      expect(s.namespaces[2].counter.hitRatio, isNull);
      expect(s.redis!.memoryUsage, closeTo(2 / 64, 1e-9));
      expect(s.redis!.counter.misses, 100);
    });

    test('Redis ต่อไม่ได้ = redis เป็น null', () {
      final s = CacheStats.fromJson(_stats(available: false));
      expect(s.available, isFalse);
      expect(s.redis, isNull);
    });
  });

  group('hitRatioColor', () {
    test('ตัดสีตามเกณฑ์ 80% / 50% เมื่อมีตัวอย่างพอ', () {
      expect(hitRatioColor(0.95, 100), AppColors.success);
      expect(hitRatioColor(0.6, 100), AppColors.warning);
      expect(hitRatioColor(0.2, 100), AppColors.danger);
    });

    test('ตัวอย่างน้อยหรือยังไม่มีข้อมูล = สีเทา ไม่ใช่แดง', () {
      expect(hitRatioColor(0.0, 3), isNot(AppColors.danger));
      expect(hitRatioColor(null, 0), isNot(AppColors.danger));
    });
  });

  testWidgets('แสดง hit ratio รวม/แยกกลุ่ม และรีเซ็ตแล้วโหลดใหม่', (tester) async {
    final calls = <String>[];
    var reset = false;
    Future<http.Response> handle(http.Request req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path == '/admin/cache-stats/reset') {
        reset = true;
        return http.Response(jsonEncode({'success': true}), 200, headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode(_stats(petHits: reset ? 0 : 90)), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AdminCacheStatsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('90.6%'), findsOneWidget); // รวม 96 / 106
      expect(find.text('ประกาศ (รายตัว)'), findsOneWidget);
      expect(find.text('90.0%'), findsOneWidget);
      expect(find.text('volatile-lru'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('cache-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'เริ่มนับใหม่'));
      await tester.pumpAndSettle();

      expect(calls, contains('POST /admin/cache-stats/reset'));
      expect(calls.where((c) => c == 'GET /admin/cache-stats'), hasLength(2));
    }, () => MockClient(handle));
  });

  testWidgets('ปิด cache อยู่ แสดงแถบเตือนและปิดปุ่มรีเซ็ต', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AdminCacheStatsScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('ปิด cache อยู่'), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const ValueKey('cache-reset'))).onPressed, isNull);
    },
        () => MockClient((_) async => http.Response(jsonEncode(_stats(enabled: false, available: false)), 200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
  });
}
