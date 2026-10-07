import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import type { App } from 'supertest/types';
import { randomUUID } from 'node:crypto';
import { AppModule } from './../src/app.module.js';
import { AllExceptionsFilter } from './../src/common/http-exception.filter.js';
import { MailService } from './../src/mail/mail.service.js';

// หน้าเว็บตั้งรหัสผ่านใหม่ผ่าน HTTP จริง (ผู้ใช้กดลิงก์ในอีเมลแล้วเปิดในเบราว์เซอร์):
// GET /auth/reset-password?token=...  →  ฟอร์ม  →  POST /auth/reset-password/form  →  หน้าผลลัพธ์
const PASSWORD = 'Str0ng!Passw0rd#1';
const NEW_PASSWORD = 'An0ther!Passw0rd#2';

const mailArrives = async (mail: MailService, n: number) => {
  for (let i = 0; i < 250 && mail.outbox.length < n; i++) await new Promise((r) => setTimeout(r, 20));
};

describe('หน้าเว็บตั้งรหัสผ่านใหม่ (HTTP e2e)', () => {
  let app: INestApplication;
  let http: App;
  let mail: MailService;

  beforeAll(async () => {
    process.env.MAIL_PROVIDER = 'log';
    const moduleFixture: TestingModule = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleFixture.createNestApplication();
    // ตั้งเหมือน src/main.ts (ValidationPipe + รูปแบบ error ของระบบ)
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
    app.useGlobalFilters(new AllExceptionsFilter());
    await app.init();
    http = app.getHttpServer() as App;
    mail = app.get(MailService);
  });

  afterAll(async () => {
    delete process.env.MAIL_PROVIDER;
    await app.close();
  });

  /** สมัคร + ขอลิงก์ลืมรหัสผ่าน แล้วคืน token จากอีเมล */
  const signupAndRequest = async () => {
    const tag = randomUUID().slice(0, 8);
    const username = `pg_${tag}`;
    const email = `pg_${tag}@example.test`;
    await request(http).post('/auth/register').send({ username, email, password: PASSWORD }).expect(201);
    await mailArrives(mail, mail.outbox.length + 0); // อีเมลยืนยันตอนสมัครส่งแบบไม่รอ
    await new Promise((r) => setTimeout(r, 100));
    const before = mail.outbox.length;
    const res = await request(http).post('/auth/forgot-password').send({ email }).expect(200);
    expect(res.body).not.toHaveProperty('resetToken');
    await mailArrives(mail, before + 1);
    const msg = mail.outbox[mail.outbox.length - 1];
    expect(msg.to).toBe(email);
    const token = /reset-password\?token=([A-Za-z0-9_-]+)/.exec(msg.text)![1];
    return { username, email, token };
  };

  it('ลิงก์ใช้ได้ → หน้าฟอร์ม (HTML, ไม่เก็บแคช, ไม่ส่ง referrer) และเปิดซ้ำได้', async () => {
    const { token } = await signupAndRequest();
    for (let i = 0; i < 2; i++) {
      const res = await request(http).get('/auth/reset-password').query({ token }).expect(200);
      expect(res.headers['content-type']).toContain('text/html');
      expect(res.headers['cache-control']).toBe('no-store');
      expect(res.headers['referrer-policy']).toBe('no-referrer');
      expect(res.text).toMatch(/<form\b[^>]*\bmethod="post"[^>]*>/);
      expect(res.text).toMatch(/<form\b[^>]*\baction="\/auth\/reset-password\/form"[^>]*>/);
      expect(res.text).toContain(`name="token" value="${token}"`);
    }
  });

  it('token มั่ว / สั้นเกิน → ไม่เปิดฟอร์ม', async () => {
    const bad = await request(http).get('/auth/reset-password').query({ token: 'x'.repeat(43) }).expect(400);
    expect(bad.text).toContain('ลิงก์ไม่ถูกต้อง');
    expect(bad.text).not.toContain('<form');
    await request(http).get('/auth/reset-password').query({ token: 'สั้น' }).expect(400);
    await request(http).get('/auth/reset-password').expect(400);
  });

  it('กรอกรหัสสองช่องไม่ตรง → ฟอร์มเดิมพร้อมข้อความ ลิงก์ยังไม่ถูกใช้', async () => {
    const { token } = await signupAndRequest();
    const res = await request(http)
      .post('/auth/reset-password/form')
      .type('form')
      .send({ token, newPassword: NEW_PASSWORD, confirmPassword: 'ไม่ตรงกัน' })
      .expect(400);
    expect(res.text).toContain('รหัสผ่านทั้งสองช่องไม่ตรงกัน');
    expect(res.text).toContain('<form');
    await request(http).get('/auth/reset-password').query({ token }).expect(200);
  });

  it('รหัสอ่อน → ฟอร์มเดิมพร้อมข้อความกฎรหัสผ่าน', async () => {
    const { token } = await signupAndRequest();
    const res = await request(http)
      .post('/auth/reset-password/form')
      .type('form')
      .send({ token, newPassword: 'abc', confirmPassword: 'abc' })
      .expect(400);
    expect(res.text).toContain('รหัสผ่านต้อง');
  });

  it('ตั้งรหัสใหม่สำเร็จ → หน้าสำเร็จ แล้วล็อกอินด้วยรหัสใหม่ได้ รหัสเก่าไม่ได้ และลิงก์ใช้ซ้ำไม่ได้', async () => {
    const { token, username } = await signupAndRequest();

    const ok = await request(http)
      .post('/auth/reset-password/form')
      .type('form')
      .send({ token, newPassword: NEW_PASSWORD, confirmPassword: NEW_PASSWORD })
      .expect(200);
    expect(ok.text).toContain('ตั้งรหัสผ่านใหม่สำเร็จ');
    expect(ok.text).not.toContain('<form');

    // บัญชีที่ยังไม่ยืนยันอีเมลแต่รีเซ็ตผ่านลิงก์ในอีเมลได้ = ถือว่ายืนยันแล้ว จึงล็อกอินได้เลย
    await request(http).post('/auth/login').send({ identifier: username, password: NEW_PASSWORD }).expect(200);
    await request(http).post('/auth/login').send({ identifier: username, password: PASSWORD }).expect(401);

    const again = await request(http).get('/auth/reset-password').query({ token }).expect(400);
    expect(again.text).toContain('ถูกใช้ไปแล้ว');
    const reuse = await request(http)
      .post('/auth/reset-password/form')
      .type('form')
      .send({ token, newPassword: 'Yet4nother!Pass#3', confirmPassword: 'Yet4nother!Pass#3' })
      .expect(400);
    expect(reuse.text).toContain('ถูกใช้ไปแล้ว');
  });

  it('JSON API เดิม (POST /auth/reset-password) ยังทำงาน และรหัสยาวเกิน 128 ตัวถูกปฏิเสธก่อนเข้า argon2', async () => {
    const { token } = await signupAndRequest();
    await request(http).post('/auth/reset-password').send({ token, newPassword: `Aa1!${'x'.repeat(200)}` }).expect(400);
    await request(http).post('/auth/reset-password').send({ token, newPassword: NEW_PASSWORD }).expect(200);
  });

  it('forgot-password: อีเมลรูปแบบผิด → 400, อีเมลที่ไม่มีบัญชี → 200 ข้อความเดียวกับที่มีบัญชี', async () => {
    await request(http).post('/auth/forgot-password').send({ email: 'ไม่ใช่อีเมล' }).expect(400);
    const unknown = await request(http).post('/auth/forgot-password').send({ email: `no_${randomUUID()}@example.test` }).expect(200);
    const { email } = await signupAndRequest();
    const known = await request(http).post('/auth/forgot-password').send({ email }).expect(200);
    expect(unknown.body).toEqual(known.body);
  });
});
