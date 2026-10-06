import { Logger } from '@nestjs/common';
import { ThrottlerStorageService, type ThrottlerStorage } from '@nestjs/throttler';
import type { Redis } from 'ioredis';

const KEY_PREFIX = 'petpaws:throttle';

/**
 * นับ + บล็อกในคำสั่งเดียว (atomic) — API หลายตัวยิงพร้อมกันก็ไม่นับพลาด
 * KEYS[1] = ตัวนับของช่วงเวลานี้, KEYS[2] = ป้าย "ถูกบล็อก"
 * ARGV    = ttl (ms), limit, blockDuration (ms)
 * คืน {totalHits, ttl ที่เหลือ (ms), isBlocked (0/1), เวลาบล็อกที่เหลือ (ms)}
 *
 * ระหว่างถูกบล็อกไม่นับเพิ่ม และพอพ้นบล็อกเริ่มนับใหม่จากศูนย์ — เหมือน ThrottlerStorageService
 * ต่างกันตรงนับเป็นช่วงเวลาตายตัว (เริ่มนับที่คำขอแรก) แทนการเลื่อนตามแต่ละคำขอ
 */
const INCREMENT_SCRIPT = `
local blockTtl = redis.call('PTTL', KEYS[2])
if blockTtl > 0 then
  return {tonumber(redis.call('GET', KEYS[1]) or '0'), math.max(redis.call('PTTL', KEYS[1]), 0), 1, blockTtl}
end
local hits = redis.call('INCR', KEYS[1])
local ttl = redis.call('PTTL', KEYS[1])
if ttl < 0 then
  redis.call('PEXPIRE', KEYS[1], ARGV[1])
  ttl = tonumber(ARGV[1])
end
if hits > tonumber(ARGV[2]) then
  local block = tonumber(ARGV[3])
  if block <= 0 then return {hits, ttl, 1, ttl} end
  redis.call('SET', KEYS[2], '1', 'PX', block)
  redis.call('DEL', KEYS[1])
  return {hits, ttl, 1, block}
end
return {hits, ttl, 0, 0}
`;

/**
 * ตัวนับ rate limit เก็บใน Redis (ตัว cache) — ทุก API หลัง load balancer เห็นตัวเลขเดียวกัน
 * ไม่งั้นแต่ละตัวนับแยก เพดานจริงหลวมเป็น N เท่าตามจำนวน API
 *
 * Redis ไม่ได้ตั้ง / ล่ม / ช้า = นับในหน่วยความจำของ API ตัวนี้แทน (fail open แบบยังมีเพดาน)
 * — rate limit พังต้องไม่ทำให้ทุก request พังตาม
 */
export class RedisThrottlerStorage implements ThrottlerStorage {
  private readonly logger = new Logger(RedisThrottlerStorage.name);
  private readonly fallback = new ThrottlerStorageService();
  private failing = false;

  constructor(private readonly redis: Redis | null) {}

  async increment(key: string, ttl: number, limit: number, blockDuration: number, throttlerName: string) {
    if (!this.redis) return this.fallback.increment(key, ttl, limit, blockDuration, throttlerName);
    const base = `${KEY_PREFIX}:${throttlerName}:${key}`;
    try {
      const [totalHits, ttlMs, blocked, blockMs] = (await this.redis.eval(
        INCREMENT_SCRIPT,
        2,
        `${base}:hits`,
        `${base}:block`,
        ttl,
        limit,
        blockDuration,
      )) as [number, number, number, number];
      this.failing = false;
      return {
        totalHits,
        timeToExpire: Math.ceil(ttlMs / 1000),
        isBlocked: blocked === 1,
        timeToBlockExpire: Math.ceil(blockMs / 1000),
      };
    } catch (err) {
      // log ครั้งแรกที่เริ่มพัง ไม่พ่นทุก request
      if (!this.failing) {
        this.failing = true;
        this.logger.warn(`นับ rate limit ใน Redis ไม่ได้ (${(err as Error).message}) — นับในหน่วยความจำแทน`);
      }
      return this.fallback.increment(key, ttl, limit, blockDuration, throttlerName);
    }
  }
}
