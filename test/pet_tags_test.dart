import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpaws/utils/pet_tags.dart';

void main() {
  group('ชุดแท็กนิสัย', () {
    test('มี 10 แท็ก และ id ไม่ซ้ำกัน', () {
      expect(petTags, hasLength(10));
      expect(petTags.map((t) => t.id).toSet(), hasLength(10));
    });

    test('เลือกได้สูงสุด 5 แท็ก', () {
      expect(maxTagSelection, 5);
    });

    // pet_tags.dart เขียนไว้ว่า id ต้องตรงกับ slug ในฐานข้อมูลเป๊ะ ๆ
    // ถ้าแก้ฝั่งเดียว แท็กที่ผู้ใช้เลือกจะไม่ตรงกับที่เซิร์ฟเวอร์รู้จัก
    // เทสนี้จึงอ่านไฟล์ migration มาเทียบให้ ทั้ง id คำไทย และลำดับ
    test('ตรงกับข้อมูลตั้งต้นของตาราง traits ใน migration 007', () {
      final sql =
          File('backend/db/migrations/007_search_taxonomy.sql').readAsStringSync();
      final start = sql.indexOf('INSERT INTO traits');
      expect(start, isNonNegative, reason: 'ไม่พบ INSERT INTO traits');
      final block = sql.substring(start, sql.indexOf(';', start));

      final seeded = RegExp(r"\('([a-z_]+)',\s*'([^']+)',\s*(\d+)\)")
          .allMatches(block)
          .map((m) => (m[1]!, m[2]!, int.parse(m[3]!)))
          .toList();

      final inApp = [
        for (var i = 0; i < petTags.length; i++)
          (petTags[i].id, petTags[i].label, i),
      ];
      expect(inApp, seeded);
    });
  });

  group('tagLabel / tagLabels', () {
    test('แปลง id เป็นคำไทย', () {
      expect(tagLabel('chill'), 'สายชิล');
      expect(tagLabels(['chill', 'kid_friendly']), ['สายชิล', 'รักเด็ก']);
    });

    test('id ที่ไม่รู้จักคืนค่า id เดิม แอปไม่ล้ม', () {
      expect(tagLabel('ไม่มีแท็กนี้'), 'ไม่มีแท็กนี้');
    });
  });

  group('petTagIds', () {
    test('อ่านแท็กจากข้อมูลสัตว์เลี้ยง', () {
      expect(petTagIds({'tags': ['chill', 'quiet']}), ['chill', 'quiet']);
    });

    test('ไม่มีฟิลด์ tags ได้ลิสต์ว่าง', () {
      expect(petTagIds({'name': 'มอมแมม'}), isEmpty);
    });

    test('แปลงสมาชิกที่ไม่ใช่ข้อความเป็นข้อความ', () {
      expect(petTagIds({'tags': [1, 'chill']}), ['1', 'chill']);
    });
  });

  group('tagMatchCount / matchedTagLabels', () {
    test('นับเฉพาะแท็กที่ตรงกันทั้งสองฝั่ง', () {
      expect(tagMatchCount(['chill', 'quiet', 'tidy'], ['quiet', 'tidy', 'foodie']), 2);
    });

    test('ไม่ตรงกันเลยได้ 0', () {
      expect(tagMatchCount(['chill'], ['energetic']), 0);
      expect(tagMatchCount([], ['energetic']), 0);
    });

    test('แสดงแท็กที่ตรงกันเป็นคำไทยตามลำดับของผู้ใช้', () {
      final pet = {'tags': ['quiet', 'chill', 'foodie']};
      expect(matchedTagLabels(['chill', 'quiet'], pet), ['สายชิล', 'รักความสงบ']);
    });
  });
}
