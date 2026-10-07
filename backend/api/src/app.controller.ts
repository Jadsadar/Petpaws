import { Controller, Get, Inject } from '@nestjs/common';
import type { Pool } from 'pg';
import { PG_POOL } from './database/database.module.js';
import { SkipThrottle } from '@nestjs/throttler';
import { Public } from './common/public.decorator.js';

/**
 * health check สองแบบ (ถูกยิงทุกไม่กี่วินาที จึงไม่นับ rate limit):
 *
 *   /health/live           — process ยังทำงานและตอบได้ ไม่แตะ DB
 *                            load balancer (Caddy) ใช้เลือกว่าจะส่งงานให้ API ตัวไหน
 *   /health, /health/ready — ต่อ Postgres ได้จริง พร้อมรับงาน
 *                            Docker HEALTHCHECK และขั้น deploy ใช้รอให้ API ตัวใหม่พร้อมก่อนสลับ
 *
 * แยกกันเพราะถ้า load balancer ใช้แบบเช็ก DB แล้ว DB สะดุดแป๊บเดียว API ทุกตัวจะถูกถอดพร้อมกัน
 * ทั้งที่ตัว API เองไม่ได้เป็นอะไร (และ request ที่ไม่ต้องใช้ DB ก็ตอบไม่ได้ไปด้วย)
 */
@SkipThrottle()
@Public()
@Controller('health')
export class AppController {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  @Get('live')
  live() {
    return { status: 'ok' };
  }

  // ROADMAP.md Phase 1.8 — เช็ก Postgres ต่อติดจริง ไม่ใช่แค่ process ยังไม่ crash
  @Get(['', 'ready'])
  async ready() {
    await this.pool.query('SELECT 1');
    return { status: 'ok', db: 'connected' };
  }
}
