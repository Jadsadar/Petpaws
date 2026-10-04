import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/upload/pet_post_preview_screen.dart';
import 'package:petpaws/screens/upload/upload_screen.dart';

// PNG 1x1 โปร่งใส ใช้เป็นรูปจำลอง
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

const _dog = {
  'name': 'มะม่วง',
  'species': 'other',
  'speciesOther': 'เต่า',
  'breed': 'พันทาง',
  'province': 'เชียงใหม่',
  'age': '1 ปี',
  'gender': 'เมีย',
  'weight': '2',
  'tags': ['chill', 'foodie'],
  'story': 'รอบ้านใหม่',
};

Future<bool?> _open(WidgetTester tester, String tapKey) async {
  bool? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => PetPostPreviewScreen(dog: _dog, imageBytes: _png)),
        ),
        child: const Text('เปิด'),
      ),
    ),
  ));
  await tester.tap(find.text('เปิด'));
  await tester.pumpAndSettle();
  expect(find.text('มะม่วง'), findsOneWidget);
  expect(find.text('เต่า'), findsOneWidget, reason: 'ชนิด "อื่น ๆ" แสดงข้อความที่ระบุ');
  expect(find.text('สายชิล'), findsOneWidget);
  expect(find.text('รอบ้านใหม่'), findsOneWidget);
  await tester.tap(find.byKey(ValueKey(tapKey)));
  await tester.pumpAndSettle();
  return result;
}

Widget _upload() => MaterialApp(
      home: UploadScreen(
        onAddDog: (_) {},
        myPostedDogs: const [],
        onDeleteDog: (_) {},
        onChangeStatus: (_, __) {},
        onEditDog: (_) {},
        likedDogs: const [],
        onToggleFavorite: (_) {},
      ),
    );

http.Response _me(String province) => http.Response(jsonEncode({'province': province}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('จังหวัดเริ่มต้นของประกาศ = จังหวัดในโปรไฟล์เจ้าของ', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_upload());
      await tester.pumpAndSettle();
      expect(find.text('เชียงใหม่'), findsWidgets);
      expect(find.text('กรุงเทพมหานคร'), findsNothing);
    }, () => MockClient((_) async => _me('เชียงใหม่')));
  });

  testWidgets('โหลดโปรไฟล์ไม่ได้ → ใช้ค่าเริ่มต้นเดิม (กรุงเทพฯ)', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_upload());
      await tester.pumpAndSettle();
      expect(find.text('กรุงเทพมหานคร'), findsWidgets);
    }, () => MockClient((_) async => http.Response('{}', 500)));
  });
  testWidgets('พรีวิว: กดยืนยันโพสต์ → คืนค่า true', (tester) async {
    expect(await _open(tester, 'preview-confirm'), isTrue);
  });

  testWidgets('พรีวิว: กดแก้ไข → คืนค่า false (ไม่โพสต์)', (tester) async {
    expect(await _open(tester, 'preview-edit'), isFalse);
  });

  testWidgets('หน้าลงประกาศ: รูปภาพอยู่บนสุด เหนือช่องชื่อ และเพศอยู่เหนืออายุ', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_upload());
      await tester.pumpAndSettle();
      final imageY = tester.getTopLeft(find.text('รูปภาพ *')).dy;
      final nameY = tester.getTopLeft(find.text('ชื่อสัตว์เลี้ยง *')).dy;
      final genderY = tester.getTopLeft(find.text('เพศ')).dy;
      final ageY = tester.getTopLeft(find.text('อายุ (ปี) *')).dy;
      expect(imageY, lessThan(nameY));
      expect(genderY, lessThan(ageY));
    }, () => MockClient((_) async => _me('กรุงเทพมหานคร')));
  });
}
