import { Inject, Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import type { Queue } from 'bullmq';
import type { Pool, PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AppException } from '../common/app-exception.js';
import { PUSH_QUEUE, SEND_MESSAGE_PUSH_JOB, type MessagePushJobData } from '../queue/queue.constants.js';
import { ChatGateway } from './chat.gateway.js';
import { ChatMediaService, type ResolvedMedia } from './chat-media.service.js';
import type { CreateChatDto } from './dto/create-chat.dto.js';
import type { CreateMediaUploadDto } from './dto/create-media-upload.dto.js';
import type { ListMessagesQueryDto } from './dto/list-messages.dto.js';
import type { MessageMediaDto, MessageMediaType } from './dto/message-media.dto.js';

const DEFAULT_PAGE_SIZE = 50;

export interface MessageMedia {
  type: MessageMediaType;
  url: string;
  thumbnailUrl: string;
  width: number;
  height: number;
  durationMs: number | null;
}

export interface SentMessage {
  id: string;
  senderId: string;
  text: string;
  media: MessageMedia | null;
  createdAt: Date;
}

interface MessageRow {
  id: string;
  sender_id: string;
  body: string;
  media_type: MessageMediaType | null;
  media_url: string | null;
  thumbnail_url: string | null;
  media_width: number | null;
  media_height: number | null;
  media_duration_ms: number | null;
  created_at: Date;
  read_at: Date | null;
}

/** สิ่งที่ผู้ใช้ส่งมา 1 ข้อความ — ตรวจแล้วว่าไม่ว่างและสื่อเป็นของผู้ส่งจริง */
interface MessageContent {
  text: string;
  media: ResolvedMedia | null;
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
}

@Injectable()
export class ChatService {
  private readonly logger = new Logger('ChatService');

  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly chatGateway: ChatGateway,
    private readonly chatMedia: ChatMediaService,
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
    };
  }

  private toMessage(row: MessageRow) {
    return {
      id: row.id,
      senderId: row.sender_id,
      text: row.body,
      media: row.media_type
        ? {
            type: row.media_type,
            url: row.media_url!,
            thumbnailUrl: row.thumbnail_url!,
            width: row.media_width!,
            height: row.media_height!,
            durationMs: row.media_duration_ms,
          }
        : null,
      createdAt: row.created_at,
      // ผู้รับอ่านแล้วเมื่อไหร่ (null = ยังไม่อ่าน) — ให้ "อ่านแล้ว" อยู่ถาวร ไม่ใช่เห็นแค่ตอน event สด
      readAt: row.read_at,
    };
  }

  /** ข้อความต้องมีตัวหนังสือหรือสื่ออย่างน้อยหนึ่งอย่าง สื่อต้องเป็นของผู้ส่งและอัปเสร็จแล้ว */
  private async resolveContent(
    userId: string,
    text: string | undefined,
    media: MessageMediaDto | undefined,
  ): Promise<MessageContent> {
    const trimmed = text?.trim() ?? '';
    if (!trimmed && !media) {
      throw new AppException('EMPTY_MESSAGE', 'กรุณาพิมพ์ข้อความหรือแนบรูป/วิดีโอ');
    }
    return {
      text: trimmed,
      media: media ? await this.chatMedia.resolve(userId, media) : null,
    };
  }

  /** INSERT ข้อความ + claim ไฟล์แนบ (ต้องอยู่ใน transaction ที่ผู้เรียกเปิดไว้) */
  private async insertMessage(
    client: PoolClient,
    chatId: string,
    userId: string,
    content: MessageContent,
  ): Promise<SentMessage> {
    const m = content.media;
    const res = await client.query<{ id: string; created_at: Date }>(
      `INSERT INTO messages (conversation_id, sender_id, body, created_at,
         media_type, media_url, thumbnail_url, media_width, media_height, media_duration_ms)
       VALUES ($1, $2, $3, now(), $4, $5, $6, $7, $8, $9)
       RETURNING id, created_at`,
      [
        chatId, userId, content.text,
        m?.type ?? null, m?.url ?? null, m?.thumbnailUrl ?? null,
        m?.width ?? null, m?.height ?? null, m?.durationMs ?? null,
      ],
    );
    if (m) await this.chatMedia.claim(client, userId, m.keys);
    return {
      id: res.rows[0].id,
      senderId: userId,
      text: content.text,
      media: m
        ? {
            type: m.type,
            url: m.url,
            thumbnailUrl: m.thumbnailUrl,
            width: m.width,
            height: m.height,
            durationMs: m.durationMs,
          }
        : null,
      createdAt: res.rows[0].created_at,
    };
  }

  private async inTransaction<T>(run: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await run(client);
      await client.query('COMMIT');
      return result;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  createMediaUpload(userId: string, dto: CreateMediaUploadDto) {
    return this.chatMedia.createUpload(userId, dto);
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

    const existing = await this.pool.query<{ id: string }>(
      `SELECT id FROM conversations WHERE pet_id = $1 AND initiator_id = $2`,
      [dto.petId, userId],
    );

    if (existing.rows.length > 0) {
      const chatId = existing.rows[0].id;
      await this.sendMessage(userId, chatId, { text: dto.message, media: dto.media });
      return { chatId };
    }

    const content = await this.resolveContent(userId, dto.message, dto.media);
    const { chatId, message } = await this.inTransaction(async (client) => {
      const convRes = await client.query<{ id: string }>(
        `INSERT INTO conversations (pet_id, initiator_id, owner_id)
         VALUES ($1, $2, $3) RETURNING id`,
        [dto.petId, userId, ownerId],
      );
      const id = convRes.rows[0].id;
      return { chatId: id, message: await this.insertMessage(client, id, userId, content) };
    });

    this.afterMessageSent(chatId, ownerId, message);
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
         CASE WHEN c.initiator_id = $1 THEN c.initiator_unread_count ELSE c.owner_unread_count END AS unread_count
       FROM conversations c
       JOIN pets p ON p.id = c.pet_id
       JOIN users ui ON ui.id = c.initiator_id
       JOIN users uo ON uo.id = c.owner_id
       WHERE (c.initiator_id = $1 OR c.owner_id = $1)
         AND ($2::text IS NULL OR p.name = $2)
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

  /**
   * ประวัติข้อความทีละหน้า: ดึงใหม่สุดก่อน แล้วกลับลำดับเป็นเก่า -> ใหม่ให้แอปแสดงผลตรง ๆ
   * วิ่งบน index messages_conversation_idx (conversation_id, created_at DESC, id DESC)
   * ห้องจะมีกี่หมื่นข้อความ แต่ละหน้าก็อ่านแค่ limit แถว
   */
  async messages(userId: string, chatId: string, query: ListMessagesQueryDto = {}) {
    await this.assertParticipant(chatId, userId);
    const res = await this.pool.query<MessageRow>(
      `SELECT id, sender_id, body, media_type, media_url, thumbnail_url,
              media_width, media_height, media_duration_ms, created_at, read_at
       FROM messages
       WHERE conversation_id = $1 AND deleted_at IS NULL
         AND ($2::uuid IS NULL OR (created_at, id) < (
           SELECT created_at, id FROM messages WHERE id = $2 AND conversation_id = $1
         ))
       ORDER BY created_at DESC, id DESC
       LIMIT $3`,
      [chatId, query.before ?? null, query.limit ?? DEFAULT_PAGE_SIZE],
    );
    return res.rows.reverse().map((r) => this.toMessage(r));
  }

  async sendMessage(userId: string, chatId: string, dto: { text?: string; media?: MessageMediaDto }) {
    const conv = await this.assertParticipant(chatId, userId);
    if (conv.status !== 'active') {
      throw AppException.forbidden('ห้องแชทนี้ถูกปิดแล้ว ส่งข้อความใหม่ไม่ได้');
    }
    const content = await this.resolveContent(userId, dto.text, dto.media);
    const message = await this.inTransaction((client) =>
      this.insertMessage(client, chatId, userId, content),
    );
    const recipientId = conv.initiator_id === userId ? conv.owner_id : conv.initiator_id;
    this.afterMessageSent(chatId, recipientId, message);
    return { success: true, message };
  }

  async markRead(userId: string, chatId: string) {
    await this.assertParticipant(chatId, userId);
    await this.pool.query(`SELECT mark_conversation_read($1, $2)`, [chatId, userId]);
    // อีกฝ่ายที่เปิดห้องอยู่เห็น "อ่านแล้ว" + เครื่องอื่นของผู้อ่านเอง badge ลดตาม
    this.chatGateway.emitRead(chatId, userId, new Date());
    this.chatGateway.notifyUsers([userId], { type: 'read', conversationId: chatId });
    return { success: true };
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
