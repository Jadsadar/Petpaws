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
// กวาดไฟล์แชททีละชุด — คืนไหนค้างเยอะผิดปกติก็ไม่ถือ query/ลิสต์ก้อนใหญ่ค้างไว้ในหน่วยความจำ
const CHAT_SWEEP_BATCH = 1000;

/**
 * ลบไฟล์ใน S3 ที่ไม่มีแถวไหนใน DB อ้างถึง และค้างนานเกิน 24 ชม.
 * เกิดจากอัปรูปแล้วไม่ได้กดบันทึกประกาศ/โปรไฟล์ หรือเปลี่ยนรูปใหม่ทับ
 *
 * เกณฑ์ 24 ชม. กันลบไฟล์ที่เพิ่งอัปแล้วผู้ใช้ยังกรอกฟอร์มอยู่
 * ประกาศที่ soft delete แล้วยังมีแถว pet_media อยู่ รูปจึงไม่ถูกลบ (ห้องแชทยังเปิดดูได้)
 *
 * ไฟล์มี 2 กลุ่ม ตรวจคนละวิธี:
 * - uploads/ (รูปประกาศ/avatar ที่อัปผ่าน API) — ลิสต์ไฟล์ใน S3 แล้วเทียบกับ URL ใน DB
 * - chat/    (รูป/วิดีโอแชท อัปผ่าน presigned POST) — ไม่ต้องลิสต์ S3 เลย ทุกไฟล์มีแถว
 *            media_uploads อยู่แล้ว แค่หาแถวที่ไม่ถูก claim ผ่าน index media_uploads_orphan_idx
 *            ข้อความที่ถูก soft delete ยังถือว่า claim อยู่ ไฟล์จึงยังอยู่เป็นหลักฐานตอนถูกรายงาน
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
    const uploads = await this.sweepUploads();
    const chat = await this.sweepChatMedia();
    return { ...uploads, chatDeleted: chat };
  }

  private async sweepChatMedia() {
    const cutoff = new Date(Date.now() - ORPHAN_AGE_MS);
    let deleted = 0;
    for (;;) {
      // ลบแถวก่อน (DELETE ... RETURNING ใน statement เดียว) แล้วค่อยลบไฟล์ — ถ้ามีคน
      // claim ไฟล์นี้พอดีระหว่างนั้น claim จะหาแถวไม่เจอแล้วส่งไม่ผ่าน แทนที่จะได้ข้อความ
      // ที่ชี้ไปไฟล์ที่ถูกลบไปแล้ว (ถ้าพังหลังลบแถว ไฟล์ค้างใน S3 — เสียพื้นที่ แต่ไม่พัง)
      const res = await this.pool.query<{ storage_key: string }>(
        `DELETE FROM media_uploads
         WHERE id IN (
           SELECT id FROM media_uploads
           WHERE claimed_at IS NULL AND created_at < $1
           ORDER BY created_at
           LIMIT $2
           FOR UPDATE SKIP LOCKED
         ) AND claimed_at IS NULL
         RETURNING storage_key`,
        [cutoff, CHAT_SWEEP_BATCH],
      );
      const keys = res.rows.map((r) => r.storage_key);
      if (keys.length === 0) break;
      await this.media.deleteObjects(keys);
      deleted += keys.length;
      if (keys.length < CHAT_SWEEP_BATCH) break;
    }
    if (deleted > 0) this.logger.log(`ลบไฟล์แชทที่ไม่ถูกส่ง ${deleted} ไฟล์`);
    return deleted;
  }

  private async sweepUploads() {
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
