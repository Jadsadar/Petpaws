import 'package:flutter_test/flutter_test.dart';
import 'package:petpaws/utils/password_policy.dart';

// เคสชุดเดียวกับ backend/api/src/auth/password-policy.spec.ts ตั้งใจให้ตรงกัน
// เพราะกฎฝั่งแอปกับฝั่ง server ต้องเป็นกฎเดียวกัน ถ้าแก้ฝั่งหนึ่งต้องแก้อีกฝั่งด้วย
void main() {
  group('PasswordPolicy.firstError', () {
    test('คืน null เมื่อผ่านทุกกฎ', () {
      expect(
        PasswordPolicy.firstError('Petpaws#Test99',
            username: 'somchai', email: 'a@b.com'),
        isNull,
      );
    });

    const cases = <String, List<String>>{
      'สั้นกว่า 8 ตัว': ['Ab1!xyz', 'รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร'],
      'ไม่มีตัวพิมพ์ใหญ่': [
        'petpaws#test99',
        'รหัสผ่านต้องมีตัวพิมพ์ใหญ่ A-Z อย่างน้อย 1 ตัว'
      ],
      'ไม่มีตัวพิมพ์เล็ก': [
        'PETPAWS#TEST99',
        'รหัสผ่านต้องมีตัวพิมพ์เล็ก a-z อย่างน้อย 1 ตัว'
      ],
      'ไม่มีตัวเลข': [
        'Petpaws#Testing',
        'รหัสผ่านต้องมีตัวเลข 0-9 อย่างน้อย 1 ตัว'
      ],
      'ไม่มีอักขระพิเศษ': [
        'PetpawsTest99',
        'รหัสผ่านต้องมีอักขระพิเศษ เช่น ! @ # \$ % อย่างน้อย 1 ตัว'
      ],
      'มีช่องว่าง': ['Pet paws#99', 'รหัสผ่านต้องไม่มีช่องว่าง'],
    };
    cases.forEach((name, pair) {
      test('ปฏิเสธรหัสผ่านที่$name', () {
        expect(PasswordPolicy.firstError(pair[0]), pair[1]);
      });
    });

    test('คืนข้อผิดพลาดของกฎแรกที่ไม่ผ่านเท่านั้น', () {
      expect(PasswordPolicy.firstError('abc'),
          'รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร');
    });

    group('กฎห้ามมีตัวตนของผู้ใช้อยู่ในรหัสผ่าน', () {
      const identityError = 'รหัสผ่านต้องไม่มีชื่อผู้ใช้หรือชื่ออีเมลอยู่ข้างใน';

      test('ปฏิเสธเมื่อมีชื่อผู้ใช้อยู่ข้างใน', () {
        expect(
            PasswordPolicy.firstError('Somchai#2026', username: 'somchai'),
            identityError);
      });

      test('ไม่สนตัวพิมพ์เล็กใหญ่', () {
        expect(
            PasswordPolicy.firstError('SOMCHAI#2026a', username: 'SomChai'),
            identityError);
      });

      test('ปฏิเสธเมื่อมีส่วนหน้า @ ของอีเมลอยู่ข้างใน', () {
        expect(
            PasswordPolicy.firstError('Kuljira6869#x',
                email: 'kuljira6869@gmail.com'),
            identityError);
      });

      test('ไม่นับชื่อผู้ใช้ที่สั้นกว่า 3 ตัว', () {
        expect(PasswordPolicy.firstError('Xab#12345', username: 'ab'), isNull);
      });
    });
  });

  group('PasswordPolicy.check / strength', () {
    test('มี 7 เงื่อนไข และความยาวขั้นต่ำคือ 8', () {
      expect(PasswordPolicy.minLength, 8);
      expect(PasswordPolicy.check('x'), hasLength(7));
    });

    test('รหัสผ่านว่างได้ความแข็งแรง 0', () {
      expect(PasswordPolicy.strength(''), 0);
    });

    test('ผ่านครบทุกข้อได้ความแข็งแรง 1', () {
      expect(PasswordPolicy.strength('Petpaws#Test99'), 1.0);
    });

    test('ผ่านบางข้อได้สัดส่วนตามจำนวนข้อที่ผ่าน', () {
      // "abc" ผ่านแค่ ตัวพิมพ์เล็ก / ไม่มีช่องว่าง / ไม่มีชื่อผู้ใช้ = 3 จาก 7 ข้อ
      expect(PasswordPolicy.strength('abc'), closeTo(3 / 7, 1e-9));
    });
  });
}
