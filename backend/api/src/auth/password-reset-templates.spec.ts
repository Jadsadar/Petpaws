import { describe, expect, it } from 'vitest';
import { runInNewContext } from 'node:vm';
import {
  passwordChangedEmail,
  passwordResetEmail,
  resetFormPage,
  resetResultPage,
} from './email-templates.js';

// เนื้อหาอีเมล/หน้าเว็บของ "ลืมรหัสผ่าน" — ฟังก์ชันล้วน ไม่แตะ DB (การทำงานกับ DB อยู่ใน test/auth.e2e-spec.ts)

describe('อีเมลลืมรหัสผ่าน', () => {
  const link = 'https://a.test/auth/reset-password?token=abc123';

  it('มีลิงก์ทั้งในปุ่มและข้อความสำรอง บอกอายุลิงก์ และ escape ชื่อผู้ใช้กัน HTML แทรก', () => {
    const m = passwordResetEmail({
      username: '<script>x</script>',
      link,
      ttlMinutes: 30,
    });
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
  it('ฟอร์มส่งแบบ POST ช่องรหัสเป็น password และมี token ในช่อง hidden (escape แล้ว)', () => {
    const html = resetFormPage({ token: 'a"><script>alert(1)</script>' });
    expect(html).toContain('<html lang="th">');
    expect(html).toContain('method="post" action="/auth/reset-password/form"');
    expect(html.match(/type="password"/g)).toHaveLength(2);
    expect(html.match(/<script>/g)).toHaveLength(1);
    expect(html).toContain(
      'value="a&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"',
    );
    expect(html).toContain('autocomplete="new-password"');
  });

  it('escape ชื่อและอีเมลก่อนใช้ตรวจเงื่อนไขใน browser', () => {
    const html = resetFormPage({
      token: 't',
      username: '"><script>alert(1)</script>',
      email: '"@a.test',
    });
    expect(html.match(/<script>/g)).toHaveLength(1);
    expect(html).toContain(
      'data-username="&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;"',
    );
  });

  function browserForm() {
    class Element {
      hidden = true;
      type = 'password';
      value = '';
      textContent = '';
      validity = '';
      style: Record<string, string> = {};
      dataset: Record<string, string> = {};
      attributes: Record<string, string> = {};
      children: Element[] = [];
      handlers: Record<string, (event?: unknown) => void> = {};
      constructor(public id = '') {}
      addEventListener(name: string, handler: (event?: unknown) => void) {
        this.handlers[name] = handler;
      }
      setCustomValidity(message: string) {
        this.validity = message;
      }
      setAttribute(name: string, value: string) {
        this.attributes[name] = value;
      }
      replaceChildren(...children: Element[]) {
        this.children = children;
      }
      querySelector() {
        return this;
      }
      reportValidity() {
        return (
          !elements.newPassword.validity && !elements.confirmPassword.validity
        );
      }
    }
    const elements: Record<string, Element> = {};
    for (const id of [
      'reset-password-form',
      'newPassword',
      'confirmPassword',
      'password-checklist',
      'password-rules',
      'password-strength',
      'password-strength-label',
    ]) {
      elements[id] = new Element(id);
    }
    elements['reset-password-form'].dataset = {
      username: 'somchai',
      email: 'kuljira@example.com',
    };
    const toggles = ['newPassword', 'confirmPassword'].map((id) => {
      const button = new Element();
      button.dataset.passwordToggle = id;
      return button;
    });
    const html = resetFormPage({ token: 'test' });
    const script = html.match(/<script>([\s\S]*?)<\/script>/)![1];
    runInNewContext(script, {
      document: {
        getElementById: (id: string) => elements[id],
        querySelectorAll: () => toggles,
        querySelector: () => ({ textContent: 'รหัสผ่าน' }),
        createElement: () => new Element(),
      },
    });
    return { elements, toggles };
  }

  it('เปิดและซ่อนรหัสแต่ละช่องได้อย่างอิสระ โดยไม่เปลี่ยนค่าที่กรอก', () => {
    const { elements, toggles } = browserForm();
    elements.newPassword.value = 'GoodPass!99';
    expect(toggles.every((button) => !button.hidden)).toBe(true);
    toggles[0].handlers.click();
    expect(elements.newPassword.type).toBe('text');
    expect(elements.confirmPassword.type).toBe('password');
    expect(toggles[0].attributes['aria-pressed']).toBe('true');
    toggles[0].handlers.click();
    expect(elements.newPassword.type).toBe('password');
    expect(elements.newPassword.value).toBe('GoodPass!99');
    toggles[1].handlers.click();
    expect(elements.confirmPassword.type).toBe('text');
  });

  it('แสดงเงื่อนไขขณะพิมพ์ ตรวจชื่อผู้ใช้/อีเมลและการยืนยันรหัส พร้อมหยุด submit ที่ไม่ผ่าน', () => {
    const { elements } = browserForm();
    expect(elements['password-checklist'].hidden).toBe(true);
    elements.newPassword.value = 'Somchai!99';
    elements.newPassword.handlers.input();
    expect(elements['password-checklist'].hidden).toBe(false);
    expect(elements['password-rules'].children).toHaveLength(7);
    expect(elements.newPassword.validity).toContain('ชื่อผู้ใช้');
    elements.newPassword.value = 'Kuljira!99';
    elements.newPassword.handlers.input();
    expect(elements.newPassword.validity).toContain('ชื่ออีเมล');
    elements.newPassword.value = 'GoodPass!99';
    elements.confirmPassword.value = 'Different!99';
    elements.confirmPassword.handlers.input();
    expect(elements.newPassword.validity).toBe('');
    expect(elements.confirmPassword.validity).toContain('ไม่ตรงกัน');
    let prevented = false;
    elements['reset-password-form'].handlers.submit({
      preventDefault() {
        prevented = true;
      },
    });
    expect(prevented).toBe(true);
    elements.confirmPassword.value = 'GoodPass!99';
    elements.confirmPassword.handlers.input();
    expect(elements.confirmPassword.validity).toBe('');
    expect(elements['password-strength-label'].textContent).toBe('แข็งแรง');
  });

  it('ข้อความเตือนถูก escape และแสดงเมื่อมี', () => {
    expect(
      resetFormPage({ token: 't'.repeat(43), error: '<b>ผิด</b>' }),
    ).toContain('&lt;b&gt;ผิด&lt;/b&gt;');
    expect(resetFormPage({ token: 't'.repeat(43) })).not.toContain(
      'role="alert"',
    );
  });

  it.each(['ok', 'invalid', 'expired', 'used'] as const)(
    'หน้าผลลัพธ์ %s เป็นภาษาไทย ไม่มีฟอร์ม',
    (outcome) => {
      const html = resetResultPage(outcome);
      expect(html).toContain('<html lang="th">');
      expect(html).toContain('Petpaws');
      expect(html).not.toContain('<form');
    },
  );
});
