import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:petpaws/services/chat_media_service.dart';
import 'package:petpaws/shared/api_client.dart';

void main() {
  group('prepareChatImage', () {
    test('JPEG ที่ไม่ต้องหมุน ส่งไฟล์เดิม (ไม่ encode ซ้ำให้คุณภาพตก)', () {
      final bytes = img.encodeJpg(img.Image(width: 1600, height: 1200));

      final out = prepareChatImage(bytes);

      expect(out.type, 'image');
      expect(out.contentType, 'image/jpeg');
      expect(out.bytes, same(bytes));
      expect((out.width, out.height), (1600, 1200));
    });

    test('thumbnail ด้านยาวสุด 400px คงสัดส่วน และเป็น JPEG เสมอ (แม้ต้นฉบับเป็น PNG)', () {
      final out = prepareChatImage(img.encodePng(img.Image(width: 800, height: 1600)));

      expect(out.contentType, 'image/png');
      final thumb = img.decodeImage(out.thumbnail)!;
      expect(img.findFormatForData(out.thumbnail), img.ImageFormat.jpg);
      expect((thumb.width, thumb.height), (200, 400));
    });

    test('รูปเล็กกว่า 400px ไม่ถูกขยาย', () {
      final out = prepareChatImage(img.encodeJpg(img.Image(width: 120, height: 80)));

      final thumb = img.decodeImage(out.thumbnail)!;
      expect((thumb.width, thumb.height), (120, 80));
    });

    test('รูปจากกล้องที่มี EXIF ให้หมุน 90° ถูกหมุนจริง ขนาดที่ส่งเป็นแนวตั้ง', () {
      final landscape = img.Image(width: 400, height: 300);
      landscape.exif.imageIfd.orientation = 6; // หมุนตามเข็ม 90°
      final bytes = img.encodeJpg(landscape);

      final out = prepareChatImage(bytes);

      expect((out.width, out.height), (300, 400));
      expect(out.bytes, isNot(same(bytes)));
      final sent = img.decodeImage(out.bytes)!;
      expect((sent.width, sent.height), (300, 400));
      expect(sent.exif.imageIfd.orientation ?? 1, 1);
    });

    test('ไฟล์ที่ไม่ใช่รูป โยน error ที่มีข้อความให้ผู้ใช้', () {
      expect(
        () => prepareChatImage(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(predicate((e) => e.toString() == 'อ่านไฟล์รูปนี้ไม่ได้')),
      );
    });
  });
}
