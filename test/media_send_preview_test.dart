import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpaws/screens/chat/media_send_preview_screen.dart';
import 'package:petpaws/services/chat_media_service.dart';

// PNG 1x1 จริง ให้ Image.memory ถอดรหัสได้
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

PreparedMedia _img(int w) => PreparedMedia(
    type: 'image', bytes: _png, contentType: 'image/png', thumbnail: _png, width: w, height: 1);

/// เปิดหน้าตรวจก่อนส่ง แล้วคืนค่าที่หน้านั้นส่งกลับตอนปิด
Future<Future<List<PreparedMedia>?> Function()> _open(
    WidgetTester tester, List<PreparedMedia> media) async {
  List<PreparedMedia>? result;
  var done = false;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await Navigator.push<List<PreparedMedia>>(
              context, MaterialPageRoute(builder: (_) => MediaSendPreviewScreen(media: media)));
          done = true;
        },
        child: const Text('open'),
      ),
    ),
  ));
  return () async {
    expect(done, isTrue, reason: 'หน้าตรวจก่อนส่งต้องปิดแล้ว');
    return result;
  };
}

void main() {
  testWidgets('ตรวจก่อนส่ง: กด ✕ เอารูปที่ 2 ออก แล้วกดส่ง → ได้รูปที่เหลือตามลำดับ', (tester) async {
    final media = [_img(1), _img(2), _img(3)];
    final result = await _open(tester, media);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('ส่ง (3 รายการ)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('media-preview-remove-1')));
    await tester.pumpAndSettle();
    expect(find.text('ส่ง (2 รายการ)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('media-preview-send')));
    await tester.pumpAndSettle();
    final sent = await result();
    expect(sent!.map((m) => m.width), [1, 3]);
  });

  testWidgets('ตรวจก่อนส่ง: กดยกเลิก → ไม่ส่งอะไร', (tester) async {
    final result = await _open(tester, [_img(1)]);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('media-preview-cancel')));
    await tester.pumpAndSettle();
    expect(await result(), isNull);
  });

  testWidgets('ตรวจก่อนส่ง: เอาออกจนหมด → ปิดหน้าโดยไม่ส่ง', (tester) async {
    final result = await _open(tester, [_img(1)]);
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('media-preview-remove-0')));
    await tester.pumpAndSettle();
    expect(await result(), isNull);
  });
}
