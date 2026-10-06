import { INestApplicationContext, Logger } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import { Redis } from 'ioredis';
import type { Server, ServerOptions } from 'socket.io';

const CONNECT_TIMEOUT_MS = 3_000;

/**
 * Socket.IO ผ่าน Redis pub/sub — ให้ API หลายตัวหลัง load balancer ส่ง event ถึงกันได้
 *
 * ไม่มีตัวนี้: emit ไปห้อง conversation:{id} ถึงเฉพาะ socket ที่ต่ออยู่กับ API ตัวที่ emit
 * ผู้รับที่ต่ออยู่กับอีกตัวจะไม่เห็นข้อความสด (ต้องออกแล้วเข้าห้องใหม่) — มี adapter แล้ว
 * ทุกตัวกระจาย event ผ่าน Redis แล้วส่งให้ socket ของตัวเองที่อยู่ในห้องนั้น
 *
 * ใช้ Redis ตัวของคิว (REDIS_URL) — pub/sub ไม่เก็บข้อมูลลงหน่วยความจำ ไม่โดนไล่ทิ้งแบบตัว cache
 *
 * ต่อ Redis ไม่ได้ตอนเปิด = ใช้ adapter ในหน่วยความจำแบบเดิม (ถูกต้องเฉพาะ API ตัวเดียว)
 * ดีกว่าให้ API เปิดไม่ขึ้นทั้งตัว — log เตือนไว้ให้เห็น
 */
export class RedisIoAdapter extends IoAdapter {
  private readonly redisLogger = new Logger(RedisIoAdapter.name);
  private adapterConstructor: ReturnType<typeof createAdapter> | null = null;

  constructor(app: INestApplicationContext) {
    super(app);
  }

  get usingRedis() {
    return this.adapterConstructor !== null;
  }

  async connectToRedis(url: string): Promise<void> {
    const pub = new Redis(url, { lazyConnect: true });
    const sub = pub.duplicate();
    // ไม่ log ซ้ำทุกรอบที่ ioredis ต่อใหม่ — แค่ไม่ให้เป็น unhandled error event
    pub.on('error', () => {});
    sub.on('error', () => {});
    try {
      await Promise.race([
        Promise.all([pub.connect(), sub.connect()]),
        new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), CONNECT_TIMEOUT_MS)),
      ]);
    } catch (err) {
      pub.disconnect();
      sub.disconnect();
      this.redisLogger.warn(
        `ต่อ Redis สำหรับ WebSocket ไม่ได้ (${(err as Error).message}) — ใช้ adapter ในหน่วยความจำ ` +
          'ข้อความสดถึงกันได้เฉพาะตอนมี API ตัวเดียว',
      );
      return;
    }
    this.adapterConstructor = createAdapter(pub, sub);
  }

  override createIOServer(port: number, options?: ServerOptions): Server {
    const server = super.createIOServer(port, options) as Server;
    if (this.adapterConstructor) server.adapter(this.adapterConstructor);
    return server;
  }
}
