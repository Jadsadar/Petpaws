import { describe, expect, it } from 'vitest';
import { firstPasswordError } from './password-policy.js';

const nobody = {};

describe('firstPasswordError', () => {
  it('คืน null เมื่อรหัสผ่านผ่านทุกกฎ', () => {
    expect(
      firstPasswordError('Petpaws#Test99', { username: 'somchai', email: 'a@b.com' }),
    ).toBeNull();
  });

  it.each([
    ['สั้นกว่า 8 ตัว', 'Ab1!xyz', 'รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร'],
    ['ไม่มีตัวพิมพ์ใหญ่', 'petpaws#test99', 'รหัสผ่านต้องมีตัวพิมพ์ใหญ่ A-Z อย่างน้อย 1 ตัว'],
    ['ไม่มีตัวพิมพ์เล็ก', 'PETPAWS#TEST99', 'รหัสผ่านต้องมีตัวพิมพ์เล็ก a-z อย่างน้อย 1 ตัว'],
    ['ไม่มีตัวเลข', 'Petpaws#Testing', 'รหัสผ่านต้องมีตัวเลข 0-9 อย่างน้อย 1 ตัว'],
    [
      'ไม่มีอักขระพิเศษ',
      'PetpawsTest99',
      'รหัสผ่านต้องมีอักขระพิเศษ เช่น ! @ # $ % อย่างน้อย 1 ตัว',
    ],
    ['มีช่องว่าง', 'Pet paws#99', 'รหัสผ่านต้องไม่มีช่องว่าง'],
  ])('ปฏิเสธรหัสผ่านที่%s', (_label, password, expected) => {
    expect(firstPasswordError(password, nobody)).toBe(expected);
  });

  it('คืนข้อผิดพลาดของกฎแรกที่ไม่ผ่านเท่านั้น (ตามลำดับกฎ)', () => {
    // ทั้งสั้น ไม่มีตัวใหญ่ ไม่มีเลข ไม่มีอักขระพิเศษ — ต้องได้ข้อความเรื่องความยาวก่อน
    expect(firstPasswordError('abc', nobody)).toBe('รหัสผ่านต้องยาวอย่างน้อย 8 ตัวอักษร');
  });

  describe('กฎห้ามมีตัวตนของผู้ใช้อยู่ในรหัสผ่าน', () => {
    const identityError = 'รหัสผ่านต้องไม่มีชื่อผู้ใช้หรือชื่ออีเมลอยู่ข้างใน';

    it('ปฏิเสธเมื่อมีชื่อผู้ใช้อยู่ข้างใน', () => {
      expect(firstPasswordError('Somchai#2026', { username: 'somchai' })).toBe(identityError);
    });

    it('ไม่สนตัวพิมพ์เล็กใหญ่ของชื่อผู้ใช้', () => {
      expect(firstPasswordError('SOMCHAI#2026a', { username: 'SomChai' })).toBe(identityError);
    });

    it('ปฏิเสธเมื่อมีส่วนหน้า @ ของอีเมลอยู่ข้างใน', () => {
      expect(firstPasswordError('Kuljira6869#x', { email: 'kuljira6869@gmail.com' })).toBe(
        identityError,
      );
    });

    it('ไม่นับชื่อผู้ใช้ที่สั้นกว่า 3 ตัว (กันปฏิเสธพร่ำเพรื่อ)', () => {
      expect(firstPasswordError('Xab#12345', { username: 'ab' })).toBeNull();
    });
  });
});
