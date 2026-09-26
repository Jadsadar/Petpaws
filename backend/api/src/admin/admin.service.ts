import { Inject, Injectable } from '@nestjs/common';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AppException } from '../common/app-exception.js';
import type { BanUserDto } from './dto/ban-user.dto.js';

/**
 * รายงานค้างทุกฉบับ พร้อม "ผู้ใช้ที่ถูกรายงานจริง" — รายงานประกาศนับเข้าเจ้าของประกาศ
 * รายงานข้อความนับเข้าคนส่ง รวมกับรายงานตัวผู้ใช้ตรง ๆ เพื่อให้คนที่โดนรายงานผ่าน
 * ประกาศ/ข้อความถึงเกณฑ์ได้เหมือนกัน (reports บังคับเป้าหมายพอดี 1 อย่างอยู่แล้ว)
 */
const PENDING_TARGETS = `
  target AS (
    SELECT r.id, r.reporter_id, r.created_at,
           COALESCE(r.reported_user_id, p.owner_id, m.sender_id) AS user_id
    FROM reports r
    LEFT JOIN pets p     ON p.id = r.reported_pet_id
    LEFT JOIN messages m ON m.id = r.reported_message_id
    WHERE r.status IN ('pending', 'reviewing')
  )`;

interface ReportedUserRow {
  id: string;
  username: string;
  display_name: string;
  avatar_url: string | null;
  is_suspended: boolean;
  suspended_until: Date | null;
  report_count: string;
  last_reported_at: Date | null;
}

@Injectable()
export class AdminService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  private toUser(r: ReportedUserRow) {
    return {
      id: r.id,
      username: r.username,
      displayName: r.display_name,
      avatarUrl: r.avatar_url ?? '',
      reportCount: Number(r.report_count),
      lastReportedAt: r.last_reported_at,
      isSuspended: r.is_suspended,
      suspendedUntil: r.suspended_until,
    };
  }

  /** นับจาก "คนรายงานไม่ซ้ำ" กันคนเดียวรายงานตัว+ประกาศ+ข้อความแล้วนับเป็น 3 */
  async reportedUsers(minReports: number) {
    const res = await this.pool.query<ReportedUserRow>(
      `WITH ${PENDING_TARGETS}
       SELECT u.id, u.username, u.display_name, u.avatar_url, u.is_suspended, u.suspended_until,
              count(DISTINCT t.reporter_id) AS report_count,
              max(t.created_at) AS last_reported_at
       FROM target t
       JOIN users u ON u.id = t.user_id
       WHERE u.deleted_at IS NULL
       GROUP BY u.id
       HAVING count(DISTINCT t.reporter_id) >= $1
       ORDER BY report_count DESC, last_reported_at DESC`,
      [minReports],
    );
    return res.rows.map((r) => this.toUser(r));
  }

  async userReports(userId: string) {
    const res = await this.pool.query<{
      id: string;
      reason: string;
      detail: string | null;
      created_at: Date;
      reporter_id: string;
      reporter_username: string;
      reporter_name: string;
      reported_user_id: string | null;
      reported_pet_id: string | null;
      pet_name: string | null;
      reported_message_id: string | null;
      message_body: string | null;
    }>(
      `WITH ${PENDING_TARGETS}
       SELECT r.id, r.reason, r.detail, r.created_at,
              r.reporter_id, ru.username AS reporter_username, ru.display_name AS reporter_name,
              r.reported_user_id, r.reported_pet_id, p.name AS pet_name,
              r.reported_message_id, m.body AS message_body
       FROM target t
       JOIN reports r   ON r.id = t.id
       JOIN users ru    ON ru.id = r.reporter_id
       LEFT JOIN pets p     ON p.id = r.reported_pet_id
       LEFT JOIN messages m ON m.id = r.reported_message_id
       WHERE t.user_id = $1
       ORDER BY r.created_at DESC`,
      [userId],
    );
    return res.rows.map((r) => ({
      id: r.id,
      reason: r.reason,
      detail: r.detail ?? '',
      createdAt: r.created_at,
      reporter: { id: r.reporter_id, username: r.reporter_username, displayName: r.reporter_name },
      targetType: r.reported_pet_id ? 'pet' : r.reported_message_id ? 'message' : 'user',
      petId: r.reported_pet_id,
      petName: r.pet_name,
      messageId: r.reported_message_id,
      messageBody: r.message_body,
    }));
  }

  async bannedUsers() {
    const res = await this.pool.query<{
      id: string;
      username: string;
      display_name: string;
      avatar_url: string | null;
      suspended_until: Date | null;
    }>(
      `SELECT id, username, display_name, avatar_url, suspended_until
       FROM users
       WHERE is_suspended AND deleted_at IS NULL
         AND (suspended_until IS NULL OR suspended_until > now())
       ORDER BY suspended_until NULLS FIRST`,
    );
    return res.rows.map((r) => ({
      id: r.id,
      username: r.username,
      displayName: r.display_name,
      avatarUrl: r.avatar_url ?? '',
      suspendedUntil: r.suspended_until,
      permanent: r.suspended_until === null,
    }));
  }

  async ban(adminId: string, userId: string, dto: BanUserDto) {
    if (userId === adminId) throw AppException.forbidden('แบนตัวเองไม่ได้');

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      const target = await client.query<{ is_admin: boolean }>(
        `SELECT is_admin FROM users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`,
        [userId],
      );
      if (target.rows.length === 0) throw AppException.notFound('ไม่พบผู้ใช้นี้');
      if (target.rows[0].is_admin) throw AppException.forbidden('แบนแอดมินด้วยกันไม่ได้');

      const updated = await client.query<{ suspended_until: Date | null }>(
        `UPDATE users
         SET is_suspended = true,
             suspended_until = CASE WHEN $2::int IS NULL THEN NULL
                                    ELSE now() + make_interval(days => $2::int) END
         WHERE id = $1
         RETURNING suspended_until`,
        [userId, dto.days ?? null],
      );

      // เตะออกจากทุกเครื่อง — access token ที่ออกไปแล้วยังใช้ได้จนหมดอายุ (JWT_ACCESS_TTL)
      await client.query(
        `UPDATE refresh_tokens SET revoked_at = now(), revoked_reason = 'suspended'
         WHERE user_id = $1 AND revoked_at IS NULL`,
        [userId],
      );

      // ปิดรายงานค้างของคนนี้ให้หลุดจากคิว (reviewed_at ต้องมีค่าตาม CHECK reports_reviewed_consistent)
      await client.query(
        `WITH ${PENDING_TARGETS}
         UPDATE reports
         SET status = 'actioned', reviewed_by = $2, reviewed_at = now(), review_note = $3
         WHERE id IN (SELECT id FROM target WHERE user_id = $1)`,
        [userId, adminId, dto.note ?? null],
      );

      await client.query('COMMIT');
      return { success: true, suspendedUntil: updated.rows[0].suspended_until };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async unban(userId: string) {
    const res = await this.pool.query(
      `UPDATE users SET is_suspended = false, suspended_until = NULL
       WHERE id = $1 AND deleted_at IS NULL`,
      [userId],
    );
    if (res.rowCount === 0) throw AppException.notFound('ไม่พบผู้ใช้นี้');
    return { success: true };
  }

  async dismissReports(adminId: string, userId: string) {
    const res = await this.pool.query(
      `WITH ${PENDING_TARGETS}
       UPDATE reports
       SET status = 'dismissed', reviewed_by = $2, reviewed_at = now()
       WHERE id IN (SELECT id FROM target WHERE user_id = $1)`,
      [userId, adminId],
    );
    return { success: true, dismissed: res.rowCount ?? 0 };
  }
}
