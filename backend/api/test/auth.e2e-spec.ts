import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import type { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { DataSource } from 'typeorm';
import { createHash, randomUUID } from 'node:crypto';
import { vi } from 'vitest';
import { AppModule } from './../src/app.module.js';
import { AuthService } from './../src/auth/auth.service.js';
import { MailService } from './../src/mail/mail.service.js';
import { EmailVerificationToken, PasswordResetToken, RefreshToken, User } from './../src/database/entities/index.js';

// ระบบบัญชีกับ DB จริง: สมัคร → ยืนยันอีเมล → ส่งซ้ำ → ล็อกอิน, refresh token rotation,
// ตรวจจับการใช้ token ซ้ำ, ออกจากระบบ, รีเซ็ตรหัสผ่าน (เทสต์เดิมใน email-verification.spec.ts
// เคย mock ฐานข้อมูลด้วยการจับข้อความ SQL — ย้ายมาที่นี่ตอนเปลี่ยนเป็น TypeORM ครบทุกกรณีเดิม)
const PASSWORD = 'Str0ng!Passw0rd#1';
const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');
const tokenFrom = (text: string) => /token=([A-Za-z0-9_-]+)/.exec(text)![1];
const flush = () => new Promise((r) => setTimeout(r, 50));
/**
 * อีเมลยืนยันตอนสมัครส่งแบบไม่รอ (void) — รอจนเข้า outbox แทนการรอเวลาตายตัว
 * (เครื่อง CI ช้ากว่า: เคยรอ 50ms แล้วอีเมลยังไม่มา เทสต์ล้มทั้งที่โค้ดถูก)
 */
const mailArrives = async (mail: MailService, n = 1) => {
  for (let i = 0; i < 250 && mail.outbox.length < n; i++) await new Promise((r) => setTimeout(r, 20));
};

describe('auth (e2e กับ DB จริง)', () => {
  let app: INestApplication;
  let ds: DataSource;

  /** AuthService ที่ต่อ DB จริง เลือกได้ว่าเปิดระบบอีเมลไหม (log = เก็บอีเมลไว้ใน outbox ให้ตรวจ) */
  const service = (mailOn: boolean) => {
    const env: Record<string, string> = {
      JWT_ACCESS_SECRET: 'a',
      JWT_REFRESH_SECRET: 'r',
      JWT_ACCESS_TTL: '15m',
      JWT_REFRESH_TTL: '30d',
      APP_PUBLIC_URL: 'https://api.example.test/',
      ...(mailOn ? { MAIL_PROVIDER: 'log' } : {}),
    };
    const config = { get: (k: string) => env[k], getOrThrow: (k: string) => env[k] } as unknown as ConfigService;
    const mail = new MailService(config);
    const auth = new AuthService(
      ds,
      ds.getRepository(User),
      ds.getRepository(RefreshToken),
      ds.getRepository(PasswordResetToken),
      ds.getRepository(EmailVerificationToken),
      new JwtService({}),
      config,
      mail,
    );
    return { auth, mail };
  };

  /** สมัครผู้ใช้ใหม่ (ชื่อไม่ซ้ำ) */
  const register = async (auth: AuthService) => {
    const tag = randomUUID().slice(0, 8);
    const username = `e2e_${tag}`;
    const email = `E2E_${tag}@Example.test`;
    const { id } = await auth.register({ username, email, password: PASSWORD });
    return { id, username, email };
  };

  const one = async <T>(sql: string, params: unknown[]) => (await ds.query(sql, params))[0] as T;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleFixture.createNestApplication();
    await app.init();
    ds = app.get(DataSource);
  });

  afterAll(async () => {
    await app.close();
  });

  describe('สมัครสมาชิก → ส่งลิงก์ยืนยัน', () => {
    it('เปิดระบบอีเมล: ส่งอีเมลหนึ่งฉบับ มีลิงก์ถึง /auth/verify-email และ DB เก็บเฉพาะ hash ของ token', async () => {
      const { auth, mail } = service(true);
      const u = await register(auth);
      await mailArrives(mail);

      expect(mail.outbox).toHaveLength(1);
      const msg = mail.outbox[0];
      expect(msg.to).toBe(u.email);
      expect(msg.text).toContain('https://api.example.test/auth/verify-email?token=');
      expect(msg.html).toContain('ยืนยันอีเมล');
      const token = tokenFrom(msg.text);
      const rows = await ds.query(`SELECT token_hash FROM email_verification_tokens WHERE user_id = $1`, [u.id]);
      expect(rows).toEqual([{ token_hash: sha256(token) }]);
    });

    it('ปิดระบบอีเมล: สมัครได้ตามเดิม ไม่ส่งอะไร ไม่สร้างลิงก์', async () => {
      const { auth, mail } = service(false);
      const res = await auth.register({ username: `e2e_${randomUUID().slice(0, 8)}`, email: `${randomUUID()}@e2e.test`, password: PASSWORD });
      await flush();

      expect(res.verificationRequired).toBe(false);
      expect(mail.outbox).toHaveLength(0);
      expect(await ds.query(`SELECT 1 FROM email_verification_tokens WHERE user_id = $1`, [res.id])).toEqual([]);
    });

    it('ผู้ให้บริการอีเมลล้ม: สมัครยังสำเร็จ (ผู้ใช้กดส่งซ้ำได้)', async () => {
      const { auth, mail } = service(true);
      vi.spyOn(mail, 'send').mockRejectedValue(new Error('smtp down'));

      await expect(register(auth)).resolves.toMatchObject({ id: expect.any(String) });
      await flush();
    });
  });

  describe('ล็อกอินกับการยืนยันอีเมล', () => {
    it('เปิดระบบอีเมล + ยังไม่ยืนยัน → 403 EMAIL_NOT_VERIFIED', async () => {
      const { auth } = service(true);
      const u = await register(auth);
      await expect(auth.login({ identifier: u.username, password: PASSWORD })).rejects.toMatchObject({ code: 'EMAIL_NOT_VERIFIED' });
    });

    it('รหัสผ่านผิด → ข้อความทั่วไป ไม่เปิดเผยว่าบัญชียังไม่ยืนยัน', async () => {
      const { auth } = service(true);
      const u = await register(auth);
      await expect(auth.login({ identifier: u.username, password: 'ผิดแน่นอน' })).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
    });

    it('ปิดระบบอีเมล → ล็อกอินได้แม้ยังไม่ยืนยัน (กันผู้ใช้ใหม่ติดตอนยังไม่มีคีย์)', async () => {
      const { auth } = service(false);
      const u = await register(auth);
      await expect(auth.login({ identifier: u.username, password: PASSWORD })).resolves.toMatchObject({ user: { id: u.id } });
    });

    it('ยืนยันแล้ว → ล็อกอินได้ ด้วยอีเมลตัวพิมพ์ต่างกันก็ได้ (citext) และบันทึกเวลาเข้าระบบ', async () => {
      const { auth, mail } = service(true);
      const u = await register(auth);
      await mailArrives(mail);
      expect(await auth.verifyEmail(tokenFrom(mail.outbox[0].text))).toBe('ok');

      const res = await auth.login({ identifier: u.email.toLowerCase(), password: PASSWORD });

      expect(res.user).toMatchObject({ id: u.id, username: u.username, profileCompleted: false, province: null });
      expect((await one<{ last_login_at: Date }>(`SELECT last_login_at FROM users WHERE id = $1`, [u.id])).last_login_at).toBeInstanceOf(Date);
    });

    it('แบนหมดเวลาแล้ว → ปลดให้เองตอนล็อกอิน / แบนอยู่ → เข้าไม่ได้', async () => {
      const { auth } = service(false);
      const expired = await register(auth);
      const active = await register(auth);
      await ds.query(`UPDATE users SET is_suspended = true, suspended_until = now() - interval '1 minute' WHERE id = $1`, [expired.id]);
      await ds.query(`UPDATE users SET is_suspended = true, suspended_until = NULL WHERE id = $1`, [active.id]);

      await expect(auth.login({ identifier: expired.username, password: PASSWORD })).resolves.toBeDefined();
      expect((await one<{ is_suspended: boolean }>(`SELECT is_suspended FROM users WHERE id = $1`, [expired.id])).is_suspended).toBe(false);
      await expect(auth.login({ identifier: active.username, password: PASSWORD })).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
    });
  });

  describe('กดลิงก์ในอีเมล (verifyEmail)', () => {
    const fresh = async () => {
      const { auth, mail } = service(true);
      const u = await register(auth);
      await mailArrives(mail);
      return { auth, mail, u, token: tokenFrom(mail.outbox[0].text) };
    };

    it('ไม่รู้จัก token → invalid', async () => {
      expect(await service(true).auth.verifyEmail('x'.repeat(30))).toBe('invalid');
    });

    it('token ปกติ → ok อัปเดตทั้งผู้ใช้และ token', async () => {
      const { auth, u, token } = await fresh();

      expect(await auth.verifyEmail(token)).toBe('ok');

      expect((await one<{ email_verified_at: Date }>(`SELECT email_verified_at FROM users WHERE id = $1`, [u.id])).email_verified_at).toBeInstanceOf(Date);
      expect((await one<{ used_at: Date }>(`SELECT used_at FROM email_verification_tokens WHERE token_hash = $1`, [sha256(token)])).used_at).toBeInstanceOf(Date);
    });

    it('หมดอายุ → expired (ไม่แตะข้อมูล)', async () => {
      const { auth, u, token } = await fresh();
      await ds.query(`UPDATE email_verification_tokens SET expires_at = now() - interval '1 minute' WHERE user_id = $1`, [u.id]);

      expect(await auth.verifyEmail(token)).toBe('expired');
      expect((await one<{ email_verified_at: Date | null }>(`SELECT email_verified_at FROM users WHERE id = $1`, [u.id])).email_verified_at).toBeNull();
    });

    it('ลิงก์เก่าที่ถูกแทนที่แล้ว (ผู้ใช้ยังไม่ยืนยัน) → used', async () => {
      const { auth, u, token } = await fresh();
      await ds.query(`UPDATE email_verification_tokens SET created_at = now() - interval '2 minutes' WHERE user_id = $1`, [u.id]);
      await auth.resendVerification(u.username);

      expect(await auth.verifyEmail(token)).toBe('used');
    });

    it('กดซ้ำหลังยืนยันแล้ว → ok (กันโปรแกรมสแกนลิงก์กดไปก่อน)', async () => {
      const { auth, token } = await fresh();
      await auth.verifyEmail(token);
      expect(await auth.verifyEmail(token)).toBe('ok');
    });
  });

  describe('ส่งลิงก์ยืนยันอีกครั้ง (resendVerification)', () => {
    const generic = 'ถ้าบัญชีนี้ยังไม่ได้ยืนยัน ระบบส่งลิงก์ยืนยันไปที่อีเมลแล้ว';
    const pastCooldown = (userId: string) =>
      ds.query(`UPDATE email_verification_tokens SET created_at = now() - interval '2 minutes' WHERE user_id = $1`, [userId]);

    it('ยังไม่ยืนยันและพ้นช่วงพัก → ส่งอีเมลใหม่ และลิงก์เก่าถูกยกเลิก', async () => {
      const { auth, mail } = service(true);
      const u = await register(auth);
      await mailArrives(mail);
      await pastCooldown(u.id);

      expect(await auth.resendVerification(u.username)).toEqual({ message: generic });

      expect(mail.outbox).toHaveLength(2);
      const rows = await ds.query(`SELECT used_at IS NOT NULL AS used FROM email_verification_tokens WHERE user_id = $1 ORDER BY created_at`, [u.id]);
      expect(rows).toEqual([{ used: true }, { used: false }]);
    });

    it('ค้นด้วยอีเมลได้ (มี @)', async () => {
      const { auth, mail } = service(true);
      const u = await register(auth);
      await mailArrives(mail);
      await pastCooldown(u.id);

      await auth.resendVerification(u.email.toUpperCase());

      expect(mail.outbox).toHaveLength(2);
    });

    it('อยู่ในช่วงพัก 60 วินาที → ไม่ส่ง แต่ตอบข้อความเดิม', async () => {
      const { auth, mail } = service(true);
      const u = await register(auth);
      await mailArrives(mail);

      expect(await auth.resendVerification(u.username)).toEqual({ message: generic });
      expect(mail.outbox).toHaveLength(1);
    });

    it('ยืนยันแล้ว หรือไม่มีบัญชี → ไม่ส่ง และตอบเหมือนกัน (กันเดาว่ามีบัญชีไหม)', async () => {
      const { auth, mail } = service(true);
      const u = await register(auth);
      await mailArrives(mail);
      await auth.verifyEmail(tokenFrom(mail.outbox[0].text));
      await pastCooldown(u.id);

      expect(await auth.resendVerification(u.username)).toEqual({ message: generic });
      expect(await auth.resendVerification(`nobody_${randomUUID()}`)).toEqual({ message: generic });
      expect(mail.outbox).toHaveLength(1);
    });

    it('ปิดระบบอีเมล → ไม่ทำอะไร', async () => {
      const { auth, mail } = service(false);
      const u = await register(auth);
      expect(await auth.resendVerification(u.username)).toEqual({ message: generic });
      expect(mail.outbox).toHaveLength(0);
    });
  });

  describe('refresh token', () => {
    const loggedIn = async () => {
      const { auth } = service(false);
      const u = await register(auth);
      return { auth, u, tokens: await auth.login({ identifier: u.username, password: PASSWORD }) };
    };

    it('ใช้แล้วได้คู่ใหม่ (rotation) — แถวเดิมชี้ไปแถวใหม่ และใช้ token เดิมต่อไม่ได้', async () => {
      const { auth, tokens } = await loggedIn();

      const next = await auth.refresh(tokens.refreshToken);

      expect(next.refreshToken).not.toBe(tokens.refreshToken);
      const oldRow = await one<{ revoked_reason: string; replaced_by_id: string }>(
        `SELECT revoked_reason, replaced_by_id FROM refresh_tokens WHERE token_hash = $1`,
        [sha256(tokens.refreshToken)],
      );
      const newRow = await one<{ id: string }>(`SELECT id FROM refresh_tokens WHERE token_hash = $1`, [sha256(next.refreshToken)]);
      expect(oldRow).toEqual({ revoked_reason: 'rotated', replaced_by_id: newRow.id });
    });

    it('เอา token ที่ใช้ไปแล้วมาใช้ซ้ำ = มีสำเนาหลุด → เพิกถอนทั้งสาย ตัวล่าสุดก็ใช้ไม่ได้', async () => {
      const { auth, tokens } = await loggedIn();
      const next = await auth.refresh(tokens.refreshToken);

      await expect(auth.refresh(tokens.refreshToken)).rejects.toMatchObject({ code: 'UNAUTHORIZED' });

      await expect(auth.refresh(next.refreshToken)).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
      const row = await one<{ revoked_reason: string }>(`SELECT revoked_reason FROM refresh_tokens WHERE token_hash = $1`, [sha256(next.refreshToken)]);
      expect(row.revoked_reason).toBe('reuse_detected');
    });

    it('ออกจากระบบแล้ว refresh ไม่ได้ / token มั่วได้ 401', async () => {
      const { auth, tokens } = await loggedIn();
      await auth.logout(tokens.refreshToken);

      await expect(auth.refresh(tokens.refreshToken)).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
      await expect(auth.refresh('ไม่ใช่ token จริง')).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
    });
  });

  describe('ลืมรหัสผ่าน → ลิงก์ทางอีเมล → ตั้งรหัสใหม่', () => {
    const NEW_PASSWORD = 'An0ther!Passw0rd#2';

    /** ผู้ใช้ใหม่ + ระบบอีเมลเปิด (ล้างอีเมลยืนยันตอนสมัครออกจาก outbox แล้ว) */
    const userWithMail = async () => {
      const s = service(true);
      const u = await register(s.auth);
      await mailArrives(s.mail);
      s.mail.outbox.length = 0;
      return { ...s, u };
    };

    /** ขอลิงก์แล้วคืน token ที่อยู่ในอีเมลฉบับล่าสุด */
    const requestLink = async (s: { auth: AuthService; mail: MailService }, email: string) => {
      const before = s.mail.outbox.length;
      await s.auth.forgotPassword(email);
      await mailArrives(s.mail, before + 1);
      return tokenFrom(s.mail.outbox[s.mail.outbox.length - 1].text);
    };

    it('ขอลิงก์: ไม่คืน token ใน response, ส่งอีเมลหนึ่งฉบับมีลิงก์ /auth/reset-password และ DB เก็บเฉพาะ hash', async () => {
      const { auth, mail, u } = await userWithMail();

      const res = await auth.forgotPassword(u.email);
      expect(res).toEqual({ message: 'ถ้ามีบัญชีที่ใช้อีเมลนี้ ระบบได้ส่งลิงก์ตั้งรหัสผ่านใหม่ไปที่อีเมลแล้ว' });
      expect(res).not.toHaveProperty('resetToken');

      await mailArrives(mail);
      expect(mail.outbox).toHaveLength(1);
      expect(mail.outbox[0].to).toBe(u.email);
      expect(mail.outbox[0].text).toContain('https://api.example.test/auth/reset-password?token=');
      expect(mail.outbox[0].html).toContain('ตั้งรหัสผ่านใหม่');

      const token = tokenFrom(mail.outbox[0].text);
      const row = await one<{ token_hash: string }>(
        `SELECT token_hash FROM password_reset_tokens WHERE user_id = $1`,
        [u.id],
      );
      expect(row.token_hash).toBe(sha256(token));
      expect(row.token_hash).not.toContain(token);
    });

    it('อีเมลที่ไม่มีในระบบ: ได้ข้อความเดียวกัน ไม่ส่งอีเมล ไม่สร้าง token', async () => {
      const { auth, mail } = service(true);
      const res = await auth.forgotPassword(`nobody_${randomUUID()}@e2e.test`);
      await flush();
      expect(res.message).toBe('ถ้ามีบัญชีที่ใช้อีเมลนี้ ระบบได้ส่งลิงก์ตั้งรหัสผ่านใหม่ไปที่อีเมลแล้ว');
      expect(mail.outbox).toHaveLength(0);
    });

    it('ระบบอีเมลปิดอยู่: ตอบข้อความเดิม ไม่ error ไม่มี token รั่ว และไม่ส่งอะไร', async () => {
      const { auth } = service(false);
      const u = await register(auth);
      const res = await auth.forgotPassword(u.email);
      expect(res).not.toHaveProperty('resetToken');
      expect(Object.keys(res)).toEqual(['message']);
      const n = await one<{ n: string }>(`SELECT count(*)::text AS n FROM password_reset_tokens WHERE user_id = $1`, [u.id]);
      expect(n.n).toBe('0');
    });

    it('ขอซ้ำภายใน 60 วินาที: ไม่ส่งฉบับที่สอง (กันยิงอีเมลใส่กล่องคนอื่น)', async () => {
      const { auth, mail, u } = await userWithMail();
      await auth.forgotPassword(u.email);
      await mailArrives(mail);
      await auth.forgotPassword(u.email);
      await flush();
      expect(mail.outbox).toHaveLength(1);
    });

    it('ขอลิงก์ใหม่หลังพัก: ลิงก์เก่าใช้ไม่ได้ ลิงก์ใหม่ใช้ได้', async () => {
      const s = await userWithMail();
      const oldToken = await requestLink(s, s.u.email);
      await ds.query(`UPDATE password_reset_tokens SET created_at = now() - interval '5 minutes' WHERE user_id = $1`, [s.u.id]);
      const newToken = await requestLink(s, s.u.email);

      expect(newToken).not.toBe(oldToken);
      await expect(s.auth.checkResetToken(oldToken)).resolves.toBe('used');
      await expect(s.auth.checkResetToken(newToken)).resolves.toBe('ok');
    });

    it('ตั้งรหัสใหม่สำเร็จ: รหัสใหม่ใช้ได้ รหัสเก่าไม่ได้ ทุกเครื่องถูกเตะออก ลิงก์ใช้ซ้ำไม่ได้ และมีอีเมลแจ้งเตือน', async () => {
      const s = await userWithMail();
      // ระบบอีเมลเปิดอยู่ ต้องยืนยันอีเมลก่อนถึงล็อกอินได้
      await ds.query(`UPDATE users SET email_verified_at = now() WHERE id = $1`, [s.u.id]);
      const session = await s.auth.login({ identifier: s.u.username, password: PASSWORD });
      const token = await requestLink(s, s.u.email);

      await expect(s.auth.resetPassword(token, NEW_PASSWORD)).resolves.toEqual({ success: true });

      await expect(s.auth.login({ identifier: s.u.username, password: PASSWORD })).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
      await expect(s.auth.login({ identifier: s.u.username, password: NEW_PASSWORD })).resolves.toBeDefined();
      await expect(s.auth.refresh(session.refreshToken)).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
      await expect(s.auth.resetPassword(token, 'Yet4nother!Pass#3')).rejects.toMatchObject({ code: 'UNAUTHORIZED' });

      await mailArrives(s.mail, 2);
      const notice = s.mail.outbox[s.mail.outbox.length - 1];
      expect(notice.to).toBe(s.u.email);
      expect(notice.subject).toContain('ถูกเปลี่ยนแล้ว');
    });

    it('รหัสใหม่อ่อนเกิน → ปฏิเสธ และลิงก์ยังใช้ได้อยู่', async () => {
      const s = await userWithMail();
      const token = await requestLink(s, s.u.email);

      await expect(s.auth.resetPassword(token, '123')).rejects.toMatchObject({ code: 'WEAK_PASSWORD' });
      await expect(s.auth.resetPassword(token, `${s.u.username}!Aa1xyz`)).rejects.toMatchObject({ code: 'WEAK_PASSWORD' });
      await expect(s.auth.resetPassword(token, NEW_PASSWORD)).resolves.toEqual({ success: true });
    });

    it('token มั่ว / หมดอายุ → ใช้ไม่ได้', async () => {
      const s = await userWithMail();
      await expect(s.auth.resetPassword('ไม่ใช่-token-จริง-เลย-สักนิด-นะครับ', NEW_PASSWORD)).rejects.toMatchObject({ code: 'UNAUTHORIZED' });

      const token = await requestLink(s, s.u.email);
      await ds.query(`UPDATE password_reset_tokens SET expires_at = now() - interval '1 second' WHERE user_id = $1`, [s.u.id]);
      await expect(s.auth.resetPassword(token, NEW_PASSWORD)).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
      await expect(s.auth.checkResetToken(token)).resolves.toBe('expired');
    });

    it('บัญชีที่ยังไม่ยืนยันอีเมล: รีเซ็ตผ่านลิงก์ในอีเมลแล้วถือว่ายืนยันอีเมลในตัว และล็อกอินได้', async () => {
      const s = await userWithMail();
      const before = await one<{ email_verified_at: Date | null }>(`SELECT email_verified_at FROM users WHERE id = $1`, [s.u.id]);
      expect(before.email_verified_at).toBeNull();
      await expect(s.auth.login({ identifier: s.u.username, password: PASSWORD })).rejects.toMatchObject({ code: 'EMAIL_NOT_VERIFIED' });

      const token = await requestLink(s, s.u.email);
      await s.auth.resetPassword(token, NEW_PASSWORD);

      await expect(s.auth.login({ identifier: s.u.username, password: NEW_PASSWORD })).resolves.toBeDefined();
    });

    it('คนละบัญชี ลิงก์ของใครของมัน: ลิงก์ของ A เปลี่ยนรหัสของ B ไม่ได้', async () => {
      const a = await userWithMail();
      const b = await userWithMail();
      const tokenA = await requestLink(a, a.u.email);

      await a.auth.resetPassword(tokenA, NEW_PASSWORD);
      await expect(b.auth.checkResetToken(tokenA)).resolves.toBe('used');
      await expect(b.auth.login({ identifier: b.u.username, password: PASSWORD }).catch((e) => e.code)).resolves.toBe('EMAIL_NOT_VERIFIED');
    });

    describe('หน้าเว็บ (ลิงก์ในอีเมลเปิดในเบราว์เซอร์)', () => {
      it('เปิดลิงก์ไม่ใช้ลิงก์ทิ้ง ส่งฟอร์มสำเร็จถึงใช้ แล้วเปิดซ้ำได้ "ถูกใช้ไปแล้ว"', async () => {
        const s = await userWithMail();
        const token = await requestLink(s, s.u.email);

        await expect(s.auth.checkResetToken(token)).resolves.toBe('ok');
        await expect(s.auth.checkResetToken(token)).resolves.toBe('ok');
        await expect(s.auth.resetFormContext(token)).resolves.toEqual({
          outcome: 'ok', username: s.u.username, email: s.u.email,
        });

        await expect(s.auth.resetPasswordFromPage(token, NEW_PASSWORD, NEW_PASSWORD)).resolves.toEqual({ outcome: 'ok' });
        await expect(s.auth.checkResetToken(token)).resolves.toBe('used');
        await expect(s.auth.resetPasswordFromPage(token, 'Yet4nother!Pass#3', 'Yet4nother!Pass#3')).resolves.toEqual({ outcome: 'used' });
      });

      it('รหัสสองช่องไม่ตรง / รหัสอ่อน → กลับไปฟอร์มพร้อมข้อความ (ลิงก์ยังใช้ได้)', async () => {
        const s = await userWithMail();
        const token = await requestLink(s, s.u.email);

        await expect(s.auth.resetPasswordFromPage(token, NEW_PASSWORD, 'ไม่ตรงกัน')).resolves.toEqual({
          outcome: 'retry',
          message: 'รหัสผ่านทั้งสองช่องไม่ตรงกัน',
          username: s.u.username,
          email: s.u.email,
        });
        const weak = await s.auth.resetPasswordFromPage(token, 'abc', 'abc');
        expect(weak).toMatchObject({ outcome: 'retry' });
        await expect(s.auth.checkResetToken(token)).resolves.toBe('ok');
      });

      it('ลิงก์มั่ว/หมดอายุ → บอกผลตรงๆ ไม่แสดงฟอร์ม', async () => {
        const s = await userWithMail();
        await expect(s.auth.resetPasswordFromPage('x'.repeat(43), NEW_PASSWORD, NEW_PASSWORD)).resolves.toEqual({ outcome: 'invalid' });

        const token = await requestLink(s, s.u.email);
        await ds.query(`UPDATE password_reset_tokens SET expires_at = now() - interval '1 second' WHERE user_id = $1`, [s.u.id]);
        await expect(s.auth.resetPasswordFromPage(token, NEW_PASSWORD, NEW_PASSWORD)).resolves.toEqual({ outcome: 'expired' });
      });

      it('กดบันทึกพร้อมกันสองคำขอ: สำเร็จได้แค่ครั้งเดียว', async () => {
        const s = await userWithMail();
        const token = await requestLink(s, s.u.email);

        const [r1, r2] = await Promise.all([
          s.auth.resetPasswordFromPage(token, NEW_PASSWORD, NEW_PASSWORD),
          s.auth.resetPasswordFromPage(token, 'Yet4nother!Pass#3', 'Yet4nother!Pass#3'),
        ]);
        expect([r1.outcome, r2.outcome].sort()).toEqual(['ok', 'used']);
      });
    });
  });
});
