import { Inject, Logger, type OnApplicationBootstrap } from '@nestjs/common';
import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import type { Queue } from 'bullmq';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { CLEANUP_ORPHAN_MEDIA_JOB, MEDIA_CLEANUP_QUEUE } from '../queue/queue.constants.js';
import { MediaService } from './media.service.js';

const ORPHAN_AGE_MS = 24 * 60 * 60 * 1000;
const NIGHTLY_CRON = '0 3 * * *'; // ตี 3 เวลาไทย — ช่วงที่คนใช้น้อยที่สุด
const SCHEDULER_ID = 'media-cleanup-nightly';

/**
 * ลบไฟล์ใน S3 ที่ไม่มีแถวไหนใน DB อ้างถึง และค้างนานเกิน 24 ชม.
 * เกิดจากอัปรูปแล้วไม่ได้กดบันทึกประกาศ/โปรไฟล์ หรือเปลี่ยนรูปใหม่ทับ
 *
 * เกณฑ์ 24 ชม. กันลบไฟล์ที่เพิ่งอัปแล้วผู้ใช้ยังกรอกฟอร์มอยู่
 * ประกาศที่ soft delete แล้วยังมีแถว pet_media อยู่ รูปจึงไม่ถูกลบ (ห้องแชทยังเปิดดูได้)
 */
@Processor(MEDIA_CLEANUP_QUEUE)
export class MediaCleanupProcessor extends WorkerHost implements OnApplicationBootstrap {
  private readonly logger = new Logger('MediaCleanupProcessor');

  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly media: MediaService,
    @InjectQueue(MEDIA_CLEANUP_QUEUE) private readonly queue: Queue,
  ) {
    super();
  }

  // upsert เรียกซ้ำได้ทุกครั้งที่ worker เริ่ม ไม่สร้าง schedule ซ้ำซ้อน
  async onApplicationBootstrap() {
    await this.queue.upsertJobScheduler(
      SCHEDULER_ID,
      { pattern: NIGHTLY_CRON, tz: 'Asia/Bangkok' },
      { name: CLEANUP_ORPHAN_MEDIA_JOB },
    );
  }

  async process() {
    const candidates = await this.media.listUploadsOlderThan(new Date(Date.now() - ORPHAN_AGE_MS));
    if (candidates.length === 0) return { deleted: 0 };

    // ponytail: ดึง URL ที่ถูกอ้างถึงทั้งหมดมาเทียบในแอป (seq scan คืนละครั้ง)
    // ถ้าตารางใหญ่จนช้า ค่อยเปลี่ยนไปใช้ media_uploads.claimed_at ที่ schema เตรียมไว้
    const res = await this.pool.query<{ url: string }>(
      `SELECT url FROM pet_media
       UNION
       SELECT avatar_url FROM users WHERE avatar_url IS NOT NULL`,
    );
    const referenced = new Set(res.rows.map((r) => this.media.keyFromUrl(r.url)).filter(Boolean));

    const orphans = candidates.filter((key) => !referenced.has(key));
    await this.media.deleteObjects(orphans);
    this.logger.log(`ลบไฟล์ค้าง ${orphans.length} ไฟล์ (ตรวจ ${candidates.length})`);
    return { deleted: orphans.length, checked: candidates.length };
  }
}
