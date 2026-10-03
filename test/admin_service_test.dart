import 'package:flutter_test/flutter_test.dart';
import 'package:petpaws/services/admin_service.dart';
import 'package:petpaws/utils/report_reasons.dart';

void main() {
  group('AdminPage', () {
    Map<String, dynamic> page(int total, int p) => {
          'items': [
            {'id': 'u', 'username': 'n'}
          ],
          'total': total,
          'page': p,
          'pageSize': 20,
        };

    test('คำนวณจำนวนหน้าและปุ่มก่อนหน้า/ถัดไป', () {
      final mid = AdminPage.fromJson(page(45, 2), ReportedUser.fromJson);
      expect(mid.totalPages, 3);
      expect(mid.hasPrevious, isTrue);
      expect(mid.hasNext, isTrue);
      final last = AdminPage.fromJson(page(45, 3), ReportedUser.fromJson);
      expect(last.hasNext, isFalse);
      final first = AdminPage.fromJson(page(20, 1), ReportedUser.fromJson);
      expect(first.totalPages, 1);
      expect(first.hasPrevious, isFalse);
      expect(first.hasNext, isFalse);
    });

    test('รายการว่างยังมี 1 หน้า', () {
      final p = AdminPage.fromJson({'items': [], 'total': 0, 'page': 1, 'pageSize': 20}, ReportedUser.fromJson);
      expect(p.totalPages, 1);
      expect(p.items, isEmpty);
    });
  });

  group('UserReport กับรูปและข้อความ', () {
    test('รายงานประกาศ: อ่านรายละเอียดประกาศและรูป (ใช้ thumb เป็นภาพย่อ)', () {
      final r = UserReport.fromJson({
        'id': 'r1',
        'reason': 'scam',
        'createdAt': '2026-10-01T10:00:00.000Z',
        'reporter': {'id': 'x', 'username': 'rep', 'displayName': ''},
        'targetType': 'pet',
        'pet': {
          'id': 'p1',
          'name': 'มะม่วง',
          'status': 'adopted',
          'deleted': false,
          'photos': [
            {'url': 'http://x/1.jpg', 'thumbUrl': 'http://x/1t.jpg'},
            {'url': 'http://x/2.jpg', 'thumbUrl': null},
          ],
        },
      });
      expect(r.pet!.photos, hasLength(2));
      expect(r.pet!.photos[0].previewUrl, 'http://x/1t.jpg');
      expect(r.pet!.photos[1].previewUrl, 'http://x/2.jpg');
      expect(r.pet!.statusLabel, 'ได้บ้านแล้ว');
    });

    test('รายงานข้อความ: ได้เฉพาะข้อความที่ถูกรายงานกับเวลาที่ส่ง', () {
      final r = UserReport.fromJson({
        'id': 'r2',
        'reason': 'spam',
        'createdAt': '2026-10-01T10:00:00.000Z',
        'reporter': {'id': 'x', 'username': 'rep'},
        'targetType': 'message',
        'messageBody': 'ข้อความโฆษณา',
        'messageCreatedAt': '2026-10-01T09:00:00.000Z',
      });
      expect(r.messageBody, 'ข้อความโฆษณา');
      expect(r.messageCreatedAt, isNotNull);
      expect(r.pet, isNull);
    });
  });

  group('AdminProfile.fromJson', () {
    test('อ่านข้อมูลบัญชีและประกาศทั้งหมด รวมที่ถูกลบ', () {
      final p = AdminProfile.fromJson({
        'id': 'u1',
        'username': 'somchai',
        'email': 's@x.com',
        'displayName': '',
        'pendingReportCount': 2,
        'pets': [
          {'id': 'p1', 'name': 'A', 'deleted': true, 'photos': []},
        ],
      });
      expect(p.title, 'somchai');
      expect(p.pendingReportCount, 2);
      expect(p.pets.single.statusLabel, 'ถูกลบ');
    });
  });

  group('ReportedUser.fromJson', () {
    test('แปลงข้อมูลที่ backend ส่งมาครบทุกฟิลด์', () {
      final u = ReportedUser.fromJson({
        'id': 'u1',
        'username': 'somchai',
        'displayName': 'สมชาย',
        'avatarUrl': 'http://x/a.png',
        'reportCount': 4,
        'lastReportedAt': '2026-10-01T10:00:00.000Z',
        'isSuspended': false,
        'suspendedUntil': null,
      });
      expect(u.id, 'u1');
      expect(u.reportCount, 4);
      expect(u.title, 'สมชาย');
      expect(u.lastReportedAt, isNotNull);
    });

    test('ไม่มี displayName ให้ใช้ username เป็นชื่อแสดง และ avatar ว่างได้', () {
      final u = ReportedUser.fromJson({
        'id': 'u2',
        'username': 'nick',
        'displayName': '',
        'avatarUrl': '',
        'reportCount': 1,
        'lastReportedAt': null,
      });
      expect(u.title, 'nick');
      expect(u.avatarUrl, '');
      expect(u.lastReportedAt, isNull);
    });
  });

  group('BannedUser.fromJson', () {
    test('แบนถาวรไม่มีวันหมดอายุ', () {
      final u = BannedUser.fromJson({
        'id': 'u3',
        'username': 'bad',
        'displayName': 'คนไม่ดี',
        'avatarUrl': '',
        'suspendedUntil': null,
        'permanent': true,
      });
      expect(u.permanent, isTrue);
      expect(u.suspendedUntil, isNull);
    });

    test('แบนชั่วคราวมีวันหมดอายุ', () {
      final u = BannedUser.fromJson({
        'id': 'u4',
        'username': 'temp',
        'displayName': '',
        'avatarUrl': '',
        'suspendedUntil': '2026-11-01T00:00:00.000Z',
        'permanent': false,
      });
      expect(u.permanent, isFalse);
      expect(u.suspendedUntil, isNotNull);
    });
  });

  group('UserReport.fromJson', () {
    test('รายงานประกาศสัตว์: เก็บชื่อสัตว์และชื่อผู้รายงาน', () {
      final r = UserReport.fromJson({
        'id': 'r1',
        'reason': 'scam',
        'detail': 'เรียกเงินค่ามัดจำ',
        'createdAt': '2026-10-01T10:00:00.000Z',
        'reporter': {'id': 'x', 'username': 'rep', 'displayName': 'ผู้รายงาน'},
        'targetType': 'pet',
        'petId': 'p1',
        'petName': 'มะม่วง',
        'messageId': null,
        'messageBody': null,
      });
      expect(r.targetType, 'pet');
      expect(r.petName, 'มะม่วง');
      expect(r.reporterName, 'ผู้รายงาน');
      expect(r.detail, 'เรียกเงินค่ามัดจำ');
    });

    test('ผู้รายงานไม่มี displayName ใช้ username แทน และ detail ว่างได้', () {
      final r = UserReport.fromJson({
        'id': 'r2',
        'reason': 'other',
        'detail': null,
        'createdAt': '2026-10-01T10:00:00.000Z',
        'reporter': {'id': 'x', 'username': 'rep2', 'displayName': ''},
        'targetType': 'message',
        'messageBody': 'ข้อความทดสอบ',
      });
      expect(r.reporterName, 'rep2');
      expect(r.detail, '');
      expect(r.messageBody, 'ข้อความทดสอบ');
    });
  });

  group('reportReasonLabel', () {
    test('ทุกเหตุผลที่ backend รับ (CreateReportDto) มีป้ายภาษาไทย', () {
      const backendReasons = ['fake_info', 'spam', 'inappropriate', 'scam', 'animal_abuse', 'other'];
      for (final reason in backendReasons) {
        expect(reportReasonLabels.containsKey(reason), isTrue, reason: 'ขาดป้ายของ $reason');
      }
    });

    test('เหตุผลที่ไม่รู้จักแสดงค่าเดิม ไม่ล้ม', () {
      expect(reportReasonLabel('something_new'), 'something_new');
    });
  });
}
