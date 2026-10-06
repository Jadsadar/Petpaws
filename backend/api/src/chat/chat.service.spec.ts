import { describe, expect, it, vi } from 'vitest';
import type { Queue } from 'bullmq';
import type { DataSource, Repository } from 'typeorm';
import { ChatService } from './chat.service.js';
import type { ChatGateway } from './chat.gateway.js';
import type { ChatMediaService } from './chat-media.service.js';
import type { Conversation, Message } from '../database/entities/index.js';

// พฤติกรรมของแชทกับ DB จริง (ส่ง/ส่งซ้ำ/แข่งกันสร้างห้อง/แจ้งเตือน/แบ่งหน้า) อยู่ใน test/chat.e2e-spec.ts
// ที่นี่เหลือเฉพาะกรณีที่ต้องจำลอง DB ล่ม ซึ่งทำกับ DB จริงไม่ได้
const ME = '11111111-1111-1111-1111-111111111111';
const OTHER = '22222222-2222-2222-2222-222222222222';
const CHAT = '33333333-3333-3333-3333-333333333333';

describe('ChatService — DB ล่มตอนอ่านสถานะกล่องข้อความ', () => {
  it('ยังแจ้งเตือนแบบไม่มีข้อมูลแนบ (แอปถอยไปดึงใหม่เอง) และไม่ทำให้ request พัง', async () => {
    const gateway = { emitNewMessage: vi.fn(), emitRead: vi.fn(), notifyUsers: vi.fn() };
    const dataSource = {
      getRepository: () => ({ upsert: vi.fn().mockResolvedValue({}) }),
      query: vi.fn().mockRejectedValue(new Error('connection reset')),
    };
    const conversations = {
      findOne: vi.fn().mockResolvedValue({ initiatorId: ME, ownerId: OTHER, status: 'active', closedReason: null }),
    };
    const service = new ChatService(
      dataSource as unknown as DataSource,
      conversations as unknown as Repository<Conversation>,
      {} as Repository<Message>,
      gateway as unknown as ChatGateway,
      {} as ChatMediaService,
      {} as Queue,
    );

    await expect(service.hide(ME, CHAT)).resolves.toEqual({ success: true });
    expect(gateway.notifyUsers).toHaveBeenCalledWith([ME], { type: 'hidden', conversationId: CHAT });
  });
});
