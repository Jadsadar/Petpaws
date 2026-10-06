import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { App } from 'supertest/types';
import type { Pool } from 'pg';
import { randomUUID } from 'node:crypto';
import { AppModule } from './../src/app.module.js';
import { PG_POOL } from './../src/database/database.module.js';
import { DevicesService } from './../src/devices/devices.service.js';
import { JwtService } from '@nestjs/jwt';

// service ที่ย้ายมาใช้ TypeORM ต้องทำงานกับ DB จริงเหมือน SQL เดิม (unit test ที่ mock DB จับ
// ความผิดของ SQL ที่ ORM สร้างไม่ได้) — แต่ละ describe ใช้ข้อมูลของตัวเอง ไม่พึ่ง seed
describe('modules ที่ใช้ TypeORM กับ DB จริง (e2e)', () => {
  let app: INestApplication<App>;
  let pool: Pool;

  const newUser = async (extra: Record<string, unknown> = {}) => {
    const tag = randomUUID().slice(0, 8);
    const res = await pool.query<{ id: string }>(
      `INSERT INTO users (username, email, password_hash, display_name, location)
       VALUES ($1, $2, 'x', $3, $4) RETURNING id`,
      [`e2e_${tag}`, `e2e_${tag}@e2e.test`, (extra.displayName as string) ?? `ผู้ทดสอบ ${tag}`, extra.location ?? null],
    );
    return res.rows[0].id;
  };

  /** access token ของผู้ใช้คนนี้ (ลายเซ็นเดียวกับที่ API ออกตอนล็อกอิน) */
  const bearer = (userId: string) =>
    `Bearer ${app.get(JwtService).sign({ sub: userId }, { secret: process.env.JWT_ACCESS_SECRET, expiresIn: '5m' })}`;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleFixture.createNestApplication();
    await app.init();
    pool = app.get<Pool>(PG_POOL);
  });

  afterAll(async () => {
    await app.close();
  });

  describe('traits', () => {
    it('GET /traits คืนแท็กที่เปิดใช้ เรียงตาม sort_order เหมือน SQL เดิม', async () => {
      const expected = await pool.query(`SELECT id, slug, label_th AS label FROM traits WHERE is_active ORDER BY sort_order`);

      const res = await request(app.getHttpServer()).get('/traits').set('Authorization', bearer(await newUser())).expect(200);

      expect(res.body).toEqual(expected.rows);
    });
  });

  describe('devices', () => {
    it('ลงทะเบียน token ซ้ำ = upsert (ย้ายเจ้าของได้) ไม่เกิดแถวซ้ำ แล้วลบได้', async () => {
      const devices = app.get(DevicesService);
      const [a, b] = [await newUser(), await newUser()];
      const token = `tok-${randomUUID()}`;

      await devices.register(a, { token, platform: 'android' });
      await devices.register(b, { token, platform: 'ios' });

      expect(await devices.tokensForUser(a)).toEqual([]);
      expect(await devices.tokensForUser(b)).toEqual([token]);
      const row = await pool.query(`SELECT platform, user_id FROM device_tokens WHERE token = $1`, [token]);
      expect(row.rows).toEqual([{ platform: 'ios', user_id: b }]);

      await devices.removeTokens([token, 'ไม่มีอยู่จริง']);
      expect(await devices.tokensForUser(b)).toEqual([]);
    });
  });
});
