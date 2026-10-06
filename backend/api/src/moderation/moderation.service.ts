import { Injectable } from '@nestjs/common';
import { InjectDataSource, InjectRepository } from '@nestjs/typeorm';
import type { DataSource, Repository } from 'typeorm';
import { AppException } from '../common/app-exception.js';
import { Block, Conversation, Message, Report } from '../database/entities/index.js';
import type { CreateReportDto } from './dto/create-report.dto.js';
import type { CreateBlockDto } from './dto/create-block.dto.js';

@Injectable()
export class ModerationService {
  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    @InjectRepository(Report) private readonly reports: Repository<Report>,
    @InjectRepository(Block) private readonly blocks: Repository<Block>,
  ) {}

  /**
   * "เป้าหมายพอดี 1 อย่าง" / "รายงานตัวเองไม่ได้" / "รายงานซ้ำเป้าหมายเดิมไม่ได้"
   * ถูกบังคับด้วย CHECK + unique partial index ใน migration 006 อยู่แล้ว —
   * ถ้าผิดกฎ pg จะโยน error ที่ AllExceptionsFilter แปลเป็นข้อความไทยให้เอง
   */
  async createReport(userId: string, dto: CreateReportDto) {
    if (dto.reportedMessageId) await this.assertCanReportMessage(userId, dto.reportedMessageId);

    const result = await this.reports.insert({
      reporterId: userId,
      reportedPetId: dto.reportedPetId ?? null,
      reportedUserId: dto.reportedUserId ?? null,
      reportedMessageId: dto.reportedMessageId ?? null,
      reason: dto.reason,
      detail: dto.detail ?? null,
    });
    return { id: result.identifiers[0].id as string };
  }

  /**
   * รายงานข้อความได้เฉพาะคนที่อยู่ในแชทนั้น และต้องเป็นข้อความของ "อีกฝ่าย" — ไม่งั้นใครรู้ id
   * ข้อความก็ส่งรายงานดึงแชทของคนอื่นเข้าไปให้แอดมินอ่านได้ (แอดมินเห็นเฉพาะข้อความที่ถูกรายงาน
   * ดังนั้นต้องกันไม่ให้ข้อความที่ไม่เกี่ยวกับผู้รายงานหลุดเข้าคิวรายงาน)
   */
  private async assertCanReportMessage(userId: string, messageId: string) {
    const row = await this.dataSource
      .createQueryBuilder(Message, 'm')
      .innerJoin(Conversation, 'c', 'c.id = m.conversation_id')
      .select(['m.sender_id AS sender_id', 'm.kind AS kind', 'c.initiator_id AS initiator_id', 'c.owner_id AS owner_id'])
      .where('m.id = :messageId AND m.deleted_at IS NULL', { messageId })
      .getRawOne<{ sender_id: string; kind: string; initiator_id: string; owner_id: string }>();
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
    await this.blocks
      .createQueryBuilder()
      .insert()
      .values({ blockerId: userId, blockedId: dto.blockedUserId, reason: dto.reason ?? null })
      .orIgnore()
      .execute();
    return { success: true };
  }

  async deleteBlock(userId: string, blockedUserId: string) {
    await this.blocks.delete({ blockerId: userId, blockedId: blockedUserId });
    // ปลดบล็อก = เปิดห้องที่เคยถูกปิดเพราะบล็อกกลับมา — ยกเว้นอีกฝ่ายก็บล็อกเราอยู่ด้วย
    // (บล็อกมีผลสองทาง) หรือสัตว์ถูกลบ/ได้บ้านแล้ว ซึ่งห้องนั้นปิดด้วยเหตุผลอื่นอยู่แล้ว
    await this.dataSource
      .createQueryBuilder()
      .update(Conversation)
      .set({ status: 'active', closedAt: null, closedReason: null })
      .where(`status = 'closed' AND closed_reason = 'blocked'`)
      .andWhere('((initiator_id = :me AND owner_id = :other) OR (initiator_id = :other AND owner_id = :me))')
      .andWhere(
        `NOT EXISTS (SELECT 1 FROM blocks b
                      WHERE (b.blocker_id = :me AND b.blocked_id = :other) OR (b.blocker_id = :other AND b.blocked_id = :me))`,
      )
      .andWhere(`EXISTS (SELECT 1 FROM pets p WHERE p.id = pet_id AND p.deleted_at IS NULL AND p.status <> 'adopted')`)
      .setParameters({ me: userId, other: blockedUserId })
      .execute();
    return { success: true };
  }
}
