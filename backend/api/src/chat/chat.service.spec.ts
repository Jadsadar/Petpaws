import { describe, expect, it, vi } from 'vitest';
import type { Pool } from 'pg';
import type { Queue } from 'bullmq';
import { ChatService } from './chat.service.js';
import type { ChatGateway } from './chat.gateway.js';
import type { ChatMediaService } from './chat-media.service.js';

const ME = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';
const CHAT = '33333333-3333-3333-3333-333333333333';
const PET = '44444444-4444-4444-4444-444444444444';

const conversation = { initiator_id: ME, owner_id: OTHER, status: 'active', closed_reason: null };
const messageRow = {
  id: 'm1',
  sender_id: OTHER,
  body: 'สวัสดี',
  kind: 'user',
  media_type: null,
  media_url: null,
  thumbnail_url: null,
  media_width: null,
  media_height: null,
  media_duration_ms: null,
  created_at: new Date('2026-10-06T10:00:00Z'),
  read_at: null,
};
const inboxRow = (userId: string, unreadCount: number, unreadTotal: number) => ({
  user_id: userId,
  unread_count: unreadCount,
  unread_total: unreadTotal,
  last_message: '📷 รูปภาพ',
  last_message_at: new Date('2026-10-06T10:00:00Z'),
  status: 'active',
  closed_reason: null,
  pet_name: 'ข้าวตัง',
});

/** ตอบ query ตามข้อความ SQL — แต่ละ test ใส่เฉพาะที่ใช้ */
function setup(answers: Array<[RegExp, unknown[] | Error]>) {
  const query = vi.fn(async (sql: string) => {
    const hit = answers.find(([re]) => re.test(sql));
    if (!hit) throw new Error(`ไม่ได้เตรียมคำตอบให้ SQL: ${sql.slice(0, 80)}`);
    if (hit[1] instanceof Error) throw hit[1];
    return { rows: hit[1], rowCount: hit[1].length };
  });
  const gateway = { emitNewMessage: vi.fn(), emitRead: vi.fn(), notifyUsers: vi.fn() };
  const service = new ChatService(
    { query } as unknown as Pool,
    gateway as unknown as ChatGateway,
    {} as ChatMediaService,
    { add: vi.fn().mockResolvedValue(undefined) } as unknown as Queue,
  );
  return { service, query, gateway };
}

const PARTICIPANT = /FROM conversations WHERE id = \$1/;
const MESSAGES = /FROM messages\s+WHERE conversation_id/;
const BLOCKS = /FROM blocks WHERE blocker_id/;
const INBOX = /unnest\(\$2::uuid\[\]\)/;

describe('ChatService.lookup', () => {
  it('เจอห้องเดิม คืน chatId ด้วย query เดียว (ไม่โหลดกล่องข้อความทั้งก้อน)', async () => {
    const { service, query } = setup([[/WHERE c\.pet_id = \$1/, [{ id: CHAT }]]]);

    await expect(service.lookup(ME, { petId: PET, otherUserId: OTHER })).resolves.toEqual({ chatId: CHAT });
    expect(query).toHaveBeenCalledTimes(1);
    expect(query.mock.calls[0][1]).toEqual([PET, ME, OTHER]);
  });

  it('ยังไม่เคยคุย (หรือลบห้องไปแล้ว) คืน null', async () => {
    const { service } = setup([[/WHERE c\.pet_id = \$1/, []]]);

    await expect(service.lookup(ME, { petId: PET, otherUserId: OTHER })).resolves.toEqual({ chatId: null });
  });
});

describe('ChatService.messages', () => {
  it('ไม่ขอ include = array เหมือนเดิม (แอปรุ่นเก่ายังใช้ได้)', async () => {
    const { service } = setup([
      [PARTICIPANT, [conversation]],
      [MESSAGES, [messageRow]],
    ]);

    const out = await service.messages(ME, CHAT);

    expect(Array.isArray(out)).toBe(true);
    expect(out).toMatchObject([{ id: 'm1', text: 'สวัสดี' }]);
  });

  it('include=room แนบสถานะห้องมาในคำขอเดียว — ไม่ต้องยิง GET /chats/:id แยก', async () => {
    const { service } = setup([
      [PARTICIPANT, [{ ...conversation, status: 'closed', closed_reason: 'adopted' }]],
      [MESSAGES, [messageRow]],
      [BLOCKS, [{ '?column?': 1 }]],
    ]);

    const out = await service.messages(ME, CHAT, { include: 'room' });

    expect(out).toEqual({
      messages: [expect.objectContaining({ id: 'm1' })],
      room: { id: CHAT, status: 'closed', closedReason: 'adopted', otherUserId: OTHER, blockedByMe: true },
    });
  });

  it('detail ยังตอบรูปแบบเดิม (ใช้ตอนบล็อก/ปลดบล็อก/ข้อความระบบ)', async () => {
    const { service } = setup([
      [PARTICIPANT, [conversation]],
      [BLOCKS, []],
    ]);

    await expect(service.detail(ME, CHAT)).resolves.toEqual({
      id: CHAT,
      status: 'active',
      closedReason: null,
      otherUserId: OTHER,
      blockedByMe: false,
    });
  });
});

describe('ChatService notification (กล่องข้อความ)', () => {
  it('แนบสถานะห้อง + badge ของ "แต่ละคน" แยกกัน แอปอัปเดตเองได้ไม่ต้องดึง GET /chats ใหม่', async () => {
    const { service, gateway } = setup([
      [PARTICIPANT, [conversation]],
      [/mark_conversation_read/, []],
      [INBOX, [inboxRow(ME, 0, 3)]],
    ]);

    await service.markRead(ME, CHAT);

    expect(gateway.notifyUsers).toHaveBeenCalledWith([ME], {
      type: 'read',
      conversationId: CHAT,
      room: {
        lastMessage: '📷 รูปภาพ',
        lastMessageAt: new Date('2026-10-06T10:00:00Z'),
        unreadCount: 0,
        status: 'active',
        closedReason: null,
        petName: 'ข้าวตัง',
      },
      unreadTotal: 3,
    });
  });

  it('ข้อความระบบ: แจ้งทั้งสองฝั่ง แต่ละคนได้ตัวเลขของตัวเอง', async () => {
    const { service, gateway } = setup([
      [
        /m\.kind = 'system'/,
        [
          {
            id: 'sys1',
            conversation_id: CHAT,
            sender_id: OTHER,
            body: 'น้องได้บ้านแล้ว',
            created_at: new Date(),
            initiator_id: ME,
            owner_id: OTHER,
          },
        ],
      ],
      [INBOX, [inboxRow(ME, 2, 5), inboxRow(OTHER, 0, 0)]],
    ]);

    await service.broadcastSystemMessages(PET, new Date());

    const byUser = new Map(gateway.notifyUsers.mock.calls.map(([ids, p]) => [ids[0], p]));
    expect(byUser.get(ME)).toMatchObject({ type: 'message', unreadTotal: 5, room: { unreadCount: 2 } });
    expect(byUser.get(OTHER)).toMatchObject({ type: 'message', unreadTotal: 0, room: { unreadCount: 0 } });
  });

  it('อ่านสถานะไม่ได้ ยังแจ้งเตือนแบบไม่มีข้อมูลแนบ (แอปถอยไปดึงใหม่เอง) ไม่ทำให้ request พัง', async () => {
    const { service, gateway } = setup([
      [PARTICIPANT, [conversation]],
      [/INSERT INTO conversation_hides/, []],
      [INBOX, new Error('connection reset')],
    ]);

    await expect(service.hide(ME, CHAT)).resolves.toEqual({ success: true });
    expect(gateway.notifyUsers).toHaveBeenCalledWith([ME], { type: 'hidden', conversationId: CHAT });
  });
});
