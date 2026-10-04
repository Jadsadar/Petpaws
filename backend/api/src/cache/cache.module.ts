import { Global, Logger, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Redis } from 'ioredis';
import { CACHE_REDIS, CACHE_STATS_KEY } from './cache.constants.js';
import { CacheService } from './cache.service.js';

// Redis ของ cache ห้ามรอนาน — ช้ากว่านี้อ่าน DB ตรงเร็วกว่า
const COMMAND_TIMEOUT_MS = 300;

/**
 * Redis ตัวนี้แยกจากตัวของ BullMQ (REDIS_URL) โดยตั้งใจ: คิวต้องใช้ noeviction + AOF
 * (งานห้ามหาย) ส่วน cache ต้องไล่ key เก่าทิ้งได้เมื่อหน่วยความจำเต็ม ถ้าใช้ร่วมกัน cache ที่โตจน
 * เต็มจะทำให้ add job ไม่ได้ (ดู redis-cache ใน docker-compose)
 *
 * Global เพื่อให้ service ไหนก็ inject CacheService ได้โดยไม่ต้อง import ซ้ำ
 */
@Global()
@Module({
  providers: [
    {
      provide: CACHE_REDIS,
      inject: [ConfigService],
      useFactory: (config: ConfigService): Redis | null => {
        const url = config.get<string>('REDIS_CACHE_URL');
        if (!url) {
          new Logger('CacheModule').warn('ไม่ได้ตั้ง REDIS_CACHE_URL — ปิด cache อ่าน DB ตรงทุกครั้ง');
          return null;
        }
        const redis = new Redis(url, {
          // fail fast: ตอนต่อไม่ติดให้คำสั่ง error ทันที (ไม่เข้าคิวรอ) แล้ว CacheService ไปอ่าน DB แทน
          enableOfflineQueue: false,
          maxRetriesPerRequest: 1,
          commandTimeout: COMMAND_TIMEOUT_MS,
        });
        // log แค่ตอนหลุดครั้งแรก ไม่งั้น ioredis ที่ reconnect วนจะพ่น log ทุกไม่กี่วินาที
        let down = false;
        redis.on('error', (err) => {
          if (down) return;
          down = true;
          new Logger('CacheModule').warn(`ต่อ Redis cache ไม่ได้: ${err.message}`);
        });
        redis.on('ready', () => {
          down = false;
          // จุดเริ่มนับของตัวนับ hit/miss (ตั้งครั้งแรกครั้งเดียว ทับเฉพาะตอนสั่ง reset)
          redis.hsetnx(CACHE_STATS_KEY, 'since', new Date().toISOString()).catch(() => {});
        });
        return redis;
      },
    },
    CacheService,
  ],
  exports: [CacheService],
})
export class CacheModule {}
