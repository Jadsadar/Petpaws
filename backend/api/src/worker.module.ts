import { Module } from '@nestjs/common';
import { AppConfigModule } from './config/app-config.module.js';
import { DatabaseModule } from './database/database.module.js';
import { QueueModule } from './queue/queue.module.js';
import { DevicesModule } from './devices/devices.module.js';
import { MediaModule } from './media/media.module.js';
import { FcmService } from './notifications/fcm.service.js';
import { PushProcessor } from './notifications/push.processor.js';
import { MediaCleanupProcessor } from './media/media-cleanup.processor.js';

/**
 * process แยกจาก API (src/worker.ts) — processor ประกาศไว้ที่นี่ที่เดียว
 * API server ไม่ import โมดูลนี้ จึงแค่ add job เข้าคิว ไม่ได้ประมวลผลเอง
 * สเกล worker แยกจาก API ได้ และงานหนักไม่แย่ง event loop ของ request
 */
@Module({
  imports: [AppConfigModule, DatabaseModule, QueueModule, DevicesModule, MediaModule],
  providers: [FcmService, PushProcessor, MediaCleanupProcessor],
})
export class WorkerModule {}
