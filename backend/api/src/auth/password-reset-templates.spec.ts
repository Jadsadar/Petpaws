import { describe, expect, it } from 'vitest';
import { passwordChangedEmail, passwordResetEmail, resetFormPage, resetResultPage } from './email-templates.js';

// เนื้อหาอีเมล/หน้าเว็บของ "ลืมรหัสผ่าน" — ฟังก์ชันล้วน ไม่แตะ DB (การทำงานกับ DB อยู่ใน test/auth.e2e-spec.ts)

describe('อีเมลลืมรหัสผ่าน', () => {
  const link = 'https://a.test/auth/reset-password?token=abc123';

  it('มีลิงก์ทั้งในปุ่มและข้อความสำรอง บอกอายุลิงก์ และ escape ชื่อผู้ใช้กัน HTML แทรก', () => {
    const m = passwordResetEmail({ username: '<script>x</script>', link, ttlMinutes: 30 });
    expect(m.html).not.toContain('<script>');
    expect(m.html.split(link).length - 1).toBeGreaterThanOrEqual(2);
    expect(m.text).toContain(link);
    expect(m.text).toContain('30 นาที');
    expect(m.subject).toContain('Petpaws');
  });

  it('อีเมลแจ้งว่ารหัสผ่านถูกเปลี่ยนแล้ว ไม่มีลิงก์/รหัสใดๆ', () => {
    const m = passwordChangedEmail({ username: 'somchai' });
    expect(m.text).toContain('ถูกเปลี่ยนแล้ว');
    expect(m.text).not.toContain('http');
    expect(m.html).not.toContain('href=');
  });
});

describe('หน้าเว็บตั้งรหัสผ่านใหม่', () => {
  it('ฟอร์มส่งแบบ POST ไม่ใช้ JavaScript ช่องรหัสเป็น password และมี token ในช่อง hidden (escape แล้ว)', () => {
    const html = resetFormPage({ token: 'a"><script>alert(1)</script>' });
    expect(html).toContain('<html lang="th">');
    expect(html).toContain('method="post" action="/auth/reset-password/form"');
    expect(html.match(/type="password"/g)).toHaveLength(2);
    expect(html).not.toContain('<script>');
    expect(html).toContain('autocomplete="new-password"');
  });

  it('ข้อความเตือนถูก escape และแสดงเมื่อมี', () => {
    expect(resetFormPage({ token: 't'.repeat(43), error: '<b>ผิด</b>' })).toContain('&lt;b&gt;ผิด&lt;/b&gt;');
    expect(resetFormPage({ token: 't'.repeat(43) })).not.toContain('role="alert"');
  });

  it.each(['ok', 'invalid', 'expired', 'used'] as const)('หน้าผลลัพธ์ %s เป็นภาษาไทย ไม่มีฟอร์ม', (outcome) => {
    const html = resetResultPage(outcome);
    expect(html).toContain('<html lang="th">');
    expect(html).toContain('Petpaws');
    expect(html).not.toContain('<form');
  });
});
