import { describe, expect, it } from 'vitest';
import {
  genderDbToLabel,
  genderLabelToDb,
  statusDbToLabel,
  statusLabelToDb,
  weightDbToLabel,
  weightToDb,
} from './pet-mappers.js';

describe('gender mappers', () => {
  it('แปลงป้ายไทยเป็นค่าใน DB', () => {
    expect(genderLabelToDb('ผู้')).toBe('male');
    expect(genderLabelToDb('เมีย')).toBe('female');
  });

  it.each([[undefined], [''], ['ไม่ระบุ']])('ค่า %j จาก frontend ได้ unknown', (label) => {
    expect(genderLabelToDb(label)).toBe('unknown');
  });

  it('แปลงค่าใน DB กลับเป็นป้ายไทย', () => {
    expect(genderDbToLabel('male')).toBe('ผู้');
    expect(genderDbToLabel('female')).toBe('เมีย');
  });

  it.each([['unknown'], [null], [undefined], ['ค่าแปลกๆ']])(
    'ค่า %j ใน DB ตกกลับเป็น "ผู้"',
    (value) => {
      expect(genderDbToLabel(value)).toBe('ผู้');
    },
  );
});

describe('status mappers', () => {
  it('แปลงป้ายไทยเป็นค่าใน DB ครบทั้ง 3 สถานะ', () => {
    expect(statusLabelToDb('ยังไม่ถูกรับเลี้ยง')).toBe('available');
    expect(statusLabelToDb('ถูกรับเลี้ยงแล้ว')).toBe('adopted');
    expect(statusLabelToDb('ยกเลิกประกาศ')).toBe('cancelled');
  });

  it('ไม่ระบุหรือไม่รู้จักถือเป็น available (ไม่ทำประกาศหายโดยไม่ตั้งใจ)', () => {
    expect(statusLabelToDb(undefined)).toBe('available');
    expect(statusLabelToDb('สถานะแปลก')).toBe('available');
  });

  it('แปลงค่าใน DB กลับเป็นป้ายไทย', () => {
    expect(statusDbToLabel('available')).toBe('ยังไม่ถูกรับเลี้ยง');
    expect(statusDbToLabel('adopted')).toBe('ถูกรับเลี้ยงแล้ว');
    expect(statusDbToLabel('cancelled')).toBe('ยกเลิกประกาศ');
  });

  it('pending ถือเป็นยังเปิดรับ เพราะแอปยังไม่มีปุ่มจอง', () => {
    expect(statusDbToLabel('pending')).toBe('ยังไม่ถูกรับเลี้ยง');
  });

  it.each([[null], [undefined], ['ค่าแปลกๆ']])('ค่า %j ใน DB ตกกลับเป็นยังไม่ถูกรับเลี้ยง', (v) => {
    expect(statusDbToLabel(v)).toBe('ยังไม่ถูกรับเลี้ยง');
  });
});

describe('weightToDb', () => {
  it('แปลงข้อความตัวเลขเป็นตัวเลข', () => {
    expect(weightToDb('3.2')).toBe(3.2);
    expect(weightToDb('5')).toBe(5);
  });

  // ค่าที่แอปส่งมาเมื่อไม่ทราบน้ำหนักคือ "-" ต้องเก็บเป็น NULL ไม่ใช่ 0 หรือ NaN
  it.each([[undefined], [''], ['-'], ['abc'], ['0'], ['-1']])(
    'ค่า %j ที่ไม่ใช่น้ำหนักที่ถูกต้องได้ null',
    (input) => {
      expect(weightToDb(input)).toBeNull();
    },
  );
});

describe('weightDbToLabel', () => {
  it('ไม่มีค่าแสดงเป็น "-"', () => {
    expect(weightDbToLabel(null)).toBe('-');
    expect(weightDbToLabel(undefined)).toBe('-');
  });

  it('แปลงตัวเลขและข้อความตัวเลขเป็นข้อความ', () => {
    expect(weightDbToLabel(3.2)).toBe('3.2');
    // pg คืนคอลัมน์ numeric เป็น string
    expect(weightDbToLabel('5.00')).toBe('5.00');
  });
});
