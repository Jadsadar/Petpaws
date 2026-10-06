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
import { UsersService } from './../src/users/users.service.js';
import { ModerationService } from './../src/moderation/moderation.service.js';

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

  /** สัตว์ 1 ตัวของ [ownerId] */
  const newPet = async (ownerId: string, status = 'available') => {
    const res = await pool.query<{ id: string }>(
      `INSERT INTO pets (owner_id, name, location, status, adopted_at)
       VALUES ($1, 'น้องทดสอบ', 'กรุงเทพมหานคร', $2::pet_status, CASE WHEN $2 = 'adopted' THEN now() END) RETURNING id`,
      [ownerId, status],
    );
    return res.rows[0].id;
  };

  /** ห้องแชท + ข้อความแรก (DB บังคับให้ห้องต้องมีข้อความแรกใน transaction เดียวกัน) */
  const newChat = async (petId: string, initiatorId: string, ownerId: string) => {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const c = await client.query<{ id: string }>(
        `INSERT INTO conversations (pet_id, initiator_id, owner_id) VALUES ($1, $2, $3) RETURNING id`,
        [petId, initiatorId, ownerId],
      );
      const m = await client.query<{ id: string }>(
        `INSERT INTO messages (conversation_id, sender_id, body) VALUES ($1, $2, 'สวัสดี') RETURNING id`,
        [c.rows[0].id, initiatorId],
      );
      await client.query('COMMIT');
      return { chatId: c.rows[0].id, messageId: m.rows[0].id };
    } finally {
      client.release();
    }
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

  describe('users', () => {
    it('แก้โปรไฟล์ทีละส่วน: ช่องที่ไม่ส่งมาคงค่าเดิม, แท็กแทนที่ทั้งชุด, profile_completed_at ตั้งครั้งเดียว', async () => {
      const users = app.get(UsersService);
      const id = await newUser();
      const slugs = (await pool.query<{ slug: string }>(`SELECT slug FROM traits WHERE is_active ORDER BY sort_order LIMIT 3`)).rows.map((r) => r.slug);

      const first = await users.updateMe(id, {
        name: '  สมชาย  ',
        province: 'เชียงใหม่',
        phone: '0812345678',
        traits: [slugs[0], slugs[1], 'ไม่มีแท็กนี้'],
        homeType: 'คอนโดมิเนียม',
      });
      const completedAt = (await pool.query(`SELECT profile_completed_at FROM users WHERE id = $1`, [id])).rows[0].profile_completed_at;

      expect(first).toMatchObject({ name: 'สมชาย', province: 'เชียงใหม่', phone: '0812345678', lineId: '', homeType: 'คอนโดมิเนียม' });
      expect(first.traits).toEqual([slugs[0], slugs[1]]);
      expect(completedAt).toBeInstanceOf(Date);

      const second = await users.updateMe(id, { lineId: 'somchai', traits: [slugs[2]] });

      expect(second).toMatchObject({ name: 'สมชาย', phone: '0812345678', lineId: 'somchai', traits: [slugs[2]] });
      const again = (await pool.query(`SELECT profile_completed_at FROM users WHERE id = $1`, [id])).rows[0].profile_completed_at;
      expect(again).toEqual(completedAt);
    });

    it('ค่าผิดกลางทาง = ยกเลิกทั้งชุด (ชื่อที่ส่งมาพร้อมกันต้องไม่ถูกบันทึก)', async () => {
      const users = app.get(UsersService);
      const id = await newUser({ displayName: 'ชื่อเดิม' });

      await expect(users.updateMe(id, { name: 'ชื่อใหม่', homeType: 'ปราสาท' })).rejects.toMatchObject({ code: 'INVALID_HOME_TYPE' });

      expect((await users.getMe(id)).name).toBe('ชื่อเดิม');
    });

    it('โปรไฟล์สาธารณะไม่มีเบอร์โทร / ผู้ใช้ที่ไม่มีอยู่ได้ 404', async () => {
      const users = app.get(UsersService);
      const id = await newUser();
      await users.updateMe(id, { phone: '0899999999', lineId: 'line_pub' });

      const pub = await users.getPublic(id);

      expect(pub).toMatchObject({ lineId: 'line_pub' });
      expect(pub).not.toHaveProperty('phone');
      await expect(users.getPublic(randomUUID())).rejects.toMatchObject({ code: 'NOT_FOUND' });
    });
  });

  describe('moderation', () => {
    it('บล็อกซ้ำไม่ error, ห้องแชทถูกปิด และปลดบล็อกแล้วห้องเปิดกลับมา', async () => {
      const moderation = app.get(ModerationService);
      const [me, owner] = [await newUser(), await newUser()];
      const { chatId } = await newChat(await newPet(owner), me, owner);
      const status = async () =>
        (await pool.query(`SELECT status, closed_reason FROM conversations WHERE id = $1`, [chatId])).rows[0];

      await moderation.createBlock(me, { blockedUserId: owner });
      await moderation.createBlock(me, { blockedUserId: owner });
      expect(await status()).toEqual({ status: 'closed', closed_reason: 'blocked' });

      await moderation.deleteBlock(me, owner);
      expect(await status()).toEqual({ status: 'active', closed_reason: null });
    });

    it('ปลดบล็อกไม่เปิดห้องที่สัตว์ได้บ้านไปแล้ว', async () => {
      const moderation = app.get(ModerationService);
      const [me, owner] = [await newUser(), await newUser()];
      const petId = await newPet(owner);
      const { chatId } = await newChat(petId, me, owner);
      await moderation.createBlock(me, { blockedUserId: owner });
      await pool.query(`UPDATE pets SET status = 'adopted', adopted_at = now() WHERE id = $1`, [petId]);

      await moderation.deleteBlock(me, owner);

      const row = (await pool.query(`SELECT status FROM conversations WHERE id = $1`, [chatId])).rows[0];
      expect(row.status).toBe('closed');
    });

    it('รายงานข้อความของอีกฝ่ายในห้องตัวเองได้ คนนอกห้องรายงานไม่ได้', async () => {
      const moderation = app.get(ModerationService);
      const [me, owner, stranger] = [await newUser(), await newUser(), await newUser()];
      const { messageId } = await newChat(await newPet(owner), me, owner);

      const report = await moderation.createReport(owner, { reportedMessageId: messageId, reason: 'spam' });

      expect(report.id).toMatch(/^[0-9a-f-]{36}$/);
      await expect(
        moderation.createReport(stranger, { reportedMessageId: messageId, reason: 'spam' }),
      ).rejects.toMatchObject({ code: 'FORBIDDEN' });
    });
  });
});
