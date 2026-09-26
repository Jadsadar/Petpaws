import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Job } from 'bullmq';
import type { Pool } from 'pg';
import type { DevicesService } from '../devices/devices.service.js';
import type { MessagePushJobData } from '../queue/queue.constants.js';
import type { FcmService, PushResult } from './fcm.service.js';
import { PushProcessor } from './push.processor.js';

const job = { data: { messageId: 'msg-1' } } as Job<MessagePushJobData>;
const messageRow = {
  conversation_id: 'conv-1',
  body: 'สวัสดีครับ สนใจน้องอยู่',
  sender_name: 'ภูผา ใจดี',
  recipient_id: 'user-owner',
};

function setup({
  enabled = true,
  rows = [messageRow] as unknown[],
  tokens = ['tok-a', 'tok-b'],
  result = { successCount: 2, deadTokens: [], retryableFailures: 0 } as PushResult,
} = {}) {
  const pool = { query: vi.fn().mockResolvedValue({ rows }) };
  const devices = {
    tokensForUser: vi.fn().mockResolvedValue(tokens),
    removeTokens: vi.fn().mockResolvedValue(undefined),
  };
  const fcm = { enabled, send: vi.fn().mockResolvedValue(result) };
  const processor = new PushProcessor(
    pool as unknown as Pool,
    devices as unknown as DevicesService,
    fcm as unknown as FcmService,
  );
  return { processor, pool, devices, fcm };
}

describe('PushProcessor', () => {
  beforeEach(() => vi.clearAllMocks());

  it('ข้ามทั้งหมดถ้ายังไม่ได้ตั้งค่า FCM', async () => {
    // Arrange
    const { processor, pool, fcm } = setup({ enabled: false });
    // Act
    const out = await processor.process(job);
    // Assert
    expect(out).toEqual({ skipped: 'fcm-disabled' });
    expect(pool.query).not.toHaveBeenCalled();
    expect(fcm.send).not.toHaveBeenCalled();
  });

  it('ข้อความถูกลบไปแล้วไม่ส่ง และไม่ throw (ไม่ต้อง retry)', async () => {
    const { processor, fcm } = setup({ rows: [] });

    const out = await processor.process(job);

    expect(out).toEqual({ skipped: 'message-gone' });
    expect(fcm.send).not.toHaveBeenCalled();
  });

  it('ผู้รับไม่มีเครื่องลงทะเบียนไว้ ไม่เรียก FCM', async () => {
    const { processor, fcm } = setup({ tokens: [] });

    const out = await processor.process(job);

    expect(out).toEqual({ skipped: 'no-tokens' });
    expect(fcm.send).not.toHaveBeenCalled();
  });

  it('ส่งหาคู่สนทนาอีกฝ่าย ใช้ชื่อผู้ส่งเป็นหัวข้อ และแนบ conversationId', async () => {
    const { processor, devices, fcm } = setup();

    const out = await processor.process(job);

    expect(devices.tokensForUser).toHaveBeenCalledWith('user-owner');
    expect(fcm.send).toHaveBeenCalledWith(
      ['tok-a', 'tok-b'],
      { title: 'ภูผา ใจดี', body: messageRow.body },
      { type: 'chat_message', conversationId: 'conv-1' },
    );
    expect(out).toEqual({ sent: 2, removedTokens: 0 });
  });

  it('ตัดข้อความยาวเหลือ 100 ตัวอักษร', async () => {
    const { processor, fcm } = setup({ rows: [{ ...messageRow, body: 'ก'.repeat(300) }] });

    await processor.process(job);

    expect(fcm.send.mock.calls[0][1].body).toHaveLength(100);
  });

  it('ลบ token ที่ FCM บอกว่าตายแล้ว', async () => {
    const { processor, devices } = setup({
      result: { successCount: 1, deadTokens: ['tok-b'], retryableFailures: 0 },
    });

    const out = await processor.process(job);

    expect(devices.removeTokens).toHaveBeenCalledWith(['tok-b']);
    expect(out).toEqual({ sent: 1, removedTokens: 1 });
  });

  it('throw ให้ BullMQ retry เมื่อไม่มีเครื่องไหนได้รับเลย (ปัญหาชั่วคราว)', async () => {
    const { processor, devices } = setup({
      result: { successCount: 0, deadTokens: [], retryableFailures: 2 },
    });

    await expect(processor.process(job)).rejects.toThrow('FCM ส่งไม่สำเร็จ');
    // ลบ token ตายก่อน throw เสมอ รอบ retry จะได้ไม่ยิงใส่ token ตายซ้ำ
    expect(devices.removeTokens).toHaveBeenCalled();
  });

  it('ไม่ retry ถ้ามีบางเครื่องได้รับแล้ว (กันเครื่องที่ได้แล้วเด้งซ้ำ)', async () => {
    const { processor } = setup({
      result: { successCount: 1, deadTokens: [], retryableFailures: 1 },
    });

    await expect(processor.process(job)).resolves.toEqual({ sent: 1, removedTokens: 0 });
  });

  it('token ตายหมดทุกตัวไม่ throw — retry ไปก็ไม่มีประโยชน์', async () => {
    const { processor } = setup({
      result: { successCount: 0, deadTokens: ['tok-a', 'tok-b'], retryableFailures: 0 },
    });

    await expect(processor.process(job)).resolves.toEqual({ sent: 0, removedTokens: 2 });
  });
});
