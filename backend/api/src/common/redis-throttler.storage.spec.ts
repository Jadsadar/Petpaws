import { describe, expect, it, vi } from 'vitest';
import type { Redis } from 'ioredis';
import { RedisThrottlerStorage } from './redis-throttler.storage.js';

// logic นับ/บล็อกใน Redis เทสต์กับ Redis จริงใน test/redis-throttler.e2e-spec.ts
// ที่นี่เทสต์เฉพาะทางสำรองตอนไม่มี/ใช้ Redis ไม่ได้
describe('RedisThrottlerStorage ทางสำรอง', () => {
  it('ไม่ได้ตั้ง Redis = นับในหน่วยความจำ ยังมีเพดานอยู่', async () => {
    const storage = new RedisThrottlerStorage(null);
    await storage.increment('k', 60_000, 1, 60_000, 'default');

    await expect(storage.increment('k', 60_000, 1, 60_000, 'default')).resolves.toMatchObject({ isBlocked: true });
  });

  it('Redis ล่ม/ช้า ไม่ทำให้ request พัง — ถอยไปนับในหน่วยความจำ', async () => {
    const redis = { eval: vi.fn().mockRejectedValue(new Error('Command timed out')) } as unknown as Redis;
    const storage = new RedisThrottlerStorage(redis);

    await expect(storage.increment('k', 60_000, 5, 60_000, 'default')).resolves.toMatchObject({
      totalHits: 1,
      isBlocked: false,
    });
  });

  it('แปลงผลจาก Redis (มิลลิวินาที) เป็นวินาทีปัดขึ้น ตามที่ ThrottlerGuard ใช้ทำ Retry-After', async () => {
    const redis = { eval: vi.fn().mockResolvedValue([6, 1500, 1, 299_001]) } as unknown as Redis;

    await expect(new RedisThrottlerStorage(redis).increment('k', 60_000, 5, 300_000, 'login')).resolves.toEqual({
      totalHits: 6,
      timeToExpire: 2,
      isBlocked: true,
      timeToBlockExpire: 300,
    });
  });
});
