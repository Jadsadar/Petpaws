import { Inject, Injectable, Logger } from '@nestjs/common';
import type { Redis } from 'ioredis';
import type { Pool } from 'pg';
import { CACHE_REDIS } from '../cache/cache.constants.js';
import { PG_POOL } from '../database/database.module.js';

/** คำขอที่ใช้เวลาเกินนี้ถือว่าช้า — log เตือน และนับแยกไว้ */
export const SLOW_REQUEST_MS = 500;
const STATS_KEY = 'petpaws:perf-stats';
const TOP_QUERIES = 15;

/**
 * เก็บค่า max แบบ atomic (HSET เฉพาะตอนค่าใหม่มากกว่า) — API หลายตัวเขียนพร้อมกันได้
 * KEYS[1] = hash, ARGV = field ของ route, ms, slow (0/1)
 */
const RECORD_SCRIPT = `
redis.call('HINCRBY', KEYS[1], ARGV[1] .. '|count', 1)
redis.call('HINCRBYFLOAT', KEYS[1], ARGV[1] .. '|totalMs', ARGV[2])
if tonumber(ARGV[3]) == 1 then redis.call('HINCRBY', KEYS[1], ARGV[1] .. '|slow', 1) end
local max = tonumber(redis.call('HGET', KEYS[1], ARGV[1] .. '|maxMs') or '0')
if tonumber(ARGV[2]) > max then redis.call('HSET', KEYS[1], ARGV[1] .. '|maxMs', ARGV[2]) end
return 1
`;

interface RouteCounters {
  count: number;
  totalMs: number;
  slow: number;
  maxMs: number;
}

/**
 * วัดว่า endpoint ไหนช้า/ถูกเรียกบ่อย (ระดับแอป) + query ไหนกินเวลา DB มากสุด (pg_stat_statements)
 * ใช้ตัดสินว่าจะปรับ query ตัวไหนก่อน — ดูที่ GET /admin/perf-stats
 *
 * ตัวนับของ route เก็บใน Redis ตัว cache ให้ API ทุกตัวหลัง load balancer นับรวมกัน
 * ไม่มี Redis = นับในหน่วยความจำของ API ตัวนี้ ตัวนับเป็นข้อมูลประกอบ ห้ามทำให้ request ช้า/พัง
 */
@Injectable()
export class MetricsService {
  private readonly logger = new Logger('Perf');
  private readonly local = new Map<string, RouteCounters>();

  constructor(
    @Inject(CACHE_REDIS) private readonly redis: Redis | null,
    @Inject(PG_POOL) private readonly pool: Pool,
  ) {}

  record(route: string, ms: number) {
    const slow = ms >= SLOW_REQUEST_MS;
    if (slow) this.logger.warn(`ช้า ${route} ${Math.round(ms)}ms`);
    const rounded = Math.round(ms * 10) / 10;
    if (this.redis) {
      this.redis.eval(RECORD_SCRIPT, 1, STATS_KEY, route, rounded, slow ? 1 : 0).catch(() => this.recordLocal(route, rounded, slow));
      return;
    }
    this.recordLocal(route, rounded, slow);
  }

  private recordLocal(route: string, ms: number, slow: boolean) {
    const c = this.local.get(route) ?? { count: 0, totalMs: 0, slow: 0, maxMs: 0 };
    c.count++;
    c.totalMs += ms;
    if (slow) c.slow++;
    c.maxMs = Math.max(c.maxMs, ms);
    this.local.set(route, c);
  }

  private async counters(): Promise<Map<string, RouteCounters>> {
    const merged = new Map<string, RouteCounters>();
    for (const [route, c] of this.local) merged.set(route, { ...c });
    if (!this.redis) return merged;
    try {
      const raw = await this.redis.hgetall(STATS_KEY);
      for (const [field, value] of Object.entries(raw)) {
        const i = field.lastIndexOf('|');
        const route = field.slice(0, i);
        const name = field.slice(i + 1) as keyof RouteCounters;
        const c = merged.get(route) ?? { count: 0, totalMs: 0, slow: 0, maxMs: 0 };
        c[name] = name === 'maxMs' ? Math.max(c.maxMs, Number(value)) : c[name] + Number(value);
        merged.set(route, c);
      }
    } catch {
      // Redis ใช้ไม่ได้ — คืนเท่าที่มีในเครื่อง
    }
    return merged;
  }

  /** endpoint เรียงตามเวลารวม (ตัวที่ควรปรับก่อนอยู่บนสุด) + query ที่กินเวลา DB มากสุด */
  async stats() {
    const routes = [...(await this.counters()).entries()]
      .map(([route, c]) => ({
        route,
        count: c.count,
        avgMs: c.count ? Math.round((c.totalMs / c.count) * 10) / 10 : 0,
        maxMs: c.maxMs,
        totalMs: Math.round(c.totalMs),
        slowCount: c.slow,
      }))
      .sort((a, b) => b.totalMs - a.totalMs);
    return { slowThresholdMs: SLOW_REQUEST_MS, routes, queries: await this.topQueries() };
  }

  /**
   * ต้องเปิด shared_preload_libraries=pg_stat_statements (docker-compose) + CREATE EXTENSION
   * (migration 019) — ยังไม่เปิด = บอกว่าใช้ไม่ได้ ไม่ throw
   */
  private async topQueries() {
    try {
      const res = await this.pool.query<{
        query: string;
        calls: string;
        total_ms: number;
        mean_ms: number;
        rows: string;
      }>(
        `SELECT query, calls, total_exec_time AS total_ms, mean_exec_time AS mean_ms, rows
           FROM pg_stat_statements
          WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
          ORDER BY total_exec_time DESC
          LIMIT $1`,
        [TOP_QUERIES],
      );
      return {
        available: true,
        items: res.rows.map((r) => ({
          query: r.query,
          calls: Number(r.calls),
          totalMs: Math.round(r.total_ms),
          meanMs: Math.round(r.mean_ms * 100) / 100,
          rows: Number(r.rows),
        })),
      };
    } catch (err) {
      return { available: false, reason: (err as Error).message, items: [] };
    }
  }

  /** เริ่มนับใหม่ทั้งสองฝั่ง — ใช้ก่อน/หลังแก้ query เพื่อเทียบผล */
  async reset() {
    this.local.clear();
    await this.redis?.del(STATS_KEY).catch(() => {});
    await this.pool.query('SELECT pg_stat_statements_reset()').catch(() => {});
    return { success: true };
  }
}
