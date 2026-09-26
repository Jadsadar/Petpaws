import { describe, expect, it } from 'vitest';
import { homeTypeEnumToLabel, homeTypeLabelToEnum } from './home-type.js';

const pairs: Array<[label: string, value: string]> = [
  ['บ้านเดี่ยว', 'detached_house'],
  ['ทาวน์โฮม/ทาวน์เฮ้าส์', 'townhouse'],
  ['คอนโดมิเนียม', 'condo'],
  ['อพาร์ทเม้นท์/ห้องเช่า', 'apartment'],
];

describe('home-type mappers', () => {
  it.each(pairs)('แปลง "%s" เป็น %s', (label, value) => {
    expect(homeTypeLabelToEnum(label)).toBe(value);
  });

  it.each(pairs)('แปลง %s กลับเป็น "%s"', (label, value) => {
    expect(homeTypeEnumToLabel(value)).toBe(label);
  });

  it('แปลงไปกลับแล้วได้ค่าเดิมทุกตัว', () => {
    for (const [label] of pairs) {
      const value = homeTypeLabelToEnum(label);
      expect(homeTypeEnumToLabel(value)).toBe(label);
    }
  });

  // label ที่ไม่รู้จักต้องได้ null เพื่อให้ users.service ปฏิเสธด้วย INVALID_HOME_TYPE
  it.each([[null], [undefined], [''], ['วิลล่า']])('label %j ที่ไม่รู้จักได้ null', (label) => {
    expect(homeTypeLabelToEnum(label)).toBeNull();
  });

  it.each([[null], [undefined], [''], ['villa']])(
    'enum %j ที่ไม่รู้จักตกกลับเป็น "บ้านเดี่ยว"',
    (value) => {
      expect(homeTypeEnumToLabel(value)).toBe('บ้านเดี่ยว');
    },
  );
});
