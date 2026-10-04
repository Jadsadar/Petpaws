import { describe, expect, it, vi } from 'vitest';
import type { Redis } from 'ioredis';
import { CacheService, parseRedisInfo } from './cache.service.js';
import { CACHE_STATS_KEY } from './cache.constants.js';

// Redis ปลอมในหน่วยความจำ — มีแค่คำสั่งที่ CacheService ใช้
function fakeRedis() {
  const store = new Map<string, string>();
  const hash: Record<string, string> = {};
  const redis = {
    get: vi.fn(async (k: string) => store.get(k) ?? null),
    set: vi.fn(async (k: string, v: string, ..._opts: unknown[]) => {
      store.set(k, v);
      return 'OK';
    }),
    del: vi.fn(async (...ks: string[]) => ks.filter((k) => store.delete(k)).length),
    hincrby: vi.fn(async (_k: string, f: string, n: number) => {
      hash[f] = String(Number(hash[f] ?? 0) + n);
      return Number(hash[f]);
    }),
    hgetall: vi.fn(async () => ({ ...hash })),
    info: vi.fn(async (section: string) =>
      ({
        stats: '# Stats\r\nkeyspace_hits:30\r\nkeyspace_misses:10\r\nevicted_keys:2\r\nexpired_keys:5\r\n',
        memory: '# Memory\r\nused_memory:1048576\r\nmaxmemory:67108864\r\nmaxmemory_policy:volatile-lru\r\n',
        server: '# Server\r\nuptime_in_seconds:120\r\n',
      })[section] ?? '',
    ),
    dbsize: vi.fn(async () => 7),
  };
  return { redis, store, hash, service: new CacheService(redis as unknown as Redis) };
}

// ให้ HINCRBY แบบ fire-and-forget ทำงานเสร็จก่อนตรวจผล
const flush = () => new Promise((r) => setTimeout(r, 0));

describe('CacheService.getOrSet', () => {
  it('miss ครั้งแรกเรียก loader และเก็บลง Redis พร้อม TTL, ครั้งถัดไป hit ไม่เรียก loader', async () => {
    const { redis, service, hash } = fakeRedis();
    const loader = vi.fn(async () => ({ id: 'p1', name: 'ข้าวตัง' }));

    await expect(service.getOrSet({ ns: 'pet', id: 'p1' }, loader)).resolves.toEqual({ id: 'p1', name: 'ข้าวตัง' });
    await expect(service.getOrSet({ ns: 'pet', id: 'p1' }, loader)).resolves.toEqual({ id: 'p1', name: 'ข้าวตัง' });
    await flush();

    expect(loader).toHaveBeenCalledTimes(1);
    const [key, , ex, ttl] = redis.set.mock.calls[0];
    expect(key).toBe('petpaws:cache:v1:pet:p1');
    expect(ex).toBe('EX');
    // TTL 300 + jitter ไม่เกิน 10%
    expect(ttl).toBeGreaterThanOrEqual(300);
    expect(ttl).toBeLessThan(330);
    expect(hash).toMatchObject({ 'pet:miss': '1', 'pet:hit': '1' });
  });

  it('miss พร้อมกันหลาย request ยิง loader ครั้งเดียว (single-flight)', async () => {
    const { service } = fakeRedis();
    let resolve!: (v: number) => void;
    const loader = vi.fn(() => new Promise<number>((r) => (resolve = r)));

    const a = service.getOrSet({ ns: 'traits', id: 'active' }, loader);
    const b = service.getOrSet({ ns: 'traits', id: 'active' }, loader);
    await flush();
    resolve(42);

    await expect(Promise.all([a, b])).resolves.toEqual([42, 42]);
    expect(loader).toHaveBeenCalledTimes(1);
  });

  it('ไม่ cache error ของ loader (เช่น 404)', async () => {
    const { redis, service } = fakeRedis();
    const err = new Error('not found');

    await expect(service.getOrSet({ ns: 'pet', id: 'x' }, () => Promise.reject(err))).rejects.toBe(err);
    expect(redis.set).not.toHaveBeenCalled();
  });

  it('Redis ล่ม = fail open: อ่านจาก loader ตรงและนับเป็น error', async () => {
    const { redis, service } = fakeRedis();
    redis.get.mockRejectedValueOnce(new Error('Connection is closed'));

    await expect(service.getOrSet({ ns: 'pet', id: 'p1' }, async () => 'fresh')).resolves.toBe('fresh');
    expect((await service.stats()).errors).toBe(1);
  });

  it('ไม่มี Redis (null) = เรียก loader ทุกครั้ง', async () => {
    const service = new CacheService(null);
    const loader = vi.fn(async () => 1);

    await service.getOrSet({ ns: 'pet', id: 'p1' }, loader);
    await service.getOrSet({ ns: 'pet', id: 'p1' }, loader);

    expect(loader).toHaveBeenCalledTimes(2);
    expect(service.enabled).toBe(false);
  });
});

describe('CacheService.invalidate', () => {
  it('ลบ key แล้วครั้งถัดไปโหลดใหม่', async () => {
    const { service } = fakeRedis();
    let n = 0;
    const loader = async () => ++n;

    await service.getOrSet({ ns: 'userPublic', id: 'u1' }, loader);
    await service.invalidate({ ns: 'userPublic', id: 'u1' });

    await expect(service.getOrSet({ ns: 'userPublic', id: 'u1' }, loader)).resolves.toBe(2);
  });

  it('ลบไม่สำเร็จไม่ throw ออกไปให้ request พัง', async () => {
    const { redis, service } = fakeRedis();
    redis.del.mockRejectedValueOnce(new Error('timeout'));

    await expect(service.invalidate({ ns: 'pet', id: 'p1' })).resolves.toBeUndefined();
  });
});

describe('CacheService.stats', () => {
  it('คำนวณ hit ratio แยกกลุ่ม รวม และของ Redis server', async () => {
    const { service, hash } = fakeRedis();
    Object.assign(hash, { 'pet:hit': '3', 'pet:miss': '1', 'traits:hit': '6', since: '2026-10-01T00:00:00.000Z' });

    const s = await service.stats();

    expect(s.available).toBe(true);
    expect(s.since).toBe('2026-10-01T00:00:00.000Z');
    expect(s.namespaces.find((n) => n.name === 'pet')).toMatchObject({ hits: 3, misses: 1, hitRatio: 0.75 });
    expect(s.namespaces.find((n) => n.name === 'traits')).toMatchObject({ hits: 6, misses: 0, hitRatio: 1 });
    // กลุ่มที่ยังไม่มี request เลยต้องเป็น null ไม่ใช่ 0% (ไม่งั้นดูเหมือน cache ไม่ทำงาน)
    expect(s.namespaces.find((n) => n.name === 'userPublic')?.hitRatio).toBeNull();
    expect(s.overall).toEqual({ hits: 9, misses: 1, hitRatio: 0.9 });
    expect(s.redis).toMatchObject({
      keys: 7,
      hitRatio: 0.75,
      evictedKeys: 2,
      maxMemoryBytes: 67108864,
      maxMemoryPolicy: 'volatile-lru',
      uptimeSeconds: 120,
    });
  });

  it('ไม่มี Redis = enabled false และ redis เป็น null', async () => {
    const s = await new CacheService(null).stats();
    expect(s).toMatchObject({ enabled: false, available: false, redis: null });
    expect(s.overall.hitRatio).toBeNull();
  });
});

describe('parseRedisInfo', () => {
  it('ข้ามบรรทัดหัวข้อ (#) และบรรทัดว่าง', () => {
    expect(parseRedisInfo('# Stats\r\nkeyspace_hits:5\r\n\r\nfoo:a:b\r\n')).toEqual({
      keyspace_hits: '5',
      foo: 'a:b',
    });
  });
});

it('CACHE_STATS_KEY ไม่ขึ้นต้นด้วย prefix ของข้อมูล (กันโดน DEL ตอนล้างข้อมูลทั้ง prefix)', () => {
  expect(CACHE_STATS_KEY.startsWith('petpaws:cache:')).toBe(false);
});
