import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';
import { MetricsService } from './../src/metrics/metrics.service.js';

// บูตแอปจริง: interceptor ต้องนับ request จริงตาม route pattern และอ่าน pg_stat_statements ได้
// (CI ไม่ได้เปิด shared_preload_libraries ให้ service postgres — available เป็น false ได้ แต่ต้องไม่พัง)
describe('perf stats (e2e)', () => {
  let app: INestApplication<App>;
  let metrics: MetricsService;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleFixture.createNestApplication();
    await app.init();
    metrics = app.get(MetricsService);
    await metrics.reset();
  });

  afterAll(async () => {
    await app.close();
  });

  it('นับ request จริงตาม route pattern ไม่นับ health check', async () => {
    const server = app.getHttpServer();
    await request(server).get('/users/me').expect(401);
    await request(server).get('/users/me').expect(401);
    await request(server).get('/health/live').expect(200);
    // ตัวนับเขียนแบบไม่รอ — ให้ Redis รับก่อนอ่าน
    await new Promise((r) => setTimeout(r, 200));

    const stats = await metrics.stats();

    // ไฟล์ e2e อื่นรันพร้อมกันและยิง /users/me ด้วย (Redis ตัวเดียวกัน) — ได้อย่างน้อย 2
    expect(stats.routes.find((r) => r.route === 'GET /users/me')?.count).toBeGreaterThanOrEqual(2);
    expect(stats.routes.some((r) => r.route.includes('/health'))).toBe(false);
  });

  it('query ที่กินเวลา DB มากสุด: เปิด pg_stat_statements แล้วได้รายการ ไม่เปิดก็ไม่พัง', async () => {
    const { queries } = await metrics.stats();

    if (queries.available) {
      expect(queries.items.length).toBeGreaterThan(0);
      expect(queries.items[0]).toEqual(
        expect.objectContaining({ query: expect.any(String), calls: expect.any(Number), totalMs: expect.any(Number) }),
      );
    } else {
      expect(queries.items).toEqual([]);
    }
  });
});
