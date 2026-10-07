import { describe, expect, it, vi } from 'vitest';
import type { DataSource, Repository } from 'typeorm';
import type { Block, Report } from '../database/entities/index.js';
import { ModerationService } from './moderation.service.js';
import { fakeQueryBuilder } from '../../test/helpers/typeorm-mock.js';

const msgRow = (over: Partial<{ sender_id: string; initiator_id: string; owner_id: string; kind: string }> = {}) => ({
  sender_id: 'other',
  initiator_id: 'me',
  owner_id: 'other',
  kind: 'user',
  ...over,
});

/** message = ผลของ query ตรวจสิทธิ์ (null = ไม่พบข้อความ) */
function setup(message: unknown = null) {
  const lookup = fakeQueryBuilder(message);
  const dataSource = { createQueryBuilder: vi.fn(() => lookup) } as unknown as DataSource;
  const reports = { insert: vi.fn().mockResolvedValue({ identifiers: [{ id: 'rep1' }] }) };
  const service = new ModerationService(
    dataSource,
    reports as unknown as Repository<Report>,
    {} as Repository<Block>,
  );
  return { service, reports, lookup };
}

describe('ModerationService.createReport — รายงานข้อความ', () => {
  const dto = { reportedMessageId: '11111111-1111-1111-1111-111111111111', reason: 'inappropriate' as const };

  it('คนในแชทรายงานข้อความของอีกฝ่ายได้ และบันทึกลง reports', async () => {
    const { service, reports } = setup(msgRow());

    await expect(service.createReport('me', dto)).resolves.toEqual({ id: 'rep1' });
    expect(reports.insert).toHaveBeenCalledWith({
      reporterId: 'me',
      reportedPetId: null,
      reportedUserId: null,
      reportedMessageId: dto.reportedMessageId,
      reason: 'inappropriate',
      detail: null,
    });
  });

  it('ฝั่งเจ้าของประกาศ (owner) ก็รายงานข้อความของผู้ทักได้', async () => {
    const { service } = setup(msgRow({ sender_id: 'other', initiator_id: 'other', owner_id: 'me' }));
    await expect(service.createReport('me', dto)).resolves.toEqual({ id: 'rep1' });
  });

  it('คนนอกแชทรายงานไม่ได้ (กันดึงแชทคนอื่นเข้าคิวแอดมิน) และไม่เขียนอะไรลง DB', async () => {
    const { service, reports } = setup(msgRow({ initiator_id: 'a', owner_id: 'b' }));

    await expect(service.createReport('me', dto)).rejects.toMatchObject({ code: 'FORBIDDEN' });
    expect(reports.insert).not.toHaveBeenCalled();
  });

  it('รายงานข้อความของตัวเองไม่ได้', async () => {
    const { service, reports } = setup(msgRow({ sender_id: 'me' }));

    await expect(service.createReport('me', dto)).rejects.toMatchObject({ code: 'INVALID_REPORT' });
    expect(reports.insert).not.toHaveBeenCalled();
  });

  it('ข้อความระบบรายงานไม่ได้', async () => {
    const { service } = setup(msgRow({ kind: 'system' }));
    await expect(service.createReport('me', dto)).rejects.toMatchObject({ code: 'INVALID_REPORT' });
  });

  it('ไม่พบข้อความ (หรือถูกลบแล้ว) → 404', async () => {
    const { service } = setup(undefined);
    await expect(service.createReport('me', dto)).rejects.toMatchObject({ code: 'NOT_FOUND' });
  });
});

describe('ModerationService.createReport — เป้าหมายอื่น', () => {
  it('รายงานประกาศไม่ต้องตรวจแชท บันทึกตรง ๆ', async () => {
    const { service, reports, lookup } = setup();

    await service.createReport('me', {
      reportedPetId: '22222222-2222-2222-2222-222222222222',
      reason: 'scam',
      detail: 'เรียกเงินมัดจำ',
    });

    expect(lookup.calls).toEqual([]);
    expect(reports.insert).toHaveBeenCalledWith(
      expect.objectContaining({ reportedPetId: '22222222-2222-2222-2222-222222222222', reason: 'scam', detail: 'เรียกเงินมัดจำ' }),
    );
  });
});
