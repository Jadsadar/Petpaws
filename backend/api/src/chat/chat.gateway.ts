import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Inject, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import type { Namespace, Socket } from 'socket.io';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';

interface AuthedSocket extends Socket {
  data: { userId?: string };
}

// ข้อความ error ที่แอปใช้ตัดสินใจว่า "token หมดอายุ -> refresh แล้วต่อใหม่"
// ต่างจาก error อื่น (เน็ตหลุด) ที่ socket.io reconnect ให้เองอยู่แล้ว
export const WS_UNAUTHORIZED = 'unauthorized';

const conversationRoom = (id: string) => `conversation:${id}`;
const userRoom = (id: string) => `user:${id}`;

// CORS อ่านจาก process.env ตรง ๆ เพราะ @WebSocketGateway ต้องกำหนด option ตอน
// class ถูก evaluate (ก่อน Nest DI พร้อมใช้งาน) — ตรรกะเดียวกับ CORS_ORIGIN ใน main.ts
const corsOrigin = process.env.CORS_ORIGIN;

/**
 * WS gateway ของแชท — ช่องทางส่งของ "สด" เท่านั้น การส่งข้อความ/อ่านแล้ว ยังผ่าน REST
 * เสมอ (ChatService เรียก emit* หลังเขียน DB สำเร็จ) WS จึงไม่มีทางทำให้ข้อมูลเพี้ยน
 *
 * ห้องมี 2 แบบ:
 *   user:{id}          — ทุก socket ของผู้ใช้คนนั้น เข้าอัตโนมัติตอน connect
 *                         ใช้ส่ง 'notification' ให้กล่องข้อความ/badge อัปเดตโดยไม่ต้องเปิดห้อง
 *   conversation:{id}  — เข้าเองด้วย 'join' หลังตรวจว่าเป็นคู่สนทนา
 *                         ได้รับ 'message', 'read', 'typing' ของห้องนั้น
 *
 * ยังไม่มี Redis adapter — ถูกต้องเฉพาะตอนมี API instance เดียว
 * ถ้าจะสเกลหลาย instance ต้องเพิ่ม @socket.io/redis-adapter ก่อน (ROADMAP 7.7)
 *
 * หมายเหตุ: JwtAuthGuard (APP_GUARD global) ข้าม context ที่ไม่ใช่ 'http' ไว้แล้ว
 * ไม่งั้น @SubscribeMessage ทุกตัวจะถูกปฏิเสธเงียบ ๆ (ดู common/jwt-auth.guard.ts)
 */
@WebSocketGateway({
  namespace: '/chat',
  cors: {
    origin: !corsOrigin || corsOrigin === '*' ? true : corsOrigin.split(','),
    credentials: true,
  },
})
export class ChatGateway implements OnGatewayInit, OnGatewayConnection {
  private readonly logger = new Logger('ChatGateway');

  @WebSocketServer()
  server!: Namespace;

  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    @Inject(PG_POOL) private readonly pool: Pool,
  ) {}

  /**
   * ตรวจ JWT เป็น middleware (ก่อน connect สำเร็จ) ไม่ใช่ใน handleConnection
   * — ฝั่งแอปจะได้ 'connect_error' พร้อมข้อความ 'unauthorized' แยกออกจากเน็ตหลุดได้
   * แล้ว refresh token ต่อใหม่เอง ถ้าตัดทิ้งหลัง connect แอปจะแยกสองกรณีนี้ไม่ออก
   *
   * client ส่ง access token ตัวเดียวกับ REST: io(url + '/chat', { auth: { token } })
   */
  afterInit(server: Namespace) {
    server.use((socket: AuthedSocket, next) => {
      const authToken = socket.handshake.auth?.token as string | undefined;
      const headerAuth = socket.handshake.headers.authorization;
      const token = authToken ?? (headerAuth?.startsWith('Bearer ') ? headerAuth.slice(7) : undefined);
      if (!token) return next(new Error(WS_UNAUTHORIZED));
      try {
        const payload = this.jwt.verify<{ sub: string }>(token, {
          secret: this.config.getOrThrow<string>('JWT_ACCESS_SECRET'),
        });
        socket.data.userId = payload.sub;
        next();
      } catch {
        next(new Error(WS_UNAUTHORIZED));
      }
    });
  }

  // middleware ผ่านแล้วเท่านั้นถึงมาถึงตรงนี้ — userId มีค่าแน่นอน
  handleConnection(client: AuthedSocket) {
    client.join(userRoom(client.data.userId!));
  }

  /**
   * ต้อง join ห้องก่อนถึงจะได้ 'message' / 'read' / 'typing' ของห้องนั้น — ตรวจว่าเป็น
   * คู่สนทนาจริงก่อน กันคนแปลกหน้าดักฟัง ตอบ ack { ok } ให้แอปรู้ผล
   */
  @SubscribeMessage('join')
  async handleJoin(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() data: { conversationId?: string },
  ) {
    const userId = client.data.userId;
    const conversationId = data?.conversationId;
    if (!userId || !conversationId) return { ok: false };

    const res = await this.pool.query<{ initiator_id: string; owner_id: string }>(
      `SELECT initiator_id, owner_id FROM conversations WHERE id = $1`,
      [conversationId],
    ).catch(() => ({ rows: [] })); // id ไม่ใช่ uuid -> ถือว่าไม่พบ ไม่ใช่ error ของ server
    const row = res.rows[0];
    if (!row || (row.initiator_id !== userId && row.owner_id !== userId)) {
      this.logger.warn(`user ${userId} tried to join conversation ${conversationId} ที่ไม่ใช่ของตัวเอง`);
      return { ok: false };
    }

    await client.join(conversationRoom(conversationId));
    return { ok: true };
  }

  @SubscribeMessage('leave')
  handleLeave(@ConnectedSocket() client: AuthedSocket, @MessageBody() data: { conversationId?: string }) {
    if (data?.conversationId) client.leave(conversationRoom(data.conversationId));
  }

  /**
   * บอกอีกฝ่ายว่ากำลังพิมพ์ — ส่งต่อเฉพาะห้องที่ socket นี้ join ผ่านการตรวจแล้ว
   * (เช็ก client.rooms ไม่ต้องยิง DB ทุกครั้งที่กดแป้น) และไม่ส่งกลับหาตัวเอง
   */
  @SubscribeMessage('typing')
  handleTyping(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() data: { conversationId?: string; isTyping?: boolean },
  ) {
    const conversationId = data?.conversationId;
    if (!conversationId || !client.rooms.has(conversationRoom(conversationId))) return;
    client.to(conversationRoom(conversationId)).emit('typing', {
      conversationId,
      userId: client.data.userId,
      isTyping: data.isTyping === true,
    });
  }

  /** ข้อความใหม่เข้าห้อง — คนที่เปิดห้องอยู่เห็นทันที */
  emitNewMessage(conversationId: string, message: Record<string, unknown>) {
    this.server.to(conversationRoom(conversationId)).emit('message', { conversationId, ...message });
  }

  /** อีกฝ่ายอ่านถึงเวลานี้แล้ว — ใช้โชว์ "อ่านแล้ว" ใต้ข้อความของเรา */
  emitRead(conversationId: string, userId: string, readAt: Date) {
    this.server.to(conversationRoom(conversationId)).emit('read', { conversationId, userId, readAt });
  }

  /**
   * แจ้งทุกเครื่องของผู้ใช้เหล่านี้ว่ามีอะไรเปลี่ยนในกล่องข้อความ (ข้อความใหม่ /
   * อ่านแล้วจากอีกเครื่อง) — แอปใช้ดึงรายการห้อง + badge ใหม่ ไม่ต้อง poll
   */
  notifyUsers(userIds: string[], payload: Record<string, unknown>) {
    this.server.to(userIds.map(userRoom)).emit('notification', payload);
  }
}
