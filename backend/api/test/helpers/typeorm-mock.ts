import { vi } from 'vitest';

const TERMINAL = new Set(['getOne', 'getMany', 'getRawOne', 'getRawMany', 'getCount', 'getExists', 'execute']);

/**
 * QueryBuilder ปลอมสำหรับ unit test — method ต่อกันได้ทุกตัว (where, innerJoin, select ...)
 * ตัวปิดท้าย (getRawOne, execute ...) คืน [result] และ [calls] เก็บว่าถูกเรียกด้วยอะไรบ้าง
 * ความถูกต้องของ SQL ที่ ORM สร้างเทสต์กับ DB จริงใน test/modules-db.e2e-spec.ts
 */
export function fakeQueryBuilder(result: unknown) {
  const calls: Array<[string, unknown[]]> = [];
  const qb: Record<string, unknown> = new Proxy(
    {},
    {
      get: (_t, prop: string) => {
        if (prop === 'calls') return calls;
        if (prop === 'then') return undefined; // ไม่ใช่ Promise
        return (...args: unknown[]) => {
          calls.push([prop, args]);
          return TERMINAL.has(prop) ? Promise.resolve(result) : qb;
        };
      },
    },
  );
  return qb as Record<string, (...args: unknown[]) => unknown> & { calls: Array<[string, unknown[]]> };
}

export const fn = vi.fn;
