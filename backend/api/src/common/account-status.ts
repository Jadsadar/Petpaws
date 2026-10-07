import { Global, Injectable, Module } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { IsNull, type DataSource } from 'typeorm';
import { User } from '../database/entities/index.js';

/** จำผลไว้นานเท่านี้ — แลกกับการแบน/ลบบัญชีมีผลช้าได้ไม่เกินเท่านี้บน API ตัวอื่น */
export const ACCOUNT_STATUS_TTL_MS = 30_000;
const MAX_ENTRIES = 10_000;

export type AccountStatus = 'active' | 'missing' | 'suspended';

/**
 * บัญชียังใช้งานได้ไหม (ยังอยู่ และไม่ถูกแบน) — JwtAuthGuard ถามทุก request
 *
 * เดิม query users ทุก request (เกือบครึ่งของ query ทั้งระบบ) — จำผลไว้ในหน่วยความจำ 30 วินาที
 * แบน/ปลดแบนผ่าน API ตัวนี้ล้างค่าที่จำไว้ทันที ([forget]) ส่วน API ตัวอื่นหลัง load balancer
 * จะรู้ภายใน 30 วินาที (refresh token ถูกเพิกถอนตอนแบนอยู่แล้ว เข้าระบบใหม่ไม่ได้ตั้งแต่ตอนนั้น)
 */
@Injectable()
export class AccountStatusService {
  private readonly cache = new Map<string, { status: AccountStatus; expires: number }>();

  constructor(@InjectDataSource() private readonly dataSource: DataSource) {}

  async status(userId: string): Promise<AccountStatus> {
    const now = Date.now();
    const hit = this.cache.get(userId);
    if (hit && hit.expires > now) return hit.status;

    const user = await this.dataSource.getRepository(User).findOne({
      select: { id: true, isSuspended: true, suspendedUntil: true },
      where: { id: userId, deletedAt: IsNull() },
    });
    // แบนหมดเวลาแล้ว = ใช้งานได้ (ระบบปลดให้จริงตอนล็อกอินครั้งถัดไป)
    const suspended = !!user?.isSuspended && (!user.suspendedUntil || user.suspendedUntil > new Date());
    const status: AccountStatus = !user ? 'missing' : suspended ? 'suspended' : 'active';

    // Map เรียงตามลำดับที่ใส่ — เต็มแล้วทิ้งตัวที่เก่าสุด กันหน่วยความจำโตไม่จำกัด
    if (this.cache.size >= MAX_ENTRIES && !this.cache.has(userId)) {
      this.cache.delete(this.cache.keys().next().value!);
    }
    this.cache.set(userId, { status, expires: now + ACCOUNT_STATUS_TTL_MS });
    return status;
  }

  /** สถานะบัญชีเปลี่ยน (แบน/ปลดแบน) — ให้ request ถัดไปอ่านจาก DB ใหม่ */
  forget(userId: string) {
    this.cache.delete(userId);
  }
}

@Global()
@Module({
  providers: [AccountStatusService],
  exports: [AccountStatusService],
})
export class AccountStatusModule {}
