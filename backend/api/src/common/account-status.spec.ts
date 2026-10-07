import { afterEach, describe, expect, it, vi } from 'vitest';
import type { DataSource } from 'typeorm';
import { ACCOUNT_STATUS_TTL_MS, AccountStatusService } from './account-status.js';

/** findOne คืนแถวผู้ใช้ตามที่กำหนด (null = ไม่พบ/ถูกลบ) และนับว่าถาม DB กี่ครั้ง */
function setup(user: { isSuspended: boolean; suspendedUntil: Date | null } | null) {
  const findOne = vi.fn().mockResolvedValue(user && { id: 'u1', ...user });
  const dataSource = { getRepository: () => ({ findOne }) } as unknown as DataSource;
  return { service: new AccountStatusService(dataSource), findOne };
}

describe('AccountStatusService', () => {
  afterEach(() => vi.useRealTimers());

  it('บัญชีปกติ = active และจำผลไว้ ไม่ถาม DB ทุก request', async () => {
    const { service, findOne } = setup({ isSuspended: false, suspendedUntil: null });

    expect(await service.status('u1')).toBe('active');
    expect(await service.status('u1')).toBe('active');
    expect(findOne).toHaveBeenCalledTimes(1);
  });

  it('จำไว้ไม่เกิน 30 วินาที แล้วถาม DB ใหม่', async () => {
    vi.useFakeTimers();
    const { service, findOne } = setup({ isSuspended: false, suspendedUntil: null });
    await service.status('u1');

    vi.advanceTimersByTime(ACCOUNT_STATUS_TTL_MS + 1);
    await service.status('u1');

    expect(findOne).toHaveBeenCalledTimes(2);
  });

  it('ไม่พบ/ถูกลบ = missing, แบนถาวรหรือยังไม่หมดเวลา = suspended, แบนหมดเวลาแล้ว = active', async () => {
    const future = new Date(Date.now() + 60_000);
    const past = new Date(Date.now() - 60_000);
    expect(await setup(null).service.status('u1')).toBe('missing');
    expect(await setup({ isSuspended: true, suspendedUntil: null }).service.status('u1')).toBe('suspended');
    expect(await setup({ isSuspended: true, suspendedUntil: future }).service.status('u1')).toBe('suspended');
    expect(await setup({ isSuspended: true, suspendedUntil: past }).service.status('u1')).toBe('active');
  });

  it('forget (ตอนแบน/ปลดแบน) = request ถัดไปอ่าน DB ใหม่ทันที', async () => {
    const { service, findOne } = setup({ isSuspended: false, suspendedUntil: null });
    await service.status('u1');

    service.forget('u1');
    await service.status('u1');

    expect(findOne).toHaveBeenCalledTimes(2);
  });
});
