import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpaws/screens/discover/discover_screen.dart';
import 'package:petpaws/utils/pet_species.dart';
import 'package:petpaws/widgets/species_field.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _dog(String id, String owner, {String species = 'dog'}) => {
      'id': id,
      'ownerId': owner,
      'ownerName': 'เจ้าของ $owner',
      'name': 'น้อง$id',
      'species': species,
      'speciesOther': '',
      'breed': 'พันทาง',
      'province': 'เชียงใหม่',
      'age': '1 ปี',
      'gender': 'ผู้',
      'weight': '5',
      'tags': <String>[],
      'story': '',
      'imageUrl': '',
    };

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('petSpeciesLabel', () {
    test('ชนิดมาตรฐานใช้ป้ายไทย', () {
      expect(petSpeciesLabel({'species': 'fish'}), 'ปลา');
      expect(petSpeciesLabel({'species': 'bird'}), 'นก');
      expect(petSpeciesLabel({}), 'สุนัข'); // ข้อมูลเก่าที่ไม่มี species ถือเป็นสุนัข
    });

    test('อื่น ๆ แสดงข้อความที่เจ้าของระบุ ถ้าไม่ระบุแสดง "อื่น ๆ"', () {
      expect(petSpeciesLabel({'species': 'other', 'speciesOther': 'เต่า'}), 'เต่า');
      expect(petSpeciesLabel({'species': 'other', 'speciesOther': '  '}), 'อื่น ๆ');
    });

    test('มีครบ 6 ชนิดตามที่ backend รับ', () {
      expect(petSpeciesLabels.keys, ['dog', 'cat', 'bird', 'fish', 'rabbit', 'other']);
    });
  });

  testWidgets('SpeciesField: เลือก "อื่น ๆ" แล้วมีช่องระบุ ชนิดอื่นไม่มี', (tester) async {
    var species = 'dog';
    final other = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SpeciesField(
            species: species,
            otherController: other,
            onChanged: (v) => setState(() => species = v),
          ),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('species-other')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('species-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('อื่น ๆ').last);
    await tester.pumpAndSettle();
    expect(species, 'other');
    expect(find.byKey(const ValueKey('species-other')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('species-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปลา').last);
    await tester.pumpAndSettle();
    expect(species, 'fish');
    expect(find.byKey(const ValueKey('species-other')), findsNothing);
  });

  testWidgets('ไอคอนกรองชนิดสัตว์ในหน้าปัดการ์ด: พิมพ์ค้นหาแล้วเลือก "ปลา" ส่งค่า fish กลับ', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: DiscoverScreen(
        dogs: [_dog('1', 'o1')],
        onLike: (_) {},
        onPass: (_) {},
        onUndoPass: () {},
        canUndo: false,
        likedDogs: const [],
        onToggleFavorite: (_) {},
        onSpeciesFilterChanged: picked.add,
      ),
    ));
    // กรองผ่านแถบหมวดด้านบนการ์ด (แทนปุ่มกรองมุมขวาเดิม)
    await tester.tap(find.byKey(const ValueKey('species-chip-fish')));
    await tester.pumpAndSettle();
    expect(picked, ['fish']);
  });

  group('รายงานแล้วถามบล็อก', () {
    Future<List<String>> run(WidgetTester tester, {required bool block, required List<Map<String, dynamic>> dogs, required List<String> passed}) async {
      final calls = <String>[];
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(
          home: DiscoverScreen(
            dogs: dogs,
            onLike: (_) {},
            onPass: (d) => passed.add(d['id'] as String),
            onUndoPass: () {},
            canUndo: false,
            likedDogs: const [],
            onToggleFavorite: (_) {},
            onSpeciesFilterChanged: (_) {},
          ),
        ));
        await tester.tap(find.byTooltip('รายงาน'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('reason-spam')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('report-submit')));
        await tester.pumpAndSettle();
        expect(find.textContaining('บล็อก เจ้าของ o1 ด้วยไหม'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey(block ? 'block-yes' : 'block-no')));
        await tester.pumpAndSettle();
      }, () => MockClient((req) async {
            calls.add('${req.method} ${req.url.path}');
            return _json({'id': 'x', 'success': true}, req.url.path == '/reports' ? 201 : 200);
          }));
      return calls;
    }

    testWidgets('เลือกบล็อก → POST /blocks และถือว่าปัดทิ้ง (รวมประกาศอื่นของเจ้าของเดียวกัน)', (tester) async {
      final passed = <String>[];
      final calls = await run(tester,
          block: true, dogs: [_dog('1', 'o1'), _dog('2', 'o2'), _dog('3', 'o1')], passed: passed);
      expect(calls, containsAll(['POST /reports', 'POST /blocks']));
      expect(passed, ['1', '3']);
    });

    testWidgets('เลือกไม่บล็อก → ไม่ยิง /blocks และไม่ปัดการ์ด', (tester) async {
      final passed = <String>[];
      final calls = await run(tester, block: false, dogs: [_dog('1', 'o1')], passed: passed);
      expect(calls, ['POST /reports']);
      expect(passed, isEmpty);
    });
  });
}
