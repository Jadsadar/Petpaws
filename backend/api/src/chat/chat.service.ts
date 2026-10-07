import { Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import type { Queue } from 'bullmq';
import { InjectDataSource, InjectRepository } from '@nestjs/typeorm';
import { IsNull, type DataSource, type EntityManager, type Repository } from 'typeorm';
import { AppException } from '../common/app-exception.js';
import { Block, Conversation, ConversationHide, Message, Pet } from '../database/entities/index.js';
import {
  PUSH_COALESCE_MS,
  PUSH_QUEUE,
  SEND_MESSAGE_PUSH_JOB,
  type MessagePushJobData,
} from '../queue/queue.constants.js';
import { ChatGateway } from './chat.gateway.js';
import { ChatMediaService, type ResolvedMedia } from './chat-media.service.js';
import type { CreateChatDto } from './dto/create-chat.dto.js';
import type { CreateMediaUploadDto } from './dto/create-media-upload.dto.js';
import type { ListMessagesQueryDto } from './dto/list-messages.dto.js';
import type { LookupChatQueryDto } from './dto/lookup-chat.dto.js';
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
  /** id ที่แอปของผู้ส่งสร้างเอง — แอปใช้จับคู่ข้อความที่รอส่งกับข้อความจริง (null = แอปรุ่นก่อน) */
  clientId: string | null;
}

/** unique index ของ (sender_id, client_id) — ชนแปลว่าข้อความนี้ถูกบันทึกไปแล้วจากคำขอก่อนหน้า */
const CLIENT_ID_CONSTRAINT = 'messages_sender_client_id_key';
/** unique (pet_id, initiator_id) — ชนแปลว่ามีคำขออื่นสร้างห้องนี้ไปก่อนหน้าเสี้ยววินาที */
const CONVERSATION_CONSTRAINT = 'conversations_pet_initiator_key';

const isUniqueViolation = (err: unknown, constraint: string) =>
  (err as { code?: string; constraint?: string })?.code === '23505' &&
  (err as { constraint?: string }).constraint === constraint;

/** สถานะห้องที่ใช้ตรวจสิทธิ์และตอบสถานะห้อง */
type RoomRow = Pick<Conversation, 'initiatorId' | 'ownerId' | 'status' | 'closedReason'>;

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
  status: string;
  closed_reason: string | null;
  blocked_by_me: boolean;
}

@Injectable()
export class ChatService {
  private readonly logger = new Logger('ChatService');

  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    @InjectRepository(Conversation) private readonly conversations: Repository<Conversation>,
    @InjectRepository(Message) private readonly messagesRepo: Repository<Message>,
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
    void this.notifyInbox(chatId, [recipientId, message.senderId], {
      type: 'message',
      conversationId: chatId,
      message: { ...message },
    });
    // jobId = messageId กันยิง push ซ้ำถ้ามีการ enqueue ข้อความเดิมสองรอบ
    // delay = รอดูก่อนว่าจะมีข้อความตามมาติด ๆ ไหม (ส่งหลายรูป) จะได้เด้งครั้งเดียว
    this.pushQueue
      .add(SEND_MESSAGE_PUSH_JOB, { messageId: message.id }, { jobId: message.id, delay: PUSH_COALESCE_MS })
      .catch((err: Error) => this.logger.error(`enqueue push ไม่สำเร็จ message=${message.id}`, err.stack));
  }

  /**
   * แจ้ง 'notification' (กล่องข้อความเปลี่ยน) พร้อมสถานะล่าสุด "ของแต่ละคน" แนบไปด้วย:
   *   room        — ห้องนี้ในกล่องข้อความของคนนั้น (ข้อความล่าสุด, ยังไม่อ่านกี่ข้อความ, สถานะห้อง)
   *   unreadTotal — ยังไม่อ่านรวมทุกห้อง (badge)
   * แอปแก้ข้อมูลในเครื่องได้เลย ไม่ต้องยิง GET /chats (query หนักสุดของแชท) + GET /chats/unread-count
   * ใหม่ทุกครั้งที่มีข้อความเข้า — 1 query ตรงนี้แทนคำขอ HTTP 2–6 ครั้งจากทั้งสองฝั่ง
   *
   * ไม่ throw: ถ้า query ล้มก็ยังส่งแจ้งเตือนแบบไม่มีข้อมูลแนบ แอปจะถอยไปดึงใหม่เองเหมือนเดิม
   * คงเป็น SQL (unnest ผู้ใช้หลายคน + ยอดรวมทุกห้องในคำสั่งเดียว)
   */
  private async notifyInbox(chatId: string, userIds: string[], payload: Record<string, unknown>) {
    const snapshots = new Map<string, Record<string, unknown>>();
    try {
      const rows = await this.dataSource.query<{
        user_id: string;
        unread_count: number;
        unread_total: number;
        last_message: string | null;
        last_message_at: Date;
        status: string;
        closed_reason: string | null;
        pet_name: string;
      }[]>(
        `SELECT u.id AS user_id,
                CASE WHEN c.initiator_id = u.id THEN c.initiator_unread_count ELSE c.owner_unread_count END
                  AS unread_count,
                (SELECT COALESCE(SUM(CASE WHEN a.initiator_id = u.id
                                          THEN a.initiator_unread_count ELSE a.owner_unread_count END), 0)
                   FROM conversations a WHERE a.initiator_id = u.id OR a.owner_id = u.id)::int AS unread_total,
                c.last_message_preview AS last_message, c.last_message_at, c.status, c.closed_reason,
                p.name AS pet_name
           FROM unnest($2::uuid[]) AS u(id)
           JOIN conversations c ON c.id = $1
           JOIN pets p ON p.id = c.pet_id`,
        [chatId, userIds],
      );
      for (const r of rows) {
        snapshots.set(r.user_id, {
          room: {
            lastMessage: r.last_message ?? '',
            lastMessageAt: r.last_message_at,
            unreadCount: r.unread_count,
            status: r.status,
            closedReason: r.closed_reason,
            petName: r.pet_name,
          },
          unreadTotal: r.unread_total,
        });
      }
    } catch (err) {
      this.logger.warn(`อ่านสถานะกล่องข้อความไม่สำเร็จ chat=${chatId}: ${(err as Error).message}`);
    }
    for (const userId of new Set(userIds)) {
      this.chatGateway.notifyUsers([userId], { ...payload, ...snapshots.get(userId) });
    }
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

  private toMessage(m: Message) {
    return {
      id: m.id,
      senderId: m.senderId,
      text: m.body,
      // 'user' = คนพิมพ์ / 'system' = ประกาศของระบบ (สัตว์ได้บ้าน/ยกเลิกประกาศ) แอปวาดกลางจอ
      kind: m.kind,
      media: m.mediaType
        ? {
            type: m.mediaType,
            url: m.mediaUrl!,
            thumbnailUrl: m.thumbnailUrl!,
            width: m.mediaWidth!,
            height: m.mediaHeight!,
            durationMs: m.mediaDurationMs,
          }
        : null,
      createdAt: m.createdAt,
      // ผู้รับอ่านแล้วเมื่อไหร่ (null = ยังไม่อ่าน) — ให้ "อ่านแล้ว" อยู่ถาวร ไม่ใช่เห็นแค่ตอน event สด
      readAt: m.readAt,
      clientId: m.clientId,
    };
  }

  /** ข้อความที่ผู้ส่งคนนี้เคยบันทึกด้วย clientId นี้แล้ว (ส่งซ้ำหลังคำตอบหาย) */
  private async findSent(userId: string, clientId: string) {
    const m = await this.messagesRepo.findOneBy({ senderId: userId, clientId });
    return m ? this.toMessage(m) : null;
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
    em: EntityManager,
    chatId: string,
    userId: string,
    content: MessageContent,
    clientId: string | null,
  ): Promise<SentMessage> {
    const m = content.media;
    const res = await em
      .createQueryBuilder()
      .insert()
      .into(Message)
      .values({
        conversationId: chatId,
        senderId: userId,
        body: content.text,
        mediaType: m?.type ?? null,
        mediaUrl: m?.url ?? null,
        thumbnailUrl: m?.thumbnailUrl ?? null,
        mediaWidth: m?.width ?? null,
        mediaHeight: m?.height ?? null,
        mediaDurationMs: m?.durationMs ?? null,
        clientId,
      })
      .returning(['id', 'created_at'])
      .execute();
    const inserted = (res.raw as { id: string; created_at: Date }[])[0];
    if (m) await this.chatMedia.claim(em, userId, m.keys);
    return {
      id: inserted.id,
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
      createdAt: inserted.created_at,
      clientId,
    };
  }

  /** บล็อกกันอยู่ไหม (ทางใดทางหนึ่ง) */
  private blockedEitherWay(a: string, b: string) {
    return this.dataSource
      .getRepository(Block)
      .exists({ where: [{ blockerId: a, blockedId: b }, { blockerId: b, blockedId: a }] });
  }

  private findRoomId(petId: string, initiatorId: string) {
    return this.conversations.findOne({ select: { id: true }, where: { petId, initiatorId } });
  }

  createMediaUpload(userId: string, dto: CreateMediaUploadDto) {
    return this.chatMedia.createUpload(userId, dto);
  }

  /**
   * หาห้องแชทของ (pet, ฉัน) ถ้ามีอยู่แล้วให้ส่งข้อความต่อ ถ้ายังไม่มีให้สร้างพร้อม
   * ข้อความแรกในธุรกรรมเดียวกัน — ตรงกับที่ DB บังคับไว้ (ดู CreateChatDto)
   */
  async createOrSend(userId: string, dto: CreateChatDto) {
    const pet = await this.dataSource
      .getRepository(Pet)
      .findOne({ select: { ownerId: true }, where: { id: dto.petId, deletedAt: IsNull() } });
    if (!pet) throw AppException.notFound('ไม่พบประกาศนี้');
    const ownerId = pet.ownerId;
    if (ownerId === userId) {
      throw AppException.forbidden('นี่คือประกาศของคุณเอง แชทกับตัวเองไม่ได้');
    }

    if (await this.blockedEitherWay(userId, ownerId)) {
      throw AppException.forbidden('ไม่สามารถส่งข้อความหาผู้ใช้นี้ได้');
    }

    const existing = await this.findRoomId(dto.petId, userId);
    if (existing) {
      return this.sendIntoExisting(userId, existing.id, dto);
    }

    const content = await this.resolveContent(userId, dto.message, dto.media);
    let created: { chatId: string; message: SentMessage };
    try {
      // ห้องต้องมีข้อความแรกใน transaction เดียวกัน (DB บังคับด้วย deferred trigger)
      created = await this.dataSource.transaction(async (em) => {
        const conv = await em.insert(Conversation, { petId: dto.petId, initiatorId: userId, ownerId });
        const id = conv.identifiers[0].id as string;
        return { chatId: id, message: await this.insertMessage(em, id, userId, content, dto.clientId ?? null) };
      });
    } catch (err) {
      // อีกคำขอ (เช่น กดส่งซ้ำขณะคำขอแรกยังไม่เสร็จ) สร้างห้องไปก่อนเสี้ยววินาที —
      // ห้องมีแล้ว ส่งเข้าห้องนั้นแทน ไม่ใช่ตอบ 409 ให้ผู้ใช้งง
      if (!isUniqueViolation(err, CONVERSATION_CONSTRAINT)) throw err;
      const room = await this.findRoomId(dto.petId, userId);
      return this.sendIntoExisting(userId, room!.id, dto);
    }

    this.afterMessageSent(created.chatId, ownerId, created.message);
    return { chatId: created.chatId };
  }

  private async sendIntoExisting(userId: string, chatId: string, dto: CreateChatDto) {
    await this.sendMessage(userId, chatId, { text: dto.message, media: dto.media, clientId: dto.clientId });
    return { chatId };
  }

  /**
   * รายการห้องแชททั้งหมดของฉัน เรียงข้อความล่าสุดก่อน กรองด้วยชื่อสัตว์ได้ (ตาม ChatInboxScreen เดิม)
   * คงเป็น SQL — คอลัมน์ "ฝั่งอีกคน" เลือกด้วย CASE ต่อแถว + EXISTS บล็อก/ซ่อน
   */
  async list(userId: string, petName?: string) {
    const rows = await this.dataSource.query<ChatRow[]>(
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
    return rows.map((r) => this.toChat(r));
  }

  /**
   * ห้องแชทเดิมของประกาศนี้ระหว่างฉันกับอีกฝ่าย (null = ยังไม่เคยคุย) — แทนการโหลด GET /chats
   * ทั้งกล่องมาวนหาในแอป วิ่งบน unique index (pet_id, initiator_id) ห้องเยอะแค่ไหนก็ query เดียว
   * ห้องที่ฉันลบไปแล้ว (ยังไม่มีข้อความใหม่) ถือว่าไม่เจอ ให้ตรงกับที่ GET /chats ไม่แสดง
   */
  async lookup(userId: string, query: LookupChatQueryDto) {
    const room = await this.conversations
      .createQueryBuilder('c')
      .select('c.id', 'id')
      .where('c.pet_id = :petId', { petId: query.petId })
      .andWhere('((c.initiator_id = :me AND c.owner_id = :other) OR (c.initiator_id = :other AND c.owner_id = :me))', {
        me: userId,
        other: query.otherUserId,
      })
      .andWhere(
        `NOT EXISTS (SELECT 1 FROM conversation_hides h
                      WHERE h.conversation_id = c.id AND h.user_id = :me AND h.hidden_at >= c.last_message_at)`,
      )
      .getRawOne<{ id: string }>();
    return { chatId: room?.id ?? null };
  }

  private async assertParticipant(chatId: string, userId: string): Promise<RoomRow> {
    const row = await this.conversations.findOne({
      select: { initiatorId: true, ownerId: true, status: true, closedReason: true },
      where: { id: chatId },
    });
    if (!row) throw AppException.notFound('ไม่พบห้องแชทนี้');
    if (row.initiatorId !== userId && row.ownerId !== userId) {
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
    const conv = await this.assertParticipant(chatId, userId);
    const qb = this.messagesRepo
      .createQueryBuilder('m')
      .where('m.conversation_id = :chatId AND m.deleted_at IS NULL', { chatId })
      // ข้อความก่อนเวลาที่ฉันลบแชทไม่โผล่กลับมา (ดู conversation_hides)
      .andWhere(
        `m.created_at > COALESCE(
           (SELECT h.hidden_at FROM conversation_hides h WHERE h.conversation_id = :chatId AND h.user_id = :userId),
           '-infinity'::timestamptz)`,
        { userId },
      )
      .orderBy('m.created_at', 'DESC')
      .addOrderBy('m.id', 'DESC')
      .limit(query.limit ?? DEFAULT_PAGE_SIZE);
    if (query.before) {
      // keyset: ก่อนข้อความ before (เทียบ (created_at, id) คู่กัน — เวลาเท่ากันก็ไม่ซ้ำ/ไม่หาย)
      qb.andWhere(
        '(m.created_at, m.id) < (SELECT b.created_at, b.id FROM messages b WHERE b.id = :before AND b.conversation_id = :chatId)',
        { before: query.before },
      );
    }
    const page = qb.getMany();
    if (query.include !== 'room') {
      return (await page).reverse().map((m) => this.toMessage(m));
    }
    // หน้าแชทเปิดห้อง: ส่งสถานะห้องมาในคำขอเดียวกัน ไม่ต้องยิง GET /chats/:id แยก
    const [rows, room] = await Promise.all([page, this.roomStatus(userId, chatId, conv)]);
    return { messages: rows.reverse().map((m) => this.toMessage(m)), room };
  }

  /**
   * [dto.clientId] = ข้อความนี้เคยถูกส่งมาแล้วหรือยัง (แอปส่งซ้ำตอนคำตอบหาย/กดลองใหม่):
   * เคยบันทึกแล้ว → คืนข้อความเดิมโดยไม่บันทึก/แจ้งเตือนซ้ำ ต้องเช็กก่อน resolveContent
   * เพราะไฟล์แนบของข้อความเดิมถูก claim ไปแล้ว จะโดนปฏิเสธว่า "ถูกใช้ไปแล้ว"
   */
  async sendMessage(
    userId: string,
    chatId: string,
    dto: { text?: string; media?: MessageMediaDto; clientId?: string },
  ) {
    const conv = await this.assertParticipant(chatId, userId);
    const clientId = dto.clientId ?? null;
    if (clientId) {
      const sent = await this.findSent(userId, clientId);
      if (sent) return { success: true, message: sent };
    }
    if (conv.status !== 'active') {
      throw AppException.forbidden('ห้องแชทนี้ถูกปิดแล้ว ส่งข้อความใหม่ไม่ได้');
    }
    const content = await this.resolveContent(userId, dto.text, dto.media);
    let message: SentMessage;
    try {
      message = await this.dataSource.transaction((em) =>
        this.insertMessage(em, chatId, userId, content, clientId),
      );
    } catch (err) {
      // คำขอซ้ำสองอันมาถึงพร้อมกัน ตัวแรกบันทึกไปแล้ว — ตอบด้วยข้อความเดียวกัน
      if (!clientId || !isUniqueViolation(err, CLIENT_ID_CONSTRAINT)) throw err;
      const sent = await this.findSent(userId, clientId);
      if (!sent) throw err;
      return { success: true, message: sent };
    }
    const recipientId = conv.initiatorId === userId ? conv.ownerId : conv.initiatorId;
    this.afterMessageSent(chatId, recipientId, message);
    return { success: true, message };
  }

  async markRead(userId: string, chatId: string) {
    await this.assertParticipant(chatId, userId);
    // ฟังก์ชันใน DB: อัปเดต read_at ของข้อความ + ล้าง unread ของห้องในคำสั่งเดียว
    await this.dataSource.query(`SELECT mark_conversation_read($1, $2)`, [chatId, userId]);
    // อีกฝ่ายที่เปิดห้องอยู่เห็น "อ่านแล้ว" + เครื่องอื่นของผู้อ่านเอง badge ลดตาม
    this.chatGateway.emitRead(chatId, userId, new Date());
    await this.notifyInbox(chatId, [userId], { type: 'read', conversationId: chatId });
    return { success: true };
  }

  /** สถานะห้อง + ฉันบล็อกอีกฝ่ายอยู่ไหม — หน้าแชทใช้เลือกว่าจะโชว์ช่องพิมพ์หรือแถบ "ห้องถูกปิด" */
  async detail(userId: string, chatId: string) {
    return this.roomStatus(userId, chatId, await this.assertParticipant(chatId, userId));
  }

  private async roomStatus(userId: string, chatId: string, conv: RoomRow) {
    const otherId = conv.initiatorId === userId ? conv.ownerId : conv.initiatorId;
    const blockedByMe = await this.dataSource
      .getRepository(Block)
      .exists({ where: { blockerId: userId, blockedId: otherId } });
    return {
      id: chatId,
      status: conv.status,
      closedReason: conv.closedReason,
      otherUserId: otherId,
      blockedByMe,
    };
  }

  /** ลบแชท = ซ่อนเฉพาะฝั่งฉัน อีกฝ่ายยังเห็นครบ ข้อความใหม่ในภายหลังจะทำให้ห้องกลับมา */
  async hide(userId: string, chatId: string) {
    await this.assertParticipant(chatId, userId);
    await this.dataSource
      .getRepository(ConversationHide)
      .upsert({ conversationId: chatId, userId, hiddenAt: () => 'now()' }, { conflictPaths: ['conversationId', 'userId'] });
    await this.notifyInbox(chatId, [userId], { type: 'hidden', conversationId: chatId });
    return { success: true };
  }

  /**
   * ข้อความระบบที่ trigger ใน DB ใส่ให้ตอนสัตว์ได้บ้าน/ประกาศถูกยกเลิก (migration 015)
   * DB เขียนข้อความให้แล้ว แต่ไม่รู้จัก WebSocket — เรียกหลัง commit เพื่อดันให้คนที่เปิดห้องอยู่เห็นทันที
   * [since] = เวลาก่อนสั่งเปลี่ยนสถานะ (นาฬิกา DB)
   */
  async broadcastSystemMessages(petId: string, since: Date) {
    const rows = await this.messagesRepo
      .createQueryBuilder('m')
      .innerJoin(Conversation, 'c', 'c.id = m.conversation_id')
      .select([
        'm.id AS id',
        'm.conversation_id AS conversation_id',
        'm.sender_id AS sender_id',
        'm.body AS body',
        'm.created_at AS created_at',
        'c.initiator_id AS initiator_id',
        'c.owner_id AS owner_id',
      ])
      .where(`c.pet_id = :petId AND m.kind = 'system' AND m.created_at >= :since`, { petId, since })
      .getRawMany<{
        id: string;
        conversation_id: string;
        sender_id: string;
        body: string;
        created_at: Date;
        initiator_id: string;
        owner_id: string;
      }>();
    for (const r of rows) {
      const message = {
        id: r.id,
        senderId: r.sender_id,
        text: r.body,
        kind: 'system',
        media: null,
        createdAt: r.created_at,
      };
      this.chatGateway.emitNewMessage(r.conversation_id, { ...message });
      await this.notifyInbox(r.conversation_id, [r.initiator_id, r.owner_id], {
        type: 'message',
        conversationId: r.conversation_id,
        message,
      });
    }
  }

  /** unread รวมทุกห้อง ไว้ทำ badge บน bottom nav / app bar (unreadChatCountStream เดิม) */
  async unreadCount(userId: string) {
    const [row] = await this.dataSource.query<{ total: string }[]>(
      `SELECT COALESCE(SUM(
         CASE WHEN initiator_id = $1 THEN initiator_unread_count ELSE owner_unread_count END
       ), 0) AS total
       FROM conversations WHERE initiator_id = $1 OR owner_id = $1`,
      [userId],
    );
    return { count: Number(row.total) };
  }
}
