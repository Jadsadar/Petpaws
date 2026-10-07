import { Redis } from 'ioredis';
import { RedisThrottlerStorage } from './../src/common/redis-throttler.storage.js';

// รัน Lua script จริงบน Redis จริง (ตัว cache ของ CI) — logic นับ/บล็อกทั้งหมดอยู่ใน script
// เทสต์ด้วย mock ไม่ได้ความมั่นใจ
describe('RedisThrottlerStorage (Redis จริง)', () => {
  let redis: Redis;
  let storage: RedisThrottlerStorage;
  let n = 0;
  const key = () => `e2e-${Date.now()}-${n++}`;

  beforeAll(() => {
    redis = new Redis(process.env.REDIS_CACHE_URL ?? 'redis://localhost:6380');
    storage = new RedisThrottlerStorage(redis);
  });

  afterAll(async () => {
    await redis.quit();
  });

  it('นับเพิ่มทีละครั้ง ยังไม่เกินเพดานไม่บล็อก และบอกเวลาที่เหลือของช่วงนับ', async () => {
    const k = key();
    const first = await storage.increment(k, 60_000, 3, 60_000, 'default');
    const second = await storage.increment(k, 60_000, 3, 60_000, 'default');

    expect(first).toMatchObject({ totalHits: 1, isBlocked: false });
    expect(second).toMatchObject({ totalHits: 2, isBlocked: false });
    expect(second.timeToExpire).toBeGreaterThan(55);
    expect(second.timeToExpire).toBeLessThanOrEqual(60);
  });

  it('เกินเพดาน = บล็อกตาม blockDuration และระหว่างบล็อกยังโดนบล็อกต่อ', async () => {
    const k = key();
    for (let i = 0; i < 2; i++) await storage.increment(k, 60_000, 2, 300_000, 'default');

    const over = await storage.increment(k, 60_000, 2, 300_000, 'default');
    const again = await storage.increment(k, 60_000, 2, 300_000, 'default');

    expect(over).toMatchObject({ isBlocked: true, timeToBlockExpire: 300 });
    expect(again.isBlocked).toBe(true);
    expect(again.timeToBlockExpire).toBeGreaterThan(295);
  });

  it('พ้นช่วงบล็อกแล้วเริ่มนับใหม่จากศูนย์', async () => {
    const k = key();
    for (let i = 0; i < 2; i++) await storage.increment(k, 60_000, 1, 300, 'default');
    await new Promise((r) => setTimeout(r, 400));

    await expect(storage.increment(k, 60_000, 1, 300, 'default')).resolves.toMatchObject({
      totalHits: 1,
      isBlocked: false,
    });
  });

  it('API สองตัว (storage สองชุด) นับรวมกันใน Redis — เพดานไม่หลวมตามจำนวน API', async () => {
    const k = key();
    const apiB = new RedisThrottlerStorage(redis);
    await storage.increment(k, 60_000, 2, 60_000, 'default');
    await apiB.increment(k, 60_000, 2, 60_000, 'default');

    await expect(storage.increment(k, 60_000, 2, 60_000, 'default')).resolves.toMatchObject({ isBlocked: true });
  });

  it('ช่วงนับหมดอายุเองตาม ttl ไม่ค้างใน Redis', async () => {
    const k = key();
    await storage.increment(k, 200, 5, 200, 'default');
    await new Promise((r) => setTimeout(r, 300));

    expect(await redis.exists(`petpaws:throttle:default:${k}:hits`)).toBe(0);
  });
});
