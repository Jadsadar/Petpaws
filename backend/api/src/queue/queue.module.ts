import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { BullModule } from '@nestjs/bullmq';
import { Redis } from 'ioredis';
import { MEDIA_CLEANUP_QUEUE, PUSH_QUEUE } from './queue.constants.js';

const RETRY_ATTEMPTS = 3;
const RETRY_BASE_DELAY_MS = 5_000; // exponential: 5s -> 10s -> 20s
const KEEP_COMPLETED_JOBS = 1_000;

/**
 * ประกาศ Redis connection + ค่าเริ่มต้นของ job ไว้ที่เดียว ใช้ทั้งฝั่ง API (แค่ add job)
 * และ worker process (ประมวลผล) — processor อยู่ใน WorkerModule เท่านั้น
 * API server จึงไม่มี worker แอบรันอยู่ในตัว
 */
@Module({
  imports: [
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        // BullMQ v6 ไม่แถม ioredis และในโหมด ESM (package.json "type": "module") ต้องส่ง
        // client ที่สร้างแล้วเข้าไป ส่งแค่ host/port จะพังตอนรันจริง (unit test จับไม่ได้)
        // maxRetriesPerRequest: null = ค่าที่ BullMQ บังคับสำหรับ worker
        connection: new Redis(config.getOrThrow<string>('REDIS_URL'), { maxRetriesPerRequest: null }),
        defaultJobOptions: {
          attempts: RETRY_ATTEMPTS,
          backoff: { type: 'exponential', delay: RETRY_BASE_DELAY_MS },
          removeOnComplete: KEEP_COMPLETED_JOBS,
          // เก็บ job ที่ล้มเหลวครบทุก attempt ไว้ทั้งหมด ไว้ตรวจย้อนหลัง/สั่งรันซ้ำ
          removeOnFail: false,
        },
      }),
    }),
    BullModule.registerQueue({ name: PUSH_QUEUE }, { name: MEDIA_CLEANUP_QUEUE }),
  ],
  exports: [BullModule],
})
export class QueueModule {}
