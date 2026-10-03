import { Inject, Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import type { Queue } from 'bullmq';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AppException } from '../common/app-exception.js';
import { PUSH_QUEUE, SEND_MESSAGE_PUSH_JOB, type MessagePushJobData } from '../queue/queue.constants.js';
import { ChatGateway } from './chat.gateway.js';
import type { CreateChatDto } from './dto/create-chat.dto.js';

interface SentMessage {
  id: string;
  senderId: string;
  text: string;
  createdAt: Date;
}

interface ChatRow {
  id: string;
  pet_id: string;
  pet_name: string;
  pet_image_url: string | null;
  other_user_id: string;
  other_user_name: string;
  other_user_avatar: string | null;
  last_message: string | null;
  last_message_at: Date;
  unread_count: number;
  status: string;
  closed_reason: string | null;
  blocked_by_me: boolean;
}

@Injectable()
export class ChatService {
  private readonly logger = new Logger('ChatService');

  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly chatGateway: ChatGateway,
    @InjectQueue(PUSH_QUEUE) private readonly pushQueue: Queue<MessagePushJobData>,
  ) {}

  /**
   * ข้อความ commit ลง DB แล้ว — ส่ง realtime ให้คนที่เปิดห้องอยู่ และโยน push เข้าคิว
   * ให้ worker ส่งทีหลัง (ไม่รอ FCM ใน request)
   *
   * ไม่ await การ enqueue: ถ้า Redis ล่ม add() จะค้างรอ reconnect แล้วลาก request
   * ส่งข้อความให้ค้างตาม และถ้าตอบ error กลับไป แอปจะกดส่งซ้ำได้ข้อความซ้ำ —
   * ข้อความบันทึกไปแล้ว เสีย push ไป 1 ครั้งยังดีกว่า
   */
  private afterMessageSent(chatId: string, recipientId: string, message: SentMessage) {
    this.chatGateway.emitNewMessage(chatId, { ...message });
    // ทั้งสองฝั่ง: ผู้รับได้ badge/ห้องใหม่ ผู้ส่งได้ lastMessage อัปเดตในเครื่องอื่นของตัวเอง
    this.chatGateway.notifyUsers([recipientId, message.senderId], {
      type: 'message',
      conversationId: chatId,
      message: { ...message },
    });
    // jobId = messageId กันยิง push ซ้ำถ้ามีการ enqueue ข้อความเดิมสองรอบ
    this.pushQueue
      .add(SEND_MESSAGE_PUSH_JOB, { messageId: message.id }, { jobId: message.id })
      .catch((err: Error) => this.logger.error(`enqueue push ไม่สำเร็จ message=${message.id}`, err.stack));
  }

  private toChat(row: ChatRow) {
    return {
      id: row.id,
      petId: row.pet_id,
      petName: row.pet_name,
      petImageUrl: row.pet_image_url ?? '',
      otherUserId: row.other_user_id,
      otherUserName: row.other_user_name,
      otherUserAvatarUrl: row.other_user_avatar ?? '',
      lastMessage: row.last_message ?? '',
      lastMessageAt: row.last_message_at,
      unreadCount: row.unread_count,
      status: row.status,
      closedReason: row.closed_reason,
      blockedByMe: row.blocked_by_me,
    };
  }

  /**
   * หาห้องแชทของ (pet, ฉัน) ถ้ามีอยู่แล้วให้ส่งข้อความต่อ ถ้ายังไม่มีให้สร้างพร้อม
   * ข้อความแรกในธุรกรรมเดียวกัน — ตรงกับที่ DB บังคับไว้ (ดู CreateChatDto)
   */
  async createOrSend(userId: string, dto: CreateChatDto) {
    const petRes = await this.pool.query<{ owner_id: string }>(
      `SELECT owner_id FROM pets WHERE id = $1 AND deleted_at IS NULL`,
      [dto.petId],
    );
    if (petRes.rows.length === 0) throw AppException.notFound('ไม่พบประกาศนี้');
    const ownerId = petRes.rows[0].owner_id;
    if (ownerId === userId) {
      throw AppException.forbidden('นี่คือประกาศของคุณเอง แชทกับตัวเองไม่ได้');
    }

    const blocked = await this.pool.query(
      `SELECT 1 FROM blocks
        WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)`,
      [userId, ownerId],
    );
    if (blocked.rows.length > 0) {
      throw AppException.forbidden('ไม่สามารถส่งข้อความหาผู้ใช้นี้ได้');
    }

    const existing = await this.pool.query<{ id: string }>(
      `SELECT id FROM conversations WHERE pet_id = $1 AND initiator_id = $2`,
      [dto.petId, userId],
    );

    if (existing.rows.length > 0) {
      const chatId = existing.rows[0].id;
      await this.sendMessage(userId, chatId, { text: dto.message });
      return { chatId };
    }

    let chatId: string;
    let msg: { id: string; created_at: Date };
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const convRes = await client.query<{ id: string }>(
        `INSERT INTO conversations (pet_id, initiator_id, owner_id)
         VALUES ($1, $2, $3) RETURNING id`,
        [dto.petId, userId, ownerId],
      );
      chatId = convRes.rows[0].id;
      const msgRes = await client.query<{ id: string; created_at: Date }>(
        `INSERT INTO messages (conversation_id, sender_id, body, created_at)
         VALUES ($1, $2, $3, now())
         RETURNING id, created_at`,
        [chatId, userId, dto.message],
      );
      msg = msgRes.rows[0];
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    this.afterMessageSent(chatId, ownerId, {
      id: msg.id,
      senderId: userId,
      text: dto.message,
      createdAt: msg.created_at,
    });
    return { chatId };
  }

  /** รายการห้องแชททั้งหมดของฉัน เรียงข้อความล่าสุดก่อน กรองด้วยชื่อสัตว์ได้ (ตาม ChatInboxScreen เดิม) */
  async list(userId: string, petName?: string) {
    const res = await this.pool.query<ChatRow>(
      `SELECT
         c.id, c.pet_id,
         p.name AS pet_name,
         (SELECT pm.url FROM pet_media pm WHERE pm.pet_id = p.id ORDER BY pm.sort_order LIMIT 1) AS pet_image_url,
         CASE WHEN c.initiator_id = $1 THEN c.owner_id ELSE c.initiator_id END AS other_user_id,
         CASE WHEN c.initiator_id = $1 THEN uo.display_name ELSE ui.display_name END AS other_user_name,
         CASE WHEN c.initiator_id = $1 THEN uo.avatar_url ELSE ui.avatar_url END AS other_user_avatar,
         c.last_message_preview AS last_message,
         c.last_message_at,
         CASE WHEN c.initiator_id = $1 THEN c.initiator_unread_count ELSE c.owner_unread_count END AS unread_count,
         c.status, c.closed_reason,
         EXISTS (
           SELECT 1 FROM blocks b WHERE b.blocker_id = $1
             AND b.blocked_id = CASE WHEN c.initiator_id = $1 THEN c.owner_id ELSE c.initiator_id END
         ) AS blocked_by_me
       FROM conversations c
       JOIN pets p ON p.id = c.pet_id
       JOIN users ui ON ui.id = c.initiator_id
       JOIN users uo ON uo.id = c.owner_id
       WHERE (c.initiator_id = $1 OR c.owner_id = $1)
         AND ($2::text IS NULL OR p.name = $2)
         -- ห้องที่ฉันลบไปแล้วจะไม่โผล่ จนกว่าจะมีข้อความใหม่หลังเวลาที่ลบ
         AND NOT EXISTS (
           SELECT 1 FROM conversation_hides h
            WHERE h.conversation_id = c.id AND h.user_id = $1 AND h.hidden_at >= c.last_message_at
         )
       ORDER BY c.last_message_at DESC`,
      [userId, petName ?? null],
    );
    return res.rows.map((r) => this.toChat(r));
  }

  private async assertParticipant(chatId: string, userId: string) {
    const res = await this.pool.query<{ initiator_id: string; owner_id: string; status: string }>(
      `SELECT initiator_id, owner_id, status FROM conversations WHERE id = $1`,
      [chatId],
    );
    if (res.rows.length === 0) throw AppException.notFound('ไม่พบห้องแชทนี้');
    const row = res.rows[0];
    if (row.initiator_id !== userId && row.owner_id !== userId) {
      throw AppException.forbidden('ไม่ใช่คู่สนทนาของห้องนี้');
    }
    return row;
  }

  async messages(userId: string, chatId: string) {
    await this.assertParticipant(chatId, userId);
    const res = await this.pool.query<{
      id: string;
      sender_id: string;
      body: string;
      created_at: Date;
      read_at: Date | null;
      kind: string;
    }>(
      `SELECT m.id, m.sender_id, m.body, m.created_at, m.read_at, m.kind FROM messages m
       WHERE m.conversation_id = $1 AND m.deleted_at IS NULL
         AND m.created_at > COALESCE(
           (SELECT h.hidden_at FROM conversation_hides h WHERE h.conversation_id = $1 AND h.user_id = $2),
           '-infinity'::timestamptz)
       ORDER BY m.created_at ASC LIMIT 200`,
      [chatId, userId],
    );
    return res.rows.map((r) => ({
      id: r.id,
      senderId: r.sender_id,
      text: r.body,
      kind: r.kind,
      createdAt: r.created_at,
      // ผู้รับอ่านแล้วเมื่อไหร่ (null = ยังไม่อ่าน) — ให้ "อ่านแล้ว" อยู่ถาวร ไม่ใช่เห็นแค่ตอน event สด
      readAt: r.read_at,
    }));
  }

  async sendMessage(userId: string, chatId: string, dto: { text: string }) {
    const conv = await this.assertParticipant(chatId, userId);
    if (conv.status !== 'active') {
      throw AppException.forbidden('ห้องแชทนี้ถูกปิดแล้ว ส่งข้อความใหม่ไม่ได้');
    }
    const msgRes = await this.pool.query<{ id: string; created_at: Date }>(
      `INSERT INTO messages (conversation_id, sender_id, body, created_at)
       VALUES ($1, $2, $3, now())
       RETURNING id, created_at`,
      [chatId, userId, dto.text],
    );
    const recipientId = conv.initiator_id === userId ? conv.owner_id : conv.initiator_id;
    this.afterMessageSent(chatId, recipientId, {
      id: msgRes.rows[0].id,
      senderId: userId,
      text: dto.text,
      createdAt: msgRes.rows[0].created_at,
    });
    return { success: true };
  }

  async markRead(userId: string, chatId: string) {
    await this.assertParticipant(chatId, userId);
    await this.pool.query(`SELECT mark_conversation_read($1, $2)`, [chatId, userId]);
    // อีกฝ่ายที่เปิดห้องอยู่เห็น "อ่านแล้ว" + เครื่องอื่นของผู้อ่านเอง badge ลดตาม
    this.chatGateway.emitRead(chatId, userId, new Date());
    this.chatGateway.notifyUsers([userId], { type: 'read', conversationId: chatId });
    return { success: true };
  }

  /** สถานะห้อง + ฉันบล็อกอีกฝ่ายอยู่ไหม — หน้าแชทใช้เลือกว่าจะโชว์ช่องพิมพ์หรือแถบ "ห้องถูกปิด" */
  async detail(userId: string, chatId: string) {
    const conv = await this.assertParticipant(chatId, userId);
    const otherId = conv.initiator_id === userId ? conv.owner_id : conv.initiator_id;
    const [info, blocked] = await Promise.all([
      this.pool.query<{ closed_reason: string | null }>(
        `SELECT closed_reason FROM conversations WHERE id = $1`,
        [chatId],
      ),
      this.pool.query(`SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2`, [userId, otherId]),
    ]);
    return {
      id: chatId,
      status: conv.status,
      closedReason: info.rows[0].closed_reason,
      otherUserId: otherId,
      blockedByMe: blocked.rows.length > 0,
    };
  }

  /** ลบแชท = ซ่อนเฉพาะฝั่งฉัน อีกฝ่ายยังเห็นครบ ข้อความใหม่ในภายหลังจะทำให้ห้องกลับมา */
  async hide(userId: string, chatId: string) {
    await this.assertParticipant(chatId, userId);
    await this.pool.query(
      `INSERT INTO conversation_hides (conversation_id, user_id, hidden_at)
       VALUES ($1, $2, now())
       ON CONFLICT (conversation_id, user_id) DO UPDATE SET hidden_at = now()`,
      [chatId, userId],
    );
    this.chatGateway.notifyUsers([userId], { type: 'hidden', conversationId: chatId });
    return { success: true };
  }

  /**
   * ข้อความระบบที่ trigger ใน DB ใส่ให้ตอนสัตว์ได้บ้าน/ประกาศถูกยกเลิก (migration 014)
   * DB เขียนข้อความให้แล้ว แต่ไม่รู้จัก WebSocket — เรียกหลัง commit เพื่อดันให้คนที่เปิดห้องอยู่เห็นทันที
   * [since] = เวลาก่อนสั่งเปลี่ยนสถานะ (นาฬิกา DB)
   */
  async broadcastSystemMessages(petId: string, since: Date) {
    const res = await this.pool.query<{
      id: string;
      conversation_id: string;
      sender_id: string;
      body: string;
      created_at: Date;
      initiator_id: string;
      owner_id: string;
    }>(
      `SELECT m.id, m.conversation_id, m.sender_id, m.body, m.created_at, c.initiator_id, c.owner_id
         FROM messages m JOIN conversations c ON c.id = m.conversation_id
        WHERE c.pet_id = $1 AND m.kind = 'system' AND m.created_at >= $2`,
      [petId, since],
    );
    for (const r of res.rows) {
      const message = { id: r.id, senderId: r.sender_id, text: r.body, kind: 'system', createdAt: r.created_at };
      this.chatGateway.emitNewMessage(r.conversation_id, { ...message });
      this.chatGateway.notifyUsers([r.initiator_id, r.owner_id], {
        type: 'message',
        conversationId: r.conversation_id,
        message,
      });
    }
  }

  /** unread รวมทุกห้อง ไว้ทำ badge บน bottom nav / app bar (unreadChatCountStream เดิม) */
  async unreadCount(userId: string) {
    const res = await this.pool.query<{ total: string }>(
      `SELECT COALESCE(SUM(
         CASE WHEN initiator_id = $1 THEN initiator_unread_count ELSE owner_unread_count END
       ), 0) AS total
       FROM conversations WHERE initiator_id = $1 OR owner_id = $1`,
      [userId],
    );
    return { count: Number(res.rows[0].total) };
  }
}
