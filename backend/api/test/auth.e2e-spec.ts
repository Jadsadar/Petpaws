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

  describe('ลืมรหัสผ่าน / รีเซ็ต', () => {
    it('รีเซ็ตสำเร็จ: รหัสใหม่ใช้ได้ รหัสเก่าใช้ไม่ได้ ทุกเครื่องที่ล็อกอินค้างถูกบังคับออก และลิงก์ใช้ซ้ำไม่ได้', async () => {
      const { auth } = service(false);
      const u = await register(auth);
      const session = await auth.login({ identifier: u.username, password: PASSWORD });
      const { resetToken } = await auth.forgotPassword(u.email);
      const newPassword = 'An0ther!Passw0rd#2';

      await expect(auth.resetPassword(resetToken!, newPassword)).resolves.toEqual({ success: true });

      await expect(auth.login({ identifier: u.username, password: PASSWORD })).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
      await expect(auth.login({ identifier: u.username, password: newPassword })).resolves.toBeDefined();
      await expect(auth.refresh(session.refreshToken)).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
      await expect(auth.resetPassword(resetToken!, 'Yet4nother!Pass#3')).rejects.toMatchObject({ code: 'UNAUTHORIZED' });
    });

    it('อีเมลที่ไม่มีในระบบ ได้ข้อความเดียวกัน ไม่มี token', async () => {
      const res = await service(false).auth.forgotPassword(`nobody_${randomUUID()}@e2e.test`);
      expect(res).toEqual({ message: 'ถ้ามีบัญชีนี้อยู่ในระบบ ระบบได้ออกลิงก์รีเซ็ตรหัสผ่านแล้ว' });
    });

    it('รหัสใหม่อ่อนเกิน → ปฏิเสธ และลิงก์ยังใช้ได้อยู่', async () => {
      const { auth } = service(false);
      const u = await register(auth);
      const { resetToken } = await auth.forgotPassword(u.email);

      await expect(auth.resetPassword(resetToken!, '123')).rejects.toMatchObject({ code: 'WEAK_PASSWORD' });
      await expect(auth.resetPassword(resetToken!, 'An0ther!Passw0rd#2')).resolves.toEqual({ success: true });
    });
  });
});
