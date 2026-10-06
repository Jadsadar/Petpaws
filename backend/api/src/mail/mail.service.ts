import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface MailMessage {
  to: string;
  subject: string;
  html: string;
  text: string;
}

/**
 * ส่งอีเมลของระบบ (ตอนนี้ใช้ยืนยันอีเมลตอนสมัคร)
 *
 * MAIL_PROVIDER:
 *   brevo = ส่งจริงผ่าน Brevo HTTP API (ฟรี ~300 ฉบับ/วัน ไม่ต้องมีโดเมนของตัวเอง แค่ยืนยันอีเมลผู้ส่ง)
 *           ต้องตั้ง BREVO_API_KEY + MAIL_FROM_EMAIL ให้ครบ ไม่ครบถือว่า "ไม่ได้ตั้ง"
 *   log   = ไม่ส่งจริง พิมพ์เนื้อหา (รวมลิงก์) ลง log และเก็บใน outbox — ใช้ตอน dev/ทดสอบเท่านั้น
 *   (ไม่ตั้ง) = ปิดระบบอีเมล: ไม่บังคับยืนยันอีเมลตอนล็อกอิน เพื่อไม่ให้ผู้ใช้ใหม่ล็อกอินไม่ได้ในระบบที่ยังไม่มีคีย์
 *
 * ใช้ fetch ตรงๆ ไม่เพิ่มไลบรารี (nodemailer ฯลฯ) — ไม่ต้องแตะ package-lock.json
 */
@Injectable()
export class MailService {
  private readonly logger = new Logger('MailService');
  readonly provider: 'brevo' | 'log' | 'none';

  /** ข้อความที่ "ส่ง" ไปแล้วในโหมด log (เก็บไว้ให้เทสต์/dev อ่านลิงก์) — จำกัดไม่เกิน 50 ฉบับกันหน่วยความจำโต */
  readonly outbox: MailMessage[] = [];

  private readonly apiKey: string;
  private readonly fromEmail: string;
  private readonly fromName: string;

  constructor(config: ConfigService) {
    const wanted = config.get<string>('MAIL_PROVIDER');
    this.apiKey = config.get<string>('BREVO_API_KEY') ?? '';
    this.fromEmail = config.get<string>('MAIL_FROM_EMAIL') ?? '';
    this.fromName = config.get<string>('MAIL_FROM_NAME') || 'Petpaws';

    if (wanted === 'brevo') {
      if (this.apiKey && this.fromEmail) {
        this.provider = 'brevo';
      } else {
        this.provider = 'none';
        this.logger.warn('MAIL_PROVIDER=brevo แต่ยังไม่มี BREVO_API_KEY / MAIL_FROM_EMAIL — ปิดระบบอีเมลไว้ก่อน');
      }
    } else if (wanted === 'log') {
      this.provider = 'log';
    } else {
      this.provider = 'none';
    }
  }

  /** true = มีผู้ให้บริการอีเมลพร้อมใช้ (ใช้ตัดสินว่าจะบังคับยืนยันอีเมลไหม) */
  get enabled(): boolean {
    return this.provider !== 'none';
  }

  async send(msg: MailMessage): Promise<void> {
    if (this.provider === 'log') {
      this.outbox.push(msg);
      if (this.outbox.length > 50) this.outbox.shift();
      this.logger.log(`[mail:log] ถึง ${msg.to} หัวข้อ "${msg.subject}"\n${msg.text}`);
      return;
    }
    if (this.provider !== 'brevo') return;

    const res = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'api-key': this.apiKey, 'content-type': 'application/json', accept: 'application/json' },
      body: JSON.stringify({
        sender: { name: this.fromName, email: this.fromEmail },
        to: [{ email: msg.to }],
        subject: msg.subject,
        htmlContent: msg.html,
        textContent: msg.text,
      }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) {
      // ไม่ใส่ body ของ error ลง log ตรงๆ เกินจำเป็น — แต่ตัดมาให้พอรู้สาเหตุ (เช่น sender ยังไม่ได้ยืนยัน)
      const detail = (await res.text().catch(() => '')).slice(0, 300);
      throw new Error(`Brevo ตอบ ${res.status}: ${detail}`);
    }
  }
}
