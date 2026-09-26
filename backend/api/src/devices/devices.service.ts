import { Inject, Injectable } from '@nestjs/common';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import type { RegisterDeviceDto } from './dto/register-device.dto.js';

@Injectable()
export class DevicesService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  /**
   * token เดียวกันย้ายเจ้าของได้จริง (ดู comment บนตาราง device_tokens ใน
   * migration 002) — unique อยู่ที่ token อย่างเดียว จึง upsert ด้วย
   * ON CONFLICT (token) แทนที่จะ insert ใหม่ทุกครั้งที่แอปเปิด
   */
  async register(userId: string, dto: RegisterDeviceDto) {
    await this.pool.query(
      `INSERT INTO device_tokens (user_id, token, platform, last_seen_at)
       VALUES ($1, $2, $3, now())
       ON CONFLICT (token) DO UPDATE
         SET user_id = excluded.user_id,
             platform = excluded.platform,
             last_seen_at = now()`,
      [userId, dto.token, dto.platform],
    );
    return { success: true };
  }

  async tokensForUser(userId: string): Promise<string[]> {
    const res = await this.pool.query<{ token: string }>(
      `SELECT token FROM device_tokens WHERE user_id = $1`,
      [userId],
    );
    return res.rows.map((r) => r.token);
  }

  /** ลบ token ที่ FCM ตอบว่าใช้ไม่ได้แล้ว (ถอนแอป / token หมดอายุ) */
  async removeTokens(tokens: string[]): Promise<void> {
    if (tokens.length === 0) return;
    await this.pool.query(`DELETE FROM device_tokens WHERE token = ANY($1::text[])`, [tokens]);
  }
}
