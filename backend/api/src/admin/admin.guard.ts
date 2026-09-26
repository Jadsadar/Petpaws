import { CanActivate, ExecutionContext, Inject, Injectable } from '@nestjs/common';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AppException } from '../common/app-exception.js';

/**
 * ใช้คู่กับ JwtAuthGuard (global) ซึ่งรันก่อนและแนบ request.user ไว้แล้ว
 * เช็ก is_admin จาก DB ทุกครั้ง ไม่ใช่จาก JWT — payload มีแค่ sub และถ้าถอด
 * สิทธิ์แอดมินต้องมีผลทันที ไม่ใช่รอ token หมดอายุ
 */
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const userId: string | undefined = context.switchToHttp().getRequest().user?.id;
    if (!userId) throw AppException.unauthorized();

    const res = await this.pool.query<{ is_admin: boolean }>(
      `SELECT is_admin FROM users WHERE id = $1 AND deleted_at IS NULL`,
      [userId],
    );
    if (!res.rows[0]?.is_admin) throw AppException.forbidden('เฉพาะแอดมินเท่านั้น');
    return true;
  }
}
