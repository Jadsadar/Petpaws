import { describe, expect, it } from 'vitest';
import type { ConfigService } from '@nestjs/config';
import { MailService } from '../mail/mail.service.js';
import { verificationEmail, verifyResultPage } from './email-templates.js';

// เทสต์ที่ไม่ต้องใช้ฐานข้อมูล — การทำงานของการสมัคร/ยืนยัน/ส่งซ้ำ/ล็อกอินกับ DB จริง
// อยู่ใน test/auth.e2e-spec.ts

function makeConfig(env: Record<string, string>) {
  return { get: (k: string) => env[k], getOrThrow: (k: string) => env[k] } as unknown as ConfigService;
}

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
