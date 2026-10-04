import { Inject, Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import type { Redis } from 'ioredis';
import {
  CACHE_KEY_PREFIX,
  CACHE_NAMESPACES,
  CACHE_REDIS,
  CACHE_STATS_KEY,
  type CacheNamespace,
} from './cache.constants.js';

/** สุ่ม TTL เพิ่ม 0-10% กัน key ที่ถูกเขียนพร้อมกันหมดอายุพร้อมกันแล้วยิง DB พร้อมกัน */
const TTL_JITTER = 0.1;

export interface CacheRef {
  ns: CacheNamespace;
  id: string;
}

const hitRatio = (hits: number, misses: number) =>
  hits + misses === 0 ? null : Math.round((hits / (hits + misses)) * 10_000) / 10_000;

/** แปลงผลของคำสั่ง INFO (บรรทัด "key:value") เป็น object */
export function parseRedisInfo(raw: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of raw.split(/\r?\n/)) {
    const i = line.indexOf(':');
    if (i > 0 && !line.startsWith('#')) out[line.slice(0, i)] = line.slice(i + 1);
  }
  return out;
}

/**
 * cache-aside บน Redis ตัวแยกจากคิว (REDIS_CACHE_URL) — หลักการ:
 * - fail open: Redis ล่ม/ช้า ต้องไม่ทำให้ request พัง แค่ตกไปอ่าน DB ตรง ๆ แล้วนับเป็น error
 * - ไม่ cache error (เช่น 404) — loader throw แล้วส่งต่อออกไปเลย
 * - รวม request ที่ miss key เดียวกันพร้อมกันใน process นี้ให้ยิง DB ครั้งเดียว (single-flight)
 * - ลบ key หลังเขียน DB สำเร็จ (ไม่ใช่เขียนค่าใหม่ทับ) กันค่าเก่าทับค่าใหม่ตอน request ชนกัน
 *
 * ไม่ตั้ง REDIS_CACHE_URL (เช่น worker, unit test) = redis เป็น null → ทุกคำสั่งอ่าน DB ตรง
 */
@Injectable()
export class CacheService implements OnModuleDestroy {
  private readonly logger = new Logger(CacheService.name);
  private readonly inflight = new Map<string, Promise<unknown>>();
  // นับเฉพาะใน process นี้ เพราะตอน Redis ล่มก็เขียนตัวนับลง Redis ไม่ได้อยู่ดี
  private errors = 0;

  constructor(@Inject(CACHE_REDIS) private readonly redis: Redis | null) {}

  get enabled() {
    return this.redis !== null;
  }

  private key({ ns, id }: CacheRef) {
    return `${CACHE_KEY_PREFIX}:${ns}:${id}`;
  }

  private ttl(ns: CacheNamespace) {
    const base = CACHE_NAMESPACES[ns].ttlSeconds;
    return base + Math.floor(Math.random() * base * TTL_JITTER);
  }

  private onError(op: string, err: unknown) {
    this.errors++;
    this.logger.warn(`cache ${op} failed: ${(err as Error)?.message ?? err}`);
  }

  /** ไม่ await — ตัวนับเป็นข้อมูลประกอบ ห้ามทำให้ request ช้าลงหรือพังตาม */
  private count(ns: CacheNamespace, result: 'hit' | 'miss') {
    this.redis?.hincrby(CACHE_STATS_KEY, `${ns}:${result}`, 1).catch(() => {});
  }

  async getOrSet<T>(ref: CacheRef, loader: () => Promise<T>): Promise<T> {
    if (!this.redis) return loader();
    const key = this.key(ref);

    try {
      const cached = await this.redis.get(key);
      if (cached !== null) {
        this.count(ref.ns, 'hit');
        return JSON.parse(cached) as T;
      }
      this.count(ref.ns, 'miss');
    } catch (err) {
      this.onError('get', err);
      return loader();
    }

    const pending = this.inflight.get(key);
    if (pending) return pending as Promise<T>;

    const load = (async () => {
      const value = await loader();
      this.redis!.set(key, JSON.stringify(value), 'EX', this.ttl(ref.ns)).catch((err) =>
        this.onError('set', err),
      );
      return value;
    })().finally(() => this.inflight.delete(key));
    this.inflight.set(key, load);
    return load;
  }

  /** เรียกหลัง COMMIT สำเร็จเท่านั้น — ลบไม่สำเร็จแค่ log ไว้ ค่าเก่าจะหมดอายุตาม TTL */
  async invalidate(...refs: CacheRef[]) {
    if (!this.redis || refs.length === 0) return;
    try {
      await this.redis.del(...refs.map((r) => this.key(r)));
    } catch (err) {
      this.onError('del', err);
    }
  }

  /**
   * สองมุมมองตามแนวปฏิบัติทั่วไป:
   * - namespaces: hit/miss ระดับแอปแยกตามชนิดข้อมูล (ตัวที่ใช้ตัดสินว่า TTL/การล้างเหมาะไหม)
   * - redis: ตัวเลขจาก INFO ของ server (รวมทุกคำสั่ง) + evicted_keys ซึ่งถ้าขึ้นเรื่อย ๆ
   *   แปลว่า maxmemory เล็กเกินไป
   */
  async stats() {
    const namespaces = Object.entries(CACHE_NAMESPACES).map(([name, cfg]) => ({
      name,
      ttlSeconds: cfg.ttlSeconds,
      hits: 0,
      misses: 0,
      hitRatio: null as number | null,
    }));
    const base = { enabled: this.enabled, available: false, since: null as string | null, errors: this.errors };
    const overall = () => {
      const hits = namespaces.reduce((s, n) => s + n.hits, 0);
      const misses = namespaces.reduce((s, n) => s + n.misses, 0);
      return { hits, misses, hitRatio: hitRatio(hits, misses) };
    };
    if (!this.redis) return { ...base, overall: overall(), namespaces, redis: null };

    try {
      const [counters, statsInfo, memoryInfo, serverInfo, keys] = await Promise.all([
        this.redis.hgetall(CACHE_STATS_KEY),
        this.redis.info('stats'),
        this.redis.info('memory'),
        this.redis.info('server'),
        this.redis.dbsize(),
      ]);
      for (const n of namespaces) {
        n.hits = Number(counters[`${n.name}:hit`] ?? 0);
        n.misses = Number(counters[`${n.name}:miss`] ?? 0);
        n.hitRatio = hitRatio(n.hits, n.misses);
      }
      const s = parseRedisInfo(statsInfo);
      const m = parseRedisInfo(memoryInfo);
      const srv = parseRedisInfo(serverInfo);
      const keyspaceHits = Number(s.keyspace_hits ?? 0);
      const keyspaceMisses = Number(s.keyspace_misses ?? 0);
      return {
        ...base,
        available: true,
        since: counters.since ?? null,
        overall: overall(),
        namespaces,
        redis: {
          keys,
          keyspaceHits,
          keyspaceMisses,
          hitRatio: hitRatio(keyspaceHits, keyspaceMisses),
          evictedKeys: Number(s.evicted_keys ?? 0),
          expiredKeys: Number(s.expired_keys ?? 0),
          usedMemoryBytes: Number(m.used_memory ?? 0),
          maxMemoryBytes: Number(m.maxmemory ?? 0),
          maxMemoryPolicy: m.maxmemory_policy ?? null,
          uptimeSeconds: Number(srv.uptime_in_seconds ?? 0),
        },
      };
    } catch (err) {
      this.onError('stats', err);
      return { ...base, errors: this.errors, overall: overall(), namespaces, redis: null };
    }
  }

  /**
   * เริ่มนับใหม่ทั้งตัวนับของแอปและของ Redis server (CONFIG RESETSTAT) ให้สองมุมมองนับช่วงเดียวกัน
   * ไม่ลบข้อมูลที่ cache ไว้
   */
  async resetStats() {
    if (!this.redis) return { success: true };
    const since = new Date().toISOString();
    await this.redis.multi().del(CACHE_STATS_KEY).hset(CACHE_STATS_KEY, 'since', since).exec();
    await this.redis.config('RESETSTAT');
    this.errors = 0;
    return { success: true, since };
  }

  async onModuleDestroy() {
    await this.redis?.quit().catch(() => {});
  }
}
