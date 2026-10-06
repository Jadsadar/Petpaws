import { describe, expect, it, vi } from 'vitest';
import type { INestApplicationContext } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { RedisIoAdapter } from './redis-io.adapter.js';

const app = { getHttpServer: () => undefined } as unknown as INestApplicationContext;

describe('RedisIoAdapter', () => {
  it('ต่อ Redis ไม่ได้ ไม่ทำให้ API เปิดไม่ขึ้น — ถอยไปใช้ adapter ในหน่วยความจำ', async () => {
    const adapter = new RedisIoAdapter(app);

    // port 1 ไม่มีอะไรฟังอยู่ = ต่อไม่ติดทันที
    await expect(adapter.connectToRedis('redis://127.0.0.1:1')).resolves.toBeUndefined();

    expect(adapter.usingRedis).toBe(false);
  });

  it('ต่อได้แล้ว Socket.IO server ที่สร้างใช้ Redis adapter', () => {
    const adapter = new RedisIoAdapter(app);
    const redisAdapter = vi.fn();
    (adapter as unknown as { adapterConstructor: unknown }).adapterConstructor = redisAdapter;
    // ไม่เปิด server จริง — ดูแค่ว่าตั้ง adapter ให้ server ที่ IoAdapter สร้าง
    const server = { adapter: vi.fn() };
    vi.spyOn(IoAdapter.prototype, 'createIOServer').mockReturnValue(server as never);

    expect(adapter.createIOServer(0)).toBe(server);
    expect(server.adapter).toHaveBeenCalledWith(redisAdapter);
    expect(adapter.usingRedis).toBe(true);
  });
});
