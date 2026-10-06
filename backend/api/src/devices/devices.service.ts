import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, type Repository } from 'typeorm';
import { DeviceToken } from '../database/entities/index.js';
import type { RegisterDeviceDto } from './dto/register-device.dto.js';

@Injectable()
export class DevicesService {
  constructor(@InjectRepository(DeviceToken) private readonly devices: Repository<DeviceToken>) {}

  /**
   * token เดียวกันย้ายเจ้าของได้จริง (ดู comment บนตาราง device_tokens ใน
   * migration 002) — unique อยู่ที่ token อย่างเดียว จึง upsert ด้วย
   * ON CONFLICT (token) แทนที่จะ insert ใหม่ทุกครั้งที่แอปเปิด
   */
  async register(userId: string, dto: RegisterDeviceDto) {
    await this.devices.upsert(
      { userId, token: dto.token, platform: dto.platform, lastSeenAt: () => 'now()' },
      { conflictPaths: ['token'] },
    );
    return { success: true };
  }

  async tokensForUser(userId: string): Promise<string[]> {
    const rows = await this.devices.find({ select: { token: true }, where: { userId } });
    return rows.map((r) => r.token);
  }

  /** ลบ token ที่ FCM ตอบว่าใช้ไม่ได้แล้ว (ถอนแอป / token หมดอายุ) */
  async removeTokens(tokens: string[]): Promise<void> {
    if (tokens.length === 0) return;
    await this.devices.delete({ token: In(tokens) });
  }
}
