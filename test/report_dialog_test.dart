import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/services/report_service.dart';
import 'package:petpaws/widgets/report_dialog.dart';

Future<void> _pumpButton(WidgetTester tester, {required String messageId}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => reportWithDialog(
            context,
            title: 'รายงานข้อความนี้',
            send: (reason, detail) =>
                ReportService.instance.reportMessage(messageId, reason: reason, detail: detail),
          ),
          child: const Text('เปิด'),
        ),
      ),
    ),
  ));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('ต้องเลือกเหตุผลก่อนจึงกดส่งได้ และส่ง reportedMessageId + reason + detail', (tester) async {
    final bodies = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await _pumpButton(tester, messageId: 'm1');
      await tester.tap(find.text('เปิด'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextButton>(find.byKey(const ValueKey('report-submit'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('reason-scam')));
      await tester.enterText(find.byKey(const ValueKey('report-detail')), '  ขอเงินมัดจำ  ');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-submit')));
      await tester.pumpAndSettle();

      expect(bodies.single, {'reportedMessageId': 'm1', 'reason': 'scam', 'detail': 'ขอเงินมัดจำ'});
      expect(find.textContaining('ส่งรายงานเรียบร้อยแล้ว'), findsOneWidget);
    }, () => MockClient((req) async {
          bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('{"id":"r1"}', 201, headers: {'content-type': 'application/json'});
        }));
  });

  testWidgets('รายงานซ้ำ (409) แสดงว่ารายงานไปแล้ว', (tester) async {
    await http.runWithClient(() async {
      await _pumpButton(tester, messageId: 'm1');
      await tester.tap(find.text('เปิด'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reason-spam')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-submit')));
      await tester.pumpAndSettle();
      expect(find.text('คุณรายงานเรื่องนี้ไปแล้ว'), findsOneWidget);
    }, () => MockClient((req) async => http.Response(
          jsonEncode({'error': {'code': 'CONFLICT', 'message': 'dup'}}),
          409,
          headers: {'content-type': 'application/json'},
        )));
  });

  testWidgets('กดยกเลิก ไม่ยิง API', (tester) async {
    var calls = 0;
    await http.runWithClient(() async {
      await _pumpButton(tester, messageId: 'm1');
      await tester.tap(find.text('เปิด'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    }, () => MockClient((req) async {
          calls++;
          return http.Response('{}', 200);
        }));
  });
}
