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
import { PetsService } from './../src/pets/pets.service.js';
import { AdminService } from './../src/admin/admin.service.js';
import { resolvePaging } from './../src/admin/dto/pagination.dto.js';

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

  // storage_key ของ pet_media เป็น unique — URL รูปต้องไม่ซ้ำกันข้ามการรันเทสต์ (DB ในเครื่องไม่ได้ล้างทุกรอบ)
  const img = (name: string) => `http://cdn.test/petpaws-media/uploads/${randomUUID()}-${name}`;
  const [url_a, url_1, url_2, url_x] = [img('a.jpg'), img('1.jpg'), img('2.jpg'), img('x.jpg')];

  describe('pets', () => {
    const slugs = async (n: number) =>
      (await pool.query<{ slug: string }>(`SELECT slug FROM traits WHERE is_active ORDER BY sort_order LIMIT $1`, [n])).rows.map((r) => r.slug);

    it('ลงประกาศพร้อมรูปและแท็ก ได้ JSON รูปทรงเดิมที่แอปใช้', async () => {
      const pets = app.get(PetsService);
      const owner = await newUser({ displayName: 'เจ้าของน้อง' });
      const tags = await slugs(2);

      const dog = await pets.create(owner, {
        name: ' ข้าวตัง ',
        species: 'cat',
        breed: '',
        gender: 'เพศเมีย',
        province: 'เชียงใหม่',
        age: '2 ปี',
        weight: '4.5',
        story: 'ขี้อ้อน',
        tags: [...tags, 'ไม่มีแท็กนี้'],
        imageUrl: url_a,
      });

      expect(dog).toMatchObject({
        ownerId: owner,
        ownerName: 'เจ้าของน้อง',
        ownerAvatar: '',
        name: 'ข้าวตัง',
        species: 'cat',
        speciesOther: '',
        breed: 'พันทาง',
        province: 'เชียงใหม่',
        age: '2 ปี',
        story: 'ขี้อ้อน',
        imageUrl: url_a,
        engagementLikes: 0,
        tags,
      });
      const media = await pool.query(`SELECT storage_key, sort_order FROM pet_media WHERE pet_id = $1`, [dog.id]);
      // storage_key = path หลัง host (ไว้ให้งานกวาดไฟล์ค้างหาไฟล์เจอ)
      expect(media.rows).toEqual([{ storage_key: new URL(url_a).pathname.slice(1), sort_order: 0 }]);
    });

    it('แก้ไขบางช่อง: ข้อความ "อื่น ๆ" ใช้ได้เฉพาะสัตว์ชนิด other, ได้บ้านแล้วตั้ง adopted_at, รูปใหม่แทนรูปเดิม', async () => {
      const pets = app.get(PetsService);
      const owner = await newUser();
      const created = await pets.create(owner, {
        gender: 'ผู้',
        name: 'โมจิ',
        species: 'other',
        speciesOther: 'เม่น',
        province: 'ภูเก็ต',
        age: '1 ปี',
        imageUrl: url_1,
      });

      const renamed = await pets.update(created.id, owner, {
        speciesOther: 'เม่นแคระ',
        imageUrl: url_2,
      });
      expect(renamed).toMatchObject({ speciesOther: 'เม่นแคระ', imageUrl: url_2 });

      const toDog = await pets.update(created.id, owner, { species: 'dog' });
      expect(toDog).toMatchObject({ species: 'dog', speciesOther: '' });
      const stillDog = await pets.update(created.id, owner, { speciesOther: 'แอบใส่' });
      expect(stillDog.speciesOther).toBe('');

      await pets.update(created.id, owner, { status: 'ถูกรับเลี้ยงแล้ว' });
      const row = (await pool.query(`SELECT status, adopted_at FROM pets WHERE id = $1`, [created.id])).rows[0];
      expect(row.status).toBe('adopted');
      expect(row.adopted_at).toBeInstanceOf(Date);
      expect((await pool.query(`SELECT count(*)::int AS n FROM pet_media WHERE pet_id = $1`, [created.id])).rows[0].n).toBe(1);
    });

    it('แก้ประกาศคนอื่นไม่ได้ / ลบแล้วหายไป (soft delete)', async () => {
      const pets = app.get(PetsService);
      const [owner, other] = [await newUser(), await newUser()];
      const dog = await pets.create(owner, { gender: 'ผู้', name: 'ถั่ว', province: 'ระยอง', age: '3 เดือน' });

      await expect(pets.update(dog.id, other, { name: 'ขโมย' })).rejects.toMatchObject({ code: 'FORBIDDEN' });
      await pets.remove(dog.id, owner);

      await expect(pets.findOne(dog.id)).rejects.toMatchObject({ code: 'NOT_FOUND' });
      expect((await pool.query(`SELECT status FROM pets WHERE id = $1`, [dog.id])).rows[0].status).toBe('cancelled');
    });

    it('ถูกใจ/เลิกถูกใจ: like_count ตาม trigger, ปัดซ้ำไม่ error, ประกาศที่ไม่มีได้ 404, รายการถูกใจเรียงล่าสุดก่อน', async () => {
      const pets = app.get(PetsService);
      const [owner, fan] = [await newUser(), await newUser()];
      const a = await pets.create(owner, { gender: 'ผู้', name: 'เอ', province: 'น่าน', age: '1 ปี' });
      const b = await pets.create(owner, { gender: 'ผู้', name: 'บี', province: 'น่าน', age: '1 ปี' });

      await pets.like(a.id, fan);
      await pets.like(a.id, fan);
      await pets.like(b.id, fan);
      expect((await pets.findOne(a.id)).engagementLikes).toBe(1);
      expect((await pets.myLikes(fan)).map((d) => d.id)).toEqual([b.id, a.id]);

      await pets.unlike(a.id, fan);
      expect((await pets.findOne(a.id)).engagementLikes).toBe(0);
      await expect(pets.like(randomUUID(), fan)).rejects.toMatchObject({ code: 'NOT_FOUND' });
    });

    it('deck: แบ่งหน้าด้วย cursor ไม่ซ้ำกัน กรองชนิดได้ และไม่มีประกาศของตัวเอง', async () => {
      const pets = app.get(PetsService);
      const [owner, viewer] = [await newUser(), await newUser()];
      for (let i = 0; i < 5; i++) await pets.create(owner, { gender: 'ผู้', name: `แมว${i}`, species: 'cat', province: 'ตาก', age: '1 ปี' });
      await pets.create(viewer, { gender: 'ผู้', name: 'ของฉันเอง', species: 'cat', province: 'ตาก', age: '1 ปี' });

      const first = await pets.deck(viewer, { species: 'cat', limit: 3 });
      const second = await pets.deck(viewer, { species: 'cat', limit: 3, cursor: first.nextCursor! });

      const all = [...first.dogs, ...second.dogs];
      expect(new Set(all.map((d) => d.id)).size).toBe(all.length);
      expect(all.every((d) => d.species === 'cat' && d.ownerId !== viewer)).toBe(true);
      expect(first.hasMore).toBe(true);
    });

    it('ประกาศทั้งหมดของเจ้าของ เรียงใหม่สุดก่อน', async () => {
      const pets = app.get(PetsService);
      const owner = await newUser();
      const a = await pets.create(owner, { gender: 'ผู้', name: 'แรก', province: 'ลำพูน', age: '1 ปี' });
      const b = await pets.create(owner, { gender: 'ผู้', name: 'สอง', province: 'ลำพูน', age: '1 ปี' });

      expect((await pets.findByOwner(owner, { cached: false })).map((d) => d.id)).toEqual([b.id, a.id]);
    });
  });

  describe('admin', () => {
    it('รายงานถึงเกณฑ์ → แบนชั่วคราว (session ถูกเพิกถอน รายงานปิด) → ปลดแบน', async () => {
      const admin = app.get(AdminService);
      const [adminId, bad, r1, r2] = [await newUser(), await newUser(), await newUser(), await newUser()];
      for (const reporter of [r1, r2]) {
        await pool.query(`INSERT INTO reports (reporter_id, reported_user_id, reason) VALUES ($1, $2, 'spam')`, [reporter, bad]);
      }
      await pool.query(
        `INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
         VALUES ($1, $2, gen_random_uuid(), now() + interval '1 day')`,
        [bad, randomUUID().replace(/-/g, '').padEnd(64, '0')],
      );

      const reported = await admin.reportedUsers(2, resolvePaging({ pageSize: 100 }));
      expect(reported.items.find((u) => u.id === bad)).toMatchObject({ reportCount: 2 });

      const banned = await admin.ban(adminId, bad, { days: 7, note: 'สแปม' });
      expect(banned.suspendedUntil).toBeInstanceOf(Date);
      const live = await pool.query(`SELECT count(*)::int AS n FROM refresh_tokens WHERE user_id = $1 AND revoked_at IS NULL`, [bad]);
      expect(live.rows[0].n).toBe(0);
      expect((await pool.query(`SELECT DISTINCT status FROM reports WHERE reported_user_id = $1`, [bad])).rows).toEqual([{ status: 'actioned' }]);
      const bannedList = await admin.bannedUsers(resolvePaging({ pageSize: 100 }));
      expect(bannedList.items.find((u) => u.id === bad)).toMatchObject({ permanent: false });

      await admin.unban(bad);
      expect((await pool.query(`SELECT is_suspended FROM users WHERE id = $1`, [bad])).rows[0].is_suspended).toBe(false);
      await expect(admin.unban(randomUUID())).rejects.toMatchObject({ code: 'NOT_FOUND' });
    });

    it('แบนแล้ว access token เดิมใช้ต่อไม่ได้ทันที (ไม่ต้องรอ token หมดอายุ) / ปลดแบนแล้วใช้ได้อีก', async () => {
      const admin = app.get(AdminService);
      const [adminId, user] = [await newUser(), await newUser()];
      const token = bearer(user);
      await request(app.getHttpServer()).get('/users/me').set('Authorization', token).expect(200);

      await admin.ban(adminId, user, {});
      const denied = await request(app.getHttpServer()).get('/users/me').set('Authorization', token).expect(401);
      // e2e ไม่ได้ใส่ AllExceptionsFilter ของ main.ts — ข้อความอยู่ใน body.message แทน body.error.message
      expect(JSON.stringify(denied.body)).toContain('บัญชีนี้ถูกระงับการใช้งาน');

      await admin.unban(user);
      await request(app.getHttpServer()).get('/users/me').set('Authorization', token).expect(200);
    });

    it('แบนแอดมินด้วยกันไม่ได้ / แบนถาวร / ปัดตกรายงานคืนจำนวนที่ปัด', async () => {
      const admin = app.get(AdminService);
      const [adminId, otherAdmin, target, reporter] = [await newUser(), await newUser(), await newUser(), await newUser()];
      await pool.query(`UPDATE users SET is_admin = true WHERE id = $1`, [otherAdmin]);

      await expect(admin.ban(adminId, otherAdmin, {})).rejects.toMatchObject({ code: 'FORBIDDEN' });
      await expect(admin.ban(adminId, target, {})).resolves.toEqual({ success: true, suspendedUntil: null });

      await pool.query(`INSERT INTO reports (reporter_id, reported_user_id, reason) VALUES ($1, $2, 'spam')`, [reporter, otherAdmin]);
      await expect(admin.dismissReports(adminId, otherAdmin)).resolves.toEqual({ success: true, dismissed: 1 });
    });

    it('โปรไฟล์ผู้ใช้ + ประกาศพร้อมรูป + สรุปตัวเลข', async () => {
      const admin = app.get(AdminService);
      const pets = app.get(PetsService);
      const owner = await newUser();
      await pets.create(owner, { gender: 'ผู้', name: 'มีรูป', province: 'แพร่', age: '1 ปี', imageUrl: url_x });

      const profile = await admin.userProfile(owner);

      expect(profile.pets).toHaveLength(1);
      expect(profile.pets[0].photos).toEqual([{ url: url_x, thumbUrl: null }]);
      const summary = await admin.summary();
      expect(Object.values(summary).every((n) => typeof n === 'number')).toBe(true);
    });
  });
});
