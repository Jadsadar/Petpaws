import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import { AppModule } from './../src/app.module.js';

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
});
