import { Inject, Logger } from '@nestjs/common';
import { Processor, WorkerHost } from '@nestjs/bullmq';
import type { Job } from 'bullmq';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { DevicesService } from '../devices/devices.service.js';
import { PUSH_COALESCE_MS, PUSH_QUEUE, type MessagePushJobData } from '../queue/queue.constants.js';
import { FcmService } from './fcm.service.js';

const PREVIEW_MAX_CHARS = 100;

/** ส่ง push "มีข้อความใหม่" ให้คู่สนทนาอีกฝ่ายทุกเครื่องที่ลงทะเบียนไว้ */
@Processor(PUSH_QUEUE)
export class PushProcessor extends WorkerHost {
  private readonly logger = new Logger('PushProcessor');

  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly devices: DevicesService,
    private readonly fcm: FcmService,
  ) {
    super();
  }

  async process(job: Job<MessagePushJobData>) {
    if (!this.fcm.enabled) return { skipped: 'fcm-disabled' };

    const res = await this.pool.query<{
      conversation_id: string;
      body: string;
      sender_name: string;
      recipient_id: string;
      superseded: boolean;
    }>(
      `SELECT m.conversation_id, message_preview(m.body, m.media_type) AS body, s.display_name AS sender_name,
              CASE WHEN m.sender_id = c.initiator_id THEN c.owner_id ELSE c.initiator_id END AS recipient_id,
              -- คนเดิมส่งข้อความใหม่ตามมาติด ๆ (ส่งหลายรูป) = ให้ push ของข้อความนั้นเด้งแทน
              EXISTS (
                SELECT 1 FROM messages n
                 WHERE n.conversation_id = m.conversation_id AND n.sender_id = m.sender_id
                   AND n.deleted_at IS NULL
                   AND (n.created_at, n.id) > (m.created_at, m.id)
                   AND n.created_at <= m.created_at + $2::int * interval '1 millisecond'
              ) AS superseded
       FROM messages m
       JOIN conversations c ON c.id = m.conversation_id
       JOIN users s ON s.id = m.sender_id
       WHERE m.id = $1 AND m.deleted_at IS NULL`,
      [job.data.messageId, PUSH_COALESCE_MS],
    );
    // ข้อความถูกลบไปก่อน worker มาถึง — ไม่มีอะไรต้องแจ้ง ไม่ใช่ error ที่ควร retry
    const msg = res.rows[0];
    if (!msg) return { skipped: 'message-gone' };
    if (msg.superseded) return { skipped: 'superseded' };

    const tokens = await this.devices.tokensForUser(msg.recipient_id);
    if (tokens.length === 0) return { skipped: 'no-tokens' };

    const result = await this.fcm.send(
      tokens,
      { title: msg.sender_name, body: msg.body.slice(0, PREVIEW_MAX_CHARS) },
      { type: 'chat_message', conversationId: msg.conversation_id },
    );
    await this.devices.removeTokens(result.deadTokens);

    // throw (ให้ BullMQ retry) เฉพาะตอนไม่มีเครื่องไหนได้รับเลย — ถ้าบางเครื่อง
    // ได้แล้วแล้ว retry ทั้งชุด เครื่องที่ได้แล้วจะเด้งซ้ำ
    if (result.successCount === 0 && result.retryableFailures > 0) {
      throw new Error(`FCM ส่งไม่สำเร็จ ${result.retryableFailures} เครื่อง message=${job.data.messageId}`);
    }
    if (result.deadTokens.length > 0) {
      this.logger.log(`ลบ token ที่ใช้ไม่ได้แล้ว ${result.deadTokens.length} ตัว`);
    }
    return { sent: result.successCount, removedTokens: result.deadTokens.length };
  }
}
