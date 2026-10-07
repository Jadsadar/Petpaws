import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/services/storage_service.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final bytes = Uint8List.fromList([1, 2, 3]);

  test('ขอใบอนุญาตแล้วอัปตรงไป storage — ไฟล์ไม่ผ่าน API', () async {
    final calls = <String>[];
    final url = await http.runWithClient(
      () => StorageService.instance.uploadPetImage(bytes, contentType: 'image/png'),
      () => MockClient((req) async {
        calls.add('${req.method} ${req.url}');
        if (req.url.path == '/media/upload-url') {
          expect(jsonDecode(req.body), {'contentType': 'image/png'});
          return _json({
            'key': 'uploads/a.png',
            'url': 'http://cdn.test/petpaws-media/uploads/a.png',
            'upload': {'url': 'http://storage.test/petpaws-media', 'fields': {'key': 'uploads/a.png'}},
          });
        }
        return http.Response('', 204); // storage ตอบสำเร็จ
      }),
    );

    expect(url, 'http://cdn.test/petpaws-media/uploads/a.png');
    expect(calls.last, 'POST http://storage.test/petpaws-media');
    expect(calls.where((c) => c.contains('/media/upload ')), isEmpty);
  });

  test('backend รุ่นก่อนไม่มี upload-url (404) ถอยไปอัปผ่าน POST /media/upload แบบเดิม', () async {
    final url = await http.runWithClient(
      () => StorageService.instance.uploadPetImage(bytes),
      () => MockClient((req) async {
        if (req.url.path == '/media/upload-url') {
          return _json({'error': {'code': 'NOT_FOUND', 'message': 'Cannot POST'}}, 404);
        }
        expect(req.url.path, '/media/upload');
        return _json({'url': 'http://old.test/petpaws-media/uploads/b.jpg'});
      }),
    );

    expect(url, 'http://old.test/petpaws-media/uploads/b.jpg');
  });
}
