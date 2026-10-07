import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import type { Redis } from 'ioredis';
import { AppModule } from './../src/app.module.js';
import { CacheService } from './../src/cache/cache.service.js';
import { CACHE_REDIS } from './../src/cache/cache.constants.js';

// e2e: บูตแอปเต็มตัว (AppModule จริง) ต่อ Postgres และ Redis จริง ไม่ mock
// ใน CI ได้ฐานข้อมูลจาก services ใน .github/workflows/ci.yml
describe('PetPaws API (e2e)', () => {
  let app: INestApplication<App>;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /health ต่อฐานข้อมูลได้จริง', () => {
    return request(app.getHttpServer())
      .get('/health')
      .expect(200)
      .expect({ status: 'ok', db: 'connected' });
  });

  it('GET /health/ready เหมือน /health (ขั้น deploy ใช้รอ API ตัวใหม่พร้อม)', () => {
    return request(app.getHttpServer()).get('/health/ready').expect(200).expect({ status: 'ok', db: 'connected' });
  });

  it('GET /health/live ไม่ต้องล็อกอิน และไม่แตะ DB (load balancer ใช้)', () => {
    return request(app.getHttpServer()).get('/health/live').expect(200).expect({ status: 'ok' });
  });

  // JwtAuthGuard เป็น global guard: route ที่ไม่ได้ติด @Public() ต้องมี token เสมอ
  it('GET /users/me ไม่มี token -> 401', () => {
    return request(app.getHttpServer()).get('/users/me').expect(401);
  });

  it('GET /users/me token ปลอม -> 401', () => {
    return request(app.getHttpServer())
      .get('/users/me')
      .set('Authorization', 'Bearer not-a-real-token')
      .expect(401);
  });

  it('GET /admin/cache-stats ไม่มี token -> 401', () => {
    return request(app.getHttpServer()).get('/admin/cache-stats').expect(401);
  });

  // ต่อ Redis cache ตัวจริง (REDIS_CACHE_URL) — ข้ามถ้าไม่ได้ตั้ง
  it.runIf(process.env.REDIS_CACHE_URL)('cache: miss แล้ว hit กับ Redis จริง และนับลงสถิติ', async () => {
    const redis = app.get<Redis>(CACHE_REDIS);
    // enableOfflineQueue: false — ต้องรอต่อติดก่อน ไม่งั้นคำสั่งแรกตกไปทาง fail open
    if (redis.status !== 'ready') await new Promise((r) => redis.once('ready', r));
    const cache = app.get(CacheService);
    await cache.resetStats();

    const id = `e2e-${Date.now()}`;
    let calls = 0;
    const loader = async () => ({ n: ++calls });
    await cache.getOrSet({ ns: 'pet', id }, loader);
    await expect(cache.getOrSet({ ns: 'pet', id }, loader)).resolves.toEqual({ n: 1 });
    await cache.invalidate({ ns: 'pet', id });

    const stats = await cache.stats();
    expect(stats.available).toBe(true);
    expect(stats.namespaces.find((n) => n.name === 'pet')).toMatchObject({ hits: 1, misses: 1, hitRatio: 0.5 });
    expect(stats.redis?.maxMemoryPolicy).toBeDefined();
  });
});
