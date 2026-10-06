import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import type { Pool } from 'pg';
import { randomUUID } from 'node:crypto';
import { vi } from 'vitest';
import { AppModule } from './../src/app.module.js';
import { PG_POOL } from './../src/database/database.module.js';
import { ChatService } from './../src/chat/chat.service.js';
import { ChatGateway } from './../src/chat/chat.gateway.js';
import { PetsService } from './../src/pets/pets.service.js';

// แชทกับ DB จริง: ส่งข้อความ, กันส่งซ้ำด้วย clientId (รวมคำขอซ้ำที่มาถึงพร้อมกันจริง ๆ),
// แข่งกันสร้างห้อง, แบ่งหน้า, ซ่อนห้อง, สถานะห้อง และข้อมูลที่แนบไปกับการแจ้งเตือนกล่องข้อความ
describe('chat (e2e กับ DB จริง)', () => {
  let app: INestApplication;
  let pool: Pool;
  let chat: ChatService;
  let gateway: ChatGateway;

  const newUser = async () => {
    const tag = randomUUID().slice(0, 8);
    const res = await pool.query<{ id: string }>(
      // username (citext) กับ display_name (varchar) คนละชนิด — ใช้ $1 ซ้ำสองคอลัมน์ Postgres เดาชนิดไม่ได้
      `INSERT INTO users (username, email, password_hash, display_name) VALUES ($1, $2, 'x', $3) RETURNING id`,
      [`e2e_${tag}`, `e2e_${tag}@e2e.test`, `e2e_${tag}`],
    );
    return res.rows[0].id;
  };
  const newPet = async (ownerId: string) =>
    (await pool.query<{ id: string }>(
      `INSERT INTO pets (owner_id, name, location) VALUES ($1, 'น้องแชท', 'กรุงเทพมหานคร') RETURNING id`,
      [ownerId],
    )).rows[0].id;
  /** ผู้สนใจทักเจ้าของ = ห้องใหม่พร้อมข้อความแรก */
  const room = async () => {
    const [me, owner] = [await newUser(), await newUser()];
    const petId = await newPet(owner);
    const { chatId } = await chat.createOrSend(me, { petId, message: 'สวัสดีครับ' });
    return { me, owner, petId, chatId };
  };
  const count = async (sql: string, params: unknown[]) => (await pool.query<{ n: number }>(sql, params)).rows[0].n;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleFixture.createNestApplication();
    await app.init();
    pool = app.get<Pool>(PG_POOL);
    chat = app.get(ChatService);
    gateway = app.get(ChatGateway);
  });

  afterEach(() => vi.restoreAllMocks());

  afterAll(async () => {
    await app.close();
  });

  describe('ส่งข้อความ + กันส่งซ้ำ (clientId)', () => {
    it('ข้อความใหม่บันทึก clientId และแนบไปกับ event ให้แอปจับคู่กับข้อความที่รอส่ง', async () => {
      const { me, chatId } = await room();
      const emit = vi.spyOn(gateway, 'emitNewMessage');
      const clientId = randomUUID();

      const { message } = await chat.sendMessage(me, chatId, { text: 'ข้อความสอง', clientId });

      expect(message).toMatchObject({ senderId: me, text: 'ข้อความสอง', clientId, media: null });
      expect(emit).toHaveBeenCalledWith(chatId, expect.objectContaining({ id: message.id, clientId }));
      expect(await count(`SELECT count(*)::int AS n FROM messages WHERE client_id = $1`, [clientId])).toBe(1);
    });

    it('ส่งซ้ำด้วย clientId เดิม (คำตอบรอบแรกหาย): ได้ข้อความเดิม ไม่บันทึก/แจ้งเตือนซ้ำ', async () => {
      const { me, chatId } = await room();
      const clientId = randomUUID();
      const first = await chat.sendMessage(me, chatId, { text: 'ครั้งเดียวพอ', clientId });
      const emit = vi.spyOn(gateway, 'emitNewMessage');

      const again = await chat.sendMessage(me, chatId, { text: 'ครั้งเดียวพอ', clientId });

      expect(again.message.id).toBe(first.message.id);
      expect(emit).not.toHaveBeenCalled();
      expect(await count(`SELECT count(*)::int AS n FROM messages WHERE client_id = $1`, [clientId])).toBe(1);
    });

    it('คำขอซ้ำสองอันมาถึงพร้อมกันจริง ๆ: ได้ข้อความเดียวกันทั้งคู่ บันทึกแถวเดียว', async () => {
      const { me, chatId } = await room();
      const clientId = randomUUID();

      const [a, b] = await Promise.all([
        chat.sendMessage(me, chatId, { text: 'กดรัว', clientId }),
        chat.sendMessage(me, chatId, { text: 'กดรัว', clientId }),
      ]);

      expect(a.message.id).toBe(b.message.id);
      expect(await count(`SELECT count(*)::int AS n FROM messages WHERE client_id = $1`, [clientId])).toBe(1);
    });

    it('แอปรุ่นก่อน (ไม่ส่ง clientId) ส่งได้ตามเดิม', async () => {
      const { me, chatId } = await room();
      await expect(chat.sendMessage(me, chatId, { text: 'แอปเก่า' })).resolves.toMatchObject({ message: { clientId: null } });
    });

    it('ข้อความแรกสองอันแข่งกันสร้างห้องพร้อมกัน: ได้ห้องเดียวกัน ข้อความครบทั้งสอง', async () => {
      const [me, owner] = [await newUser(), await newUser()];
      const petId = await newPet(owner);

      const [a, b] = await Promise.all([
        chat.createOrSend(me, { petId, message: 'หนึ่ง', clientId: randomUUID() }),
        chat.createOrSend(me, { petId, message: 'สอง', clientId: randomUUID() }),
      ]);

      expect(a.chatId).toBe(b.chatId);
      expect(await count(`SELECT count(*)::int AS n FROM conversations WHERE pet_id = $1`, [petId])).toBe(1);
      expect(await count(`SELECT count(*)::int AS n FROM messages WHERE conversation_id = $1`, [a.chatId])).toBe(2);
    });

    it('ทักประกาศตัวเองไม่ได้ / บล็อกกันแล้วทักไม่ได้ / ข้อความว่างไม่ได้', async () => {
      const [me, owner] = [await newUser(), await newUser()];
      const petId = await newPet(owner);

      await expect(chat.createOrSend(owner, { petId, message: 'x' })).rejects.toMatchObject({ code: 'FORBIDDEN' });
      await expect(chat.createOrSend(me, { petId, message: '   ' })).rejects.toMatchObject({ code: 'EMPTY_MESSAGE' });
      await pool.query(`INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [owner, me]);
      await expect(chat.createOrSend(me, { petId, message: 'x' })).rejects.toMatchObject({ code: 'FORBIDDEN' });
    });
  });

  describe('อ่านข้อความ', () => {
    it('แบ่งหน้าแบบ keyset: หน้าถัดไปต่อจากหน้าแรกพอดี ไม่ซ้ำ ไม่หาย เรียงเก่า → ใหม่', async () => {
      const { me, chatId } = await room();
      for (let i = 1; i <= 5; i++) await chat.sendMessage(me, chatId, { text: `m${i}` });

      const latest = (await chat.messages(me, chatId, { limit: 3 })) as { text: string; id: string }[];
      const older = (await chat.messages(me, chatId, { limit: 3, before: latest[0].id })) as { text: string }[];

      expect(latest.map((m) => m.text)).toEqual(['m3', 'm4', 'm5']);
      expect(older.map((m) => m.text)).toEqual(['สวัสดีครับ', 'm1', 'm2']);
    });

    it('include=room แนบสถานะห้อง (ปิดเพราะบล็อก) / detail ตอบรูปแบบเดิม / คนนอกห้องอ่านไม่ได้', async () => {
      const { me, owner, chatId } = await room();
      await pool.query(`INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [me, owner]);

      const res = (await chat.messages(me, chatId, { include: 'room' })) as { messages: unknown[]; room: unknown };

      expect(res.messages).toHaveLength(1);
      expect(res.room).toEqual({ id: chatId, status: 'closed', closedReason: 'blocked', otherUserId: owner, blockedByMe: true });
      await expect(chat.detail(owner, chatId)).resolves.toMatchObject({ blockedByMe: false, otherUserId: me });
      await expect(chat.messages(await newUser(), chatId)).rejects.toMatchObject({ code: 'FORBIDDEN' });
    });

    it('ห้องที่ปิดแล้วส่งข้อความใหม่ไม่ได้', async () => {
      const { me, owner, chatId } = await room();
      await pool.query(`INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2)`, [owner, me]);
      await expect(chat.sendMessage(me, chatId, { text: 'ยังอยู่ไหม' })).rejects.toMatchObject({ code: 'FORBIDDEN' });
    });
  });

  describe('กล่องข้อความ', () => {
    it('lookup หาห้องเดิมได้ / ซ่อนห้องแล้วหาไม่เจอและไม่อยู่ในรายการ / มีข้อความใหม่ห้องกลับมา', async () => {
      const { me, owner, petId, chatId } = await room();

      expect(await chat.lookup(me, { petId, otherUserId: owner })).toEqual({ chatId });
      await chat.hide(me, chatId);
      expect(await chat.lookup(me, { petId, otherUserId: owner })).toEqual({ chatId: null });
      expect((await chat.list(me)).some((c) => c.id === chatId)).toBe(false);
      expect(await chat.messages(me, chatId)).toEqual([]);

      await new Promise((r) => setTimeout(r, 5));
      await chat.sendMessage(owner, chatId, { text: 'กลับมาคุยกัน' });
      expect((await chat.list(me)).find((c) => c.id === chatId)).toMatchObject({ otherUserId: owner, unreadCount: 1 });
    });

    it('อ่านแล้ว: unread ของห้องเป็น 0 และแจ้งเตือนแนบสถานะห้อง + ยอดรวมของคนนั้น', async () => {
      const { owner, chatId } = await room();
      expect((await chat.unreadCount(owner)).count).toBe(1);
      const notify = vi.spyOn(gateway, 'notifyUsers');

      await chat.markRead(owner, chatId);

      expect((await chat.unreadCount(owner)).count).toBe(0);
      expect(notify).toHaveBeenCalledWith([owner], expect.objectContaining({
        type: 'read',
        conversationId: chatId,
        unreadTotal: 0,
        room: expect.objectContaining({ unreadCount: 0, lastMessage: 'สวัสดีครับ', status: 'active', petName: 'น้องแชท' }),
      }));
    });

    it('สัตว์ได้บ้าน → ข้อความระบบ แจ้งทั้งสองฝั่ง แต่ละคนได้ตัวเลขของตัวเอง', async () => {
      const { me, owner, petId, chatId } = await room();
      const notify = vi.spyOn(gateway, 'notifyUsers');

      await app.get(PetsService).update(petId, owner, { status: 'ถูกรับเลี้ยงแล้ว' });

      const byUser = new Map(
        notify.mock.calls
          .filter(([, p]) => p.type === 'message' && p.conversationId === chatId)
          .map(([ids, p]) => [ids[0], p as { room: { status: string; unreadCount: number } }]),
      );
      // ผู้สนใจ: ข้อความระบบ 1 ยังไม่อ่าน / เจ้าของ: ข้อความแรกของผู้สนใจ 1 (ข้อความระบบเป็นชื่อเจ้าของเอง ไม่นับ)
      expect(byUser.get(me)?.room).toMatchObject({ status: 'closed', unreadCount: 1 });
      expect(byUser.get(owner)?.room).toMatchObject({ status: 'closed', unreadCount: 1 });
    });
  });
});
