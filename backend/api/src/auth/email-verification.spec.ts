import { describe, expect, it, vi } from 'vitest';
import { createHash } from 'node:crypto';
import type { ConfigService } from '@nestjs/config';
import type { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { AuthService } from './auth.service.js';
import { MailService } from '../mail/mail.service.js';
import { verificationEmail, verifyResultPage } from './email-templates.js';

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

function makeConfig(env: Record<string, string>) {
  return { get: (k: string) => env[k], getOrThrow: (k: string) => env[k] } as unknown as ConfigService;
}

/** ฐานข้อมูลจำลอง: จับคู่ SQL ด้วยข้อความ แล้วคืนแถวตามที่เทสต์กำหนด + จดทุกคำสั่งไว้ตรวจ */
function makePool(handlers: Array<[RegExp, (params: unknown[]) => { rows: unknown[] }]>) {
  const calls: Array<{ sql: string; params: unknown[] }> = [];
  const run = async (sql: string, params: unknown[] = []) => {
    calls.push({ sql, params });
    for (const [re, fn] of handlers) if (re.test(sql)) return fn(params);
    return { rows: [] };
  };
  const client = { query: vi.fn(run), release: vi.fn() };
  return { pool: { query: vi.fn(run), connect: async () => client } as never, calls, client };
}

function service(opts: { provider?: 'log' | 'brevo'; pool: never; apiKey?: boolean }) {
  const env: Record<string, string> = {
    JWT_ACCESS_SECRET: 'a',
    JWT_REFRESH_SECRET: 'r',
    JWT_ACCESS_TTL: '15m',
    JWT_REFRESH_TTL: '30d',
    APP_PUBLIC_URL: 'https://api.example.test/',
    ...(opts.provider ? { MAIL_PROVIDER: opts.provider } : {}),
    ...(opts.provider === 'brevo' && opts.apiKey !== false
      ? { BREVO_API_KEY: 'k', MAIL_FROM_EMAIL: 'noreply@example.test' }
      : {}),
  };
  const config = makeConfig(env);
  const mail = new MailService(config);
  const jwt = { sign: () => 'jwt' } as unknown as JwtService;
  return { auth: new AuthService(opts.pool, jwt, config, mail), mail };
}

const flush = () => new Promise((r) => setTimeout(r, 0));
const tokenFrom = (text: string) => /token=([A-Za-z0-9_-]+)/.exec(text)![1];

describe('MailService เปิด/ปิดตามการตั้งค่า', () => {
  it('ไม่ตั้ง provider = ปิดระบบ (ไม่บังคับยืนยันอีเมล)', () => {
    expect(new MailService(makeConfig({})).enabled).toBe(false);
  });
  it('brevo แต่ไม่มีคีย์ = ปิด ไม่ใช่ครึ่งๆ กลางๆ', () => {
    expect(new MailService(makeConfig({ MAIL_PROVIDER: 'brevo' })).enabled).toBe(false);
  });
  it('log และ brevo ที่ตั้งครบ = เปิด', () => {
    expect(new MailService(makeConfig({ MAIL_PROVIDER: 'log' })).enabled).toBe(true);
    expect(
      new MailService(makeConfig({ MAIL_PROVIDER: 'brevo', BREVO_API_KEY: 'k', MAIL_FROM_EMAIL: 'a@b.co' })).enabled,
    ).toBe(true);
  });
});

describe('สมัครสมาชิก → ส่งลิงก์ยืนยัน', () => {
  const insertUser: [RegExp, () => { rows: unknown[] }] = [/INSERT INTO users/, () => ({ rows: [{ id: 'u1' }] })];

  it('เปิดระบบอีเมล: ส่งอีเมลหนึ่งฉบับ มีลิงก์ถึง /auth/verify-email และเก็บเฉพาะ hash ของ token', async () => {
    const { pool, calls } = makePool([insertUser]);
    const { auth, mail } = service({ provider: 'log', pool });
    const res = await auth.register({ username: 'somchai', email: 'S@Example.com', password: 'Str0ng!Passw0rd#1' });
    await flush();

    expect(res).toEqual({ id: 'u1', verificationRequired: true });
    expect(mail.outbox).toHaveLength(1);
    const msg = mail.outbox[0];
    expect(msg.to).toBe('S@Example.com');
    expect(msg.text).toContain('https://api.example.test/auth/verify-email?token=');
    expect(msg.html).toContain('ยืนยันอีเมล');

    const token = tokenFrom(msg.text);
    const insert = calls.find((c) => /INSERT INTO email_verification_tokens/.test(c.sql))!;
    expect(insert.params[1]).toBe(sha256(token));
    expect(JSON.stringify(calls)).not.toContain(token); // token จริงไม่ถูกส่งลง DB เลย
  });

  it('ปิดระบบอีเมล: สมัครได้ตามเดิม ไม่ส่งอะไร', async () => {
    const { pool, calls } = makePool([insertUser]);
    const { auth, mail } = service({ pool });
    const res = await auth.register({ username: 'somchai', email: 's@example.com', password: 'Str0ng!Passw0rd#1' });
    await flush();
    expect(res).toEqual({ id: 'u1', verificationRequired: false });
    expect(mail.outbox).toHaveLength(0);
    expect(calls.some((c) => /email_verification_tokens/.test(c.sql))).toBe(false);
  });

  it('ผู้ให้บริการอีเมลล้ม: สมัครยังสำเร็จ (ผู้ใช้กดส่งซ้ำได้)', async () => {
    const { pool } = makePool([insertUser]);
    const { auth, mail } = service({ provider: 'log', pool });
    vi.spyOn(mail, 'send').mockRejectedValue(new Error('smtp down'));
    await expect(
      auth.register({ username: 'somchai', email: 's@example.com', password: 'Str0ng!Passw0rd#1' }),
    ).resolves.toEqual({ id: 'u1', verificationRequired: true });
    await flush();
  });
});

describe('ล็อกอินก่อนยืนยันอีเมล', () => {
  async function userRow(verified: boolean) {
    return {
      id: 'u1',
      username: 'somchai',
      email: 's@example.com',
      display_name: 'somchai',
      avatar_url: null,
      profile_completed_at: null,
      password_hash: await argon2.hash('Str0ng!Passw0rd#1'),
      is_suspended: false,
      suspended_until: null,
      email_verified_at: verified ? new Date() : null,
    };
  }
  const poolWith = (row: unknown) =>
    makePool([
      [/FROM users/, () => ({ rows: [row] })],
      [/INSERT INTO refresh_tokens/, () => ({ rows: [] })],
    ]).pool;

  it('เปิดระบบอีเมล + ยังไม่ยืนยัน → 403 EMAIL_NOT_VERIFIED', async () => {
    const { auth } = service({ provider: 'log', pool: poolWith(await userRow(false)) });
    await expect(auth.login({ identifier: 'somchai', password: 'Str0ng!Passw0rd#1' })).rejects.toMatchObject({
      code: 'EMAIL_NOT_VERIFIED',
    });
  });

  it('รหัสผ่านผิด → ข้อความทั่วไป ไม่เปิดเผยว่าบัญชียังไม่ยืนยัน', async () => {
    const { auth } = service({ provider: 'log', pool: poolWith(await userRow(false)) });
    await expect(auth.login({ identifier: 'somchai', password: 'ผิดแน่นอน' })).rejects.toMatchObject({
      code: 'UNAUTHORIZED',
    });
  });

  it('ปิดระบบอีเมล → ล็อกอินได้แม้ยังไม่ยืนยัน (กันผู้ใช้ใหม่ติดตอนยังไม่มีคีย์)', async () => {
    const { auth } = service({ pool: poolWith(await userRow(false)) });
    await expect(auth.login({ identifier: 'somchai', password: 'Str0ng!Passw0rd#1' })).resolves.toBeDefined();
  });

  it('ยืนยันแล้ว → ล็อกอินได้', async () => {
    const { auth } = service({ provider: 'log', pool: poolWith(await userRow(true)) });
    await expect(auth.login({ identifier: 'somchai', password: 'Str0ng!Passw0rd#1' })).resolves.toBeDefined();
  });
});

describe('กดลิงก์ในอีเมล (verifyEmail)', () => {
  const future = new Date(Date.now() + 3_600_000);
  const past = new Date(Date.now() - 3_600_000);
  const lookup = (row: unknown | null) =>
    makePool([[/FROM email_verification_tokens t/, () => ({ rows: row ? [row] : [] })]]);

  it('ไม่รู้จัก token → invalid', async () => {
    const { pool } = lookup(null);
    expect(await service({ provider: 'log', pool }).auth.verifyEmail('x'.repeat(30))).toBe('invalid');
  });

  it('token ปกติ → ok และอัปเดตทั้งผู้ใช้กับ token ในธุรกรรมเดียว', async () => {
    const { pool, client } = lookup({ id: 't1', user_id: 'u1', used_at: null, expires_at: future, email_verified_at: null });
    expect(await service({ provider: 'log', pool }).auth.verifyEmail('x'.repeat(30))).toBe('ok');
    const sqls = client.query.mock.calls.map((c) => c[0] as string);
    expect(sqls[0]).toBe('BEGIN');
    expect(sqls.some((s) => /UPDATE users SET email_verified_at/.test(s))).toBe(true);
    expect(sqls.some((s) => /UPDATE email_verification_tokens SET used_at/.test(s))).toBe(true);
    expect(sqls.at(-1)).toBe('COMMIT');
  });

  it('หมดอายุ → expired (ไม่แตะข้อมูล)', async () => {
    const { pool, client } = lookup({ id: 't1', user_id: 'u1', used_at: null, expires_at: past, email_verified_at: null });
    expect(await service({ provider: 'log', pool }).auth.verifyEmail('x'.repeat(30))).toBe('expired');
    expect(client.query).not.toHaveBeenCalled();
  });

  it('ลิงก์เก่าที่ถูกแทนที่แล้ว (ผู้ใช้ยังไม่ยืนยัน) → used', async () => {
    const { pool } = lookup({ id: 't1', user_id: 'u1', used_at: new Date(), expires_at: future, email_verified_at: null });
    expect(await service({ provider: 'log', pool }).auth.verifyEmail('x'.repeat(30))).toBe('used');
  });

  it('กดซ้ำหลังยืนยันแล้ว → ok (กันโปรแกรมสแกนลิงก์กดไปก่อน)', async () => {
    const { pool } = lookup({ id: 't1', user_id: 'u1', used_at: new Date(), expires_at: future, email_verified_at: new Date() });
    expect(await service({ provider: 'log', pool }).auth.verifyEmail('x'.repeat(30))).toBe('ok');
  });
});

describe('ส่งลิงก์ยืนยันอีกครั้ง (resendVerification)', () => {
  const generic = 'ถ้าบัญชีนี้ยังไม่ได้ยืนยัน ระบบส่งลิงก์ยืนยันไปที่อีเมลแล้ว';
  const poolFor = (row: unknown | null) =>
    makePool([[/SELECT u\.id, u\.email/, () => ({ rows: row ? [row] : [] })]]);
  const base = { id: 'u1', email: 's@example.com', username: 'somchai', email_verified_at: null as Date | null };

  it('บัญชีที่ยังไม่ยืนยันและพ้นช่วงพัก → ส่งอีเมลใหม่ และลิงก์เก่าถูกยกเลิก', async () => {
    const { pool, calls } = poolFor({ ...base, last_sent: new Date(Date.now() - 120_000) });
    const { auth, mail } = service({ provider: 'log', pool });
    expect(await auth.resendVerification('somchai')).toEqual({ message: generic });
    expect(mail.outbox).toHaveLength(1);
    expect(calls.some((c) => /SET used_at = now\(\) WHERE user_id/.test(c.sql))).toBe(true);
  });

  it('ค้นด้วยอีเมลได้ (มี @)', async () => {
    const { pool, calls } = poolFor({ ...base, last_sent: null });
    await service({ provider: 'log', pool }).auth.resendVerification('s@example.com');
    expect(calls[0].sql).toContain('u.email = $1');
  });

  it('อยู่ในช่วงพัก 60 วินาที → ไม่ส่ง แต่ตอบข้อความเดิม', async () => {
    const { pool } = poolFor({ ...base, last_sent: new Date(Date.now() - 10_000) });
    const { auth, mail } = service({ provider: 'log', pool });
    expect(await auth.resendVerification('somchai')).toEqual({ message: generic });
    expect(mail.outbox).toHaveLength(0);
  });

  it('ยืนยันแล้ว หรือไม่มีบัญชี → ไม่ส่ง และตอบเหมือนกัน (กันเดาว่ามีบัญชีไหม)', async () => {
    const a = service({ provider: 'log', pool: poolFor({ ...base, email_verified_at: new Date(), last_sent: null }).pool });
    const b = service({ provider: 'log', pool: poolFor(null).pool });
    expect(await a.auth.resendVerification('somchai')).toEqual({ message: generic });
    expect(await b.auth.resendVerification('nobody')).toEqual({ message: generic });
    expect(a.mail.outbox).toHaveLength(0);
    expect(b.mail.outbox).toHaveLength(0);
  });

  it('ปิดระบบอีเมล → ไม่ทำอะไร ไม่แตะฐานข้อมูล', async () => {
    const { pool, calls } = poolFor({ ...base, last_sent: null });
    await service({ pool }).auth.resendVerification('somchai');
    expect(calls).toHaveLength(0);
  });
});

describe('เนื้อหาอีเมลและหน้าเว็บ', () => {
  it('อีเมลมีลิงก์ทั้งในปุ่มและข้อความสำรอง และ escape ชื่อผู้ใช้กัน HTML แทรก', () => {
    const m = verificationEmail({ username: '<script>x</script>', link: 'https://a.test/auth/verify-email?token=abc', ttlHours: 24 });
    expect(m.html).not.toContain('<script>');
    expect(m.html.split('https://a.test/auth/verify-email?token=abc').length - 1).toBeGreaterThanOrEqual(2);
    expect(m.text).toContain('https://a.test/auth/verify-email?token=abc');
  });

  it.each(['ok', 'invalid', 'expired', 'used'] as const)('หน้าเว็บผล %s แสดงได้และเป็นภาษาไทย', (outcome) => {
    const html = verifyResultPage(outcome);
    expect(html).toContain('<html lang="th">');
    expect(html).toContain('Petpaws');
  });
});
