import { describe, expect, it } from 'vitest';
import type { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ThrottlerStorageService } from '@nestjs/throttler';
import { AUTH_RATE_LIMITS, AppThrottlerGuard, DEFAULT_RATE_LIMIT } from './rate-limit.js';
import { AppException } from './app-exception.js';

// เรียก method protected ของ guard ตรง ๆ ใน test
type Exposed = {
  shouldSkip(ctx: ExecutionContext): Promise<boolean>;
  getTracker(req: Record<string, unknown>): Promise<string>;
  throwThrottlingException(ctx: ExecutionContext, detail: Record<string, unknown>): Promise<void>;
};

const guard = new AppThrottlerGuard(
  [DEFAULT_RATE_LIMIT],
  new ThrottlerStorageService(),
  new Reflector(),
) as unknown as Exposed;

const ctxOf = (type: string) => ({ getType: () => type }) as ExecutionContext;

describe('AppThrottlerGuard', () => {
  it('ข้าม WebSocket (ChatGateway ไม่มี HTTP request)', async () => {
    expect(await guard.shouldSkip(ctxOf('ws'))).toBe(true);
    expect(await guard.shouldSkip(ctxOf('http'))).toBe(false);
  });

  it('ล็อกอินแล้วนับต่อบัญชี ไม่ใช่ต่อ IP', async () => {
    expect(await guard.getTracker({ ip: '1.2.3.4', user: { id: 'u1' } })).toBe('user:u1');
    expect(await guard.getTracker({ ip: '1.2.3.4' })).toBe('ip:1.2.3.4');
  });

  it('เกินเพดาน = 429 รูปแบบ error เดียวกับทั้งระบบ พร้อมบอกเวลาที่ต้องรอ', async () => {
    const err = await guard
      .throwThrottlingException(ctxOf('http'), { timeToBlockExpire: 42, timeToExpire: 10 })
      .catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AppException);
    expect((err as AppException).getStatus()).toBe(429);
    expect((err as AppException).getResponse()).toMatchObject({ code: 'RATE_LIMITED' });
    expect((err as AppException).message).toBeDefined();
    expect(JSON.stringify((err as AppException).getResponse())).toContain('42');
  });
});

describe('AUTH_RATE_LIMITS.login', () => {
  const track = AUTH_RATE_LIMITS.login.getTracker;

  it('แยกนับต่ออีเมล — คนละบัญชีใน Wi-Fi เดียวกันไม่ล็อกกันเอง', () => {
    expect(track({ ip: '1.2.3.4', body: { email: 'a@x.com' } })).not.toBe(
      track({ ip: '1.2.3.4', body: { email: 'b@x.com' } }),
    );
  });

  it('ตัวพิมพ์/ช่องว่างของอีเมลไม่ช่วยหลบเพดาน', () => {
    expect(track({ ip: '1.2.3.4', body: { email: ' A@X.com ' } })).toBe(
      track({ ip: '1.2.3.4', body: { email: 'a@x.com' } }),
    );
  });
});
