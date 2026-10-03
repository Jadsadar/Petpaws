import { Inject, Injectable } from '@nestjs/common';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AppException } from '../common/app-exception.js';
import type { CreateReportDto } from './dto/create-report.dto.js';
import type { CreateBlockDto } from './dto/create-block.dto.js';

@Injectable()
export class ModerationService {
  constructor(@Inject(PG_POOL) private readonly pool: Pool) {}

  /**
   * "เป้าหมายพอดี 1 อย่าง" / "รายงานตัวเองไม่ได้" / "รายงานซ้ำเป้าหมายเดิมไม่ได้"
   * ถูกบังคับด้วย CHECK + unique partial index ใน migration 006 อยู่แล้ว —
   * ถ้าผิดกฎ pg จะโยน error ที่ AllExceptionsFilter แปลเป็นข้อความไทยให้เอง
   */
  async createReport(userId: string, dto: CreateReportDto) {
    if (dto.reportedMessageId) await this.assertCanReportMessage(userId, dto.reportedMessageId);

    const result = await this.pool.query<{ id: string }>(
      `INSERT INTO reports (reporter_id, reported_pet_id, reported_user_id, reported_message_id, reason, detail)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id`,
      [
        userId,
        dto.reportedPetId ?? null,
        dto.reportedUserId ?? null,
        dto.reportedMessageId ?? null,
        dto.reason,
        dto.detail ?? null,
      ],
    );
    return { id: result.rows[0].id };
  }

  /**
   * รายงานข้อความได้เฉพาะคนที่อยู่ในแชทนั้น และต้องเป็นข้อความของ "อีกฝ่าย" — ไม่งั้นใครรู้ id
   * ข้อความก็ส่งรายงานดึงแชทของคนอื่นเข้าไปให้แอดมินอ่านได้ (แอดมินเห็นเฉพาะข้อความที่ถูกรายงาน
   * ดังนั้นต้องกันไม่ให้ข้อความที่ไม่เกี่ยวกับผู้รายงานหลุดเข้าคิวรายงาน)
   */
  private async assertCanReportMessage(userId: string, messageId: string) {
    const res = await this.pool.query<{ sender_id: string; initiator_id: string; owner_id: string; kind: string }>(
      `SELECT m.sender_id, m.kind, c.initiator_id, c.owner_id
       FROM messages m
       JOIN conversations c ON c.id = m.conversation_id
       WHERE m.id = $1 AND m.deleted_at IS NULL`,
      [messageId],
    );
    const row = res.rows[0];
    if (!row) throw AppException.notFound('ไม่พบข้อความนี้');
    if (row.initiator_id !== userId && row.owner_id !== userId) {
      throw AppException.forbidden('รายงานได้เฉพาะข้อความในแชทของคุณ');
    }
    if (row.sender_id === userId || row.kind === 'system') {
      throw new AppException('INVALID_REPORT', 'รายงานข้อความนี้ไม่ได้');
    }
  }

  /**
   * บล็อกซ้ำ (กด 2 ครั้ง) ถือเป็นการ no-op ไม่ใช่ error — ผลลัพธ์ปลายทาง
   * เหมือนกันคือ "บล็อกอยู่" ไม่มีเหตุผลให้ผู้ใช้เห็น error ตอนกดปุ่มซ้ำ
   * (trigger blocks_close_conversations ยังทำงานปกติตอน insert ครั้งแรกเท่านั้น)
   */
  async createBlock(userId: string, dto: CreateBlockDto) {
    await this.pool.query(
      `INSERT INTO blocks (blocker_id, blocked_id, reason)
       VALUES ($1, $2, $3)
       ON CONFLICT (blocker_id, blocked_id) DO NOTHING`,
      [userId, dto.blockedUserId, dto.reason ?? null],
    );
    return { success: true };
  }

  async deleteBlock(userId: string, blockedUserId: string) {
    await this.pool.query(
      `DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2`,
      [userId, blockedUserId],
    );
    // ปลดบล็อก = เปิดห้องที่เคยถูกปิดเพราะบล็อกกลับมา — ยกเว้นอีกฝ่ายก็บล็อกเราอยู่ด้วย
    // (บล็อกมีผลสองทาง) หรือสัตว์ถูกลบ/ได้บ้านแล้ว ซึ่งห้องนั้นปิดด้วยเหตุผลอื่นอยู่แล้ว
    await this.pool.query(
      `UPDATE conversations c
          SET status = 'active', closed_at = NULL, closed_reason = NULL
        WHERE c.status = 'closed' AND c.closed_reason = 'blocked'
          AND ((c.initiator_id = $1 AND c.owner_id = $2) OR (c.initiator_id = $2 AND c.owner_id = $1))
          AND NOT EXISTS (
            SELECT 1 FROM blocks b
             WHERE (b.blocker_id = $1 AND b.blocked_id = $2) OR (b.blocker_id = $2 AND b.blocked_id = $1)
          )
          AND EXISTS (SELECT 1 FROM pets p WHERE p.id = c.pet_id AND p.deleted_at IS NULL AND p.status <> 'adopted')`,
      [userId, blockedUserId],
    );
    return { success: true };
  }
}
