import { describe, expect, it, vi } from 'vitest';
import type { Pool } from 'pg';
import { MetricsService, SLOW_REQUEST_MS } from './metrics.service.js';

// ไม่มี Redis = นับในหน่วยความจำ (logic รวมผลแบบเดียวกับตอนอ่านจาก Redis)
// การนับผ่าน Redis จริงอยู่ใน test/perf-stats.e2e-spec.ts
const pool = (rows: unknown[] | Error) =>
  ({
    query: vi.fn(async () => {
      if (rows instanceof Error) throw rows;
      return { rows };
    }),
  }) as unknown as Pool;

describe('MetricsService', () => {
  it('รวมเวลาต่อ route: จำนวน, เฉลี่ย, สูงสุด, จำนวนครั้งที่ช้า — เรียงตามจำนวนคำขอมากสุดก่อน', async () => {
    const m = new MetricsService(null, pool([]));
    m.record('GET /pets/deck', 100);
    m.record('GET /pets/deck', SLOW_REQUEST_MS + 100);
    m.record('GET /chats', 50);

    const { routes } = await m.stats();

    expect(routes.map((r) => r.route)).toEqual(['GET /pets/deck', 'GET /chats']);
    expect(routes[0]).toMatchObject({ count: 2, avgMs: 350, maxMs: 600, slowCount: 1 });
  });

  it('endpoint ที่ถูกเรียกบ่อยอยู่ก่อน endpoint ช้า และไม่นับการเปิด Monitoring เอง', async () => {
    const m = new MetricsService(null, pool([]));
    m.record('GET /slow', 900);
    m.record('GET /frequent', 10);
    m.record('GET /frequent', 20);
    m.record('GET /admin/perf-stats', 10);
    m.record('POST /admin/cache-stats/reset', 10);
    const stats = await m.stats();
    expect(stats.routes.map((r) => r.route)).toEqual(['GET /frequent', 'GET /slow']);
    expect(stats).toMatchObject({ scope: 'instance', since: expect.any(String) });
  });

  it('อ่านเวลาเริ่มนับจาก Redis รวมทุก API โดยไม่ตีความ metadata เป็น route', async () => {
    const redis = { hgetall: vi.fn().mockResolvedValue({
      since: '2026-10-07T00:00:00.000Z',
      'GET /pets/deck|count': '42', 'GET /pets/deck|totalMs': '420', 'GET /pets/deck|maxMs': '20',
    }) };
    const m = new MetricsService(redis as never, pool([]));
    expect(await m.stats()).toMatchObject({
      scope: 'shared', since: '2026-10-07T00:00:00.000Z',
      routes: [{ route: 'GET /pets/deck', count: 42, avgMs: 10, maxMs: 20, totalMs: 420, slowCount: 0 }],
    });
  });

  it('แปลงผล pg_stat_statements เป็นตัวเลข (pg คืน bigint เป็น string)', async () => {
    const m = new MetricsService(
      null,
      pool([{ query: 'SELECT * FROM deck_feed($1)', calls: '12', total_ms: 340.6, mean_ms: 28.383, rows: '240' }]),
    );

    const { queries } = await m.stats();

    expect(queries).toEqual({
      available: true,
      items: [{ query: 'SELECT * FROM deck_feed($1)', calls: 12, totalMs: 341, meanMs: 28.38, rows: 240 }],
    });
  });

  it('ยังไม่ได้เปิด pg_stat_statements = บอกว่าใช้ไม่ได้ ไม่ throw', async () => {
    const m = new MetricsService(null, pool(new Error('relation "pg_stat_statements" does not exist')));

    await expect(m.stats()).resolves.toMatchObject({ queries: { available: false, items: [] } });
  });

  it('reset ล้างตัวนับ (ไม่มี pg_stat_statements ก็ไม่พัง)', async () => {
    const m = new MetricsService(null, pool(new Error('no extension')));
    m.record('GET /chats', 10);

    await expect(m.reset()).resolves.toEqual({ success: true });
    expect((await m.stats()).routes).toEqual([]);
  });
});
