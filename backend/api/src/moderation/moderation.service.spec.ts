import { describe, expect, it, vi } from 'vitest';
import type { Pool } from 'pg';
import { ModerationService } from './moderation.service.js';

function poolWith(...results: { rows: unknown[] }[]) {
  const query = vi.fn();
  for (const r of results) query.mockResolvedValueOnce(r);
  return { pool: { query } as unknown as Pool, query };
}

const msgRow = (over: Partial<{ sender_id: string; initiator_id: string; owner_id: string }> = {}) => ({
  sender_id: 'other',
  initiator_id: 'me',
  owner_id: 'other',
  ...over,
});

describe('ModerationService.createReport — รายงานข้อความ', () => {
  const dto = { reportedMessageId: '11111111-1111-1111-1111-111111111111', reason: 'inappropriate' as const };

  it('คนในแชทรายงานข้อความของอีกฝ่ายได้ และบันทึกลง reports', async () => {
    const { pool, query } = poolWith({ rows: [msgRow()] }, { rows: [{ id: 'rep1' }] });

    const res = await new ModerationService(pool).createReport('me', dto);

    expect(res).toEqual({ id: 'rep1' });
    expect(query).toHaveBeenCalledTimes(2);
    expect(query.mock.calls[1][1]).toEqual(['me', null, null, dto.reportedMessageId, 'inappropriate', null]);
  });

  it('ฝั่งเจ้าของประกาศ (owner) ก็รายงานข้อความของผู้ทักได้', async () => {
    const { pool } = poolWith(
      { rows: [msgRow({ sender_id: 'other', initiator_id: 'other', owner_id: 'me' })] },
      { rows: [{ id: 'rep2' }] },
    );
    await expect(new ModerationService(pool).createReport('me', dto)).resolves.toEqual({ id: 'rep2' });
  });

  it('คนนอกแชทรายงานไม่ได้ (กันดึงแชทคนอื่นเข้าคิวแอดมิน) และไม่เขียนอะไรลง DB', async () => {
    const { pool, query } = poolWith({ rows: [msgRow({ initiator_id: 'a', owner_id: 'b' })] });

    await expect(new ModerationService(pool).createReport('me', dto)).rejects.toMatchObject({ code: 'FORBIDDEN' });
    expect(query).toHaveBeenCalledTimes(1); // มีแค่ query ตรวจสิทธิ์ ไม่มี INSERT
  });

  it('รายงานข้อความของตัวเองไม่ได้', async () => {
    const { pool, query } = poolWith({ rows: [msgRow({ sender_id: 'me' })] });

    await expect(new ModerationService(pool).createReport('me', dto)).rejects.toMatchObject({ code: 'INVALID_REPORT' });
    expect(query).toHaveBeenCalledTimes(1);
  });

  it('ไม่พบข้อความ (หรือถูกลบแล้ว) → 404', async () => {
    const { pool } = poolWith({ rows: [] });
    await expect(new ModerationService(pool).createReport('me', dto)).rejects.toMatchObject({ code: 'NOT_FOUND' });
  });
});

describe('ModerationService.createReport — เป้าหมายอื่น', () => {
  it('รายงานประกาศไม่ต้องตรวจแชท ยิง INSERT ตรงๆ ครั้งเดียว', async () => {
    const { pool, query } = poolWith({ rows: [{ id: 'rep3' }] });

    await new ModerationService(pool).createReport('me', {
      reportedPetId: '22222222-2222-2222-2222-222222222222',
      reason: 'scam',
      detail: 'เรียกเงินมัดจำ',
    });

    expect(query).toHaveBeenCalledTimes(1);
    expect(query.mock.calls[0][1]).toEqual(['me', '22222222-2222-2222-2222-222222222222', null, null, 'scam', 'เรียกเงินมัดจำ']);
  });
});
