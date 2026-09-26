import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { cert, initializeApp } from 'firebase-admin/app';
import { getMessaging, type Messaging } from 'firebase-admin/messaging';

// token ที่ FCM บอกว่าตายถาวร (ถอนแอป / token หมดอายุ) ต้องลบทิ้ง ไม่ใช่ retry
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

export interface PushResult {
  successCount: number;
  deadTokens: string[];
  retryableFailures: number;
}

@Injectable()
export class FcmService {
  private readonly logger = new Logger('FcmService');
  private readonly messaging: Messaging | null;

  constructor(config: ConfigService) {
    const projectId = config.get<string>('FCM_PROJECT_ID');
    const clientEmail = config.get<string>('FCM_CLIENT_EMAIL');
    const privateKey = config.get<string>('FCM_PRIVATE_KEY');

    if (!projectId || !clientEmail || !privateKey) {
      this.logger.warn('ไม่ได้ตั้ง FCM_* ใน .env — ข้ามการส่ง push ทั้งหมด (ปกติตอน dev)');
      this.messaging = null;
      return;
    }

    // private key ใน .env เก็บเป็นบรรทัดเดียวที่มี \n ตัวอักษร ต้องแปลงกลับเป็นขึ้นบรรทัดจริง
    const app = initializeApp(
      { credential: cert({ projectId, clientEmail, privateKey: privateKey.replace(/\\n/g, '\n') }) },
      'petpaws-push',
    );
    this.messaging = getMessaging(app);
  }

  get enabled(): boolean {
    return this.messaging !== null;
  }

  async send(
    tokens: string[],
    notification: { title: string; body: string },
    data: Record<string, string>,
  ): Promise<PushResult> {
    if (!this.messaging) return { successCount: 0, deadTokens: [], retryableFailures: 0 };

    const res = await this.messaging.sendEachForMulticast({ tokens, notification, data });
    const deadTokens: string[] = [];
    let retryableFailures = 0;
    res.responses.forEach((r, i) => {
      if (r.success) return;
      if (r.error && DEAD_TOKEN_CODES.has(r.error.code)) deadTokens.push(tokens[i]);
      else retryableFailures++;
    });
    return { successCount: res.successCount, deadTokens, retryableFailures };
  }
}
