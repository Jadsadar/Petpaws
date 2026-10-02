import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Queue } from 'bullmq';
import type { Pool } from 'pg';
import type { MediaService } from './media.service.js';
import { MediaCleanupProcessor } from './media-cleanup.processor.js';

const BUCKET_URL = 'http://localhost:9000/petpaws-media/';

function setup({
  candidates = [] as string[],
  referencedUrls = [] as string[],
  // แต่ละรอบของ DELETE ... RETURNING ใน sweep แชท (หมดแล้วได้ [] เสมอ)
  chatBatches = [] as string[][],
} = {}) {
  const batches = [...chatBatches];
  const pool = {
    query: vi.fn((sql: string) =>
      Promise.resolve(
        sql.includes('DELETE FROM media_uploads')
          ? { rows: (batches.shift() ?? []).map((storage_key) => ({ storage_key })) }
          : { rows: referencedUrls.map((url) => ({ url })) },
      ),
    ),
  };
  const media = {
    listUploadsOlderThan: vi.fn().mockResolvedValue(candidates),
    deleteObjects: vi.fn().mockResolvedValue(undefined),
    keyFromUrl: vi.fn((url: string) => (url.startsWith(BUCKET_URL) ? url.slice(BUCKET_URL.length) : null)),
  };
  const queue = { upsertJobScheduler: vi.fn().mockResolvedValue(undefined) };
  const processor = new MediaCleanupProcessor(
    pool as unknown as Pool,
    media as unknown as MediaService,
    queue as unknown as Queue,
  );
  return { processor, pool, media, queue };
}

describe('MediaCleanupProcessor', () => {
  beforeEach(() => vi.clearAllMocks());

  it('ดูเฉพาะไฟล์ที่เก่ากว่า 24 ชม.', async () => {
    // Arrange
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-09-26T20:00:00Z'));
    const { processor, media } = setup();
    // Act
    await processor.process();
    // Assert
    expect(media.listUploadsOlderThan).toHaveBeenCalledWith(new Date('2026-09-25T20:00:00Z'));
    vi.useRealTimers();
  });

  it('ไม่มีไฟล์เก่าเลย ไม่ต้องเทียบ URL ใน DB และไม่ลบอะไร', async () => {
    const { processor, pool, media } = setup({ candidates: [] });

    const out = await processor.process();

    expect(out).toEqual({ deleted: 0, chatDeleted: 0 });
    // query เดียวที่เกิดคือ sweep แชท (ซึ่งไม่เจออะไร) — ไม่มีการดึง URL ทั้งหมดมาเทียบ
    expect(pool.query).toHaveBeenCalledTimes(1);
    expect(media.deleteObjects).not.toHaveBeenCalled();
  });

  it('ไฟล์แชทที่ไม่ถูกส่งภายใน 24 ชม. ถูกลบทั้งแถวและไฟล์', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-09-26T20:00:00Z'));
    const { processor, pool, media } = setup({ chatBatches: [['chat/a.jpg', 'chat/a_thumb.jpg']] });

    const out = await processor.process();

    expect(pool.query).toHaveBeenCalledWith(expect.stringContaining('DELETE FROM media_uploads'), [
      new Date('2026-09-25T20:00:00Z'),
      1000,
    ]);
    expect(media.deleteObjects).toHaveBeenCalledWith(['chat/a.jpg', 'chat/a_thumb.jpg']);
    expect(out.chatDeleted).toBe(2);
    vi.useRealTimers();
  });

  it('ไฟล์แชทค้างเกิน 1 ชุด วนลบจนหมด', async () => {
    const full = Array.from({ length: 1000 }, (_, i) => `chat/${i}.jpg`);
    const { processor, media } = setup({ chatBatches: [full, ['chat/last.jpg']] });

    const out = await processor.process();

    expect(media.deleteObjects).toHaveBeenCalledTimes(2);
    expect(out.chatDeleted).toBe(1001);
  });

  it('ลบเฉพาะไฟล์ที่ไม่มีประกาศหรือรูปโปรไฟล์ไหนอ้างถึง', async () => {
    const { processor, media } = setup({
      candidates: ['uploads/pet.jpg', 'uploads/avatar.jpg', 'uploads/orphan-1.jpg', 'uploads/orphan-2.png'],
      referencedUrls: [
        `${BUCKET_URL}uploads/pet.jpg`,
        `${BUCKET_URL}uploads/avatar.jpg`,
        'https://images.dog.ceo/breeds/mix/cherry.jpg', // รูปภายนอกจาก seed ต้องไม่ทำให้พัง
      ],
    });

    const out = await processor.process();

    expect(media.deleteObjects).toHaveBeenCalledWith(['uploads/orphan-1.jpg', 'uploads/orphan-2.png']);
    expect(out).toEqual({ deleted: 2, checked: 4, chatDeleted: 0 });
  });

  it('ทุกไฟล์ถูกอ้างถึงอยู่ ไม่ลบอะไรเลย', async () => {
    const { processor, media } = setup({
      candidates: ['uploads/pet.jpg'],
      referencedUrls: [`${BUCKET_URL}uploads/pet.jpg`],
    });

    const out = await processor.process();

    expect(media.deleteObjects).toHaveBeenCalledWith([]);
    expect(out).toEqual({ deleted: 0, checked: 1, chatDeleted: 0 });
  });

  it('ตั้ง schedule ทุกคืนตี 3 เวลาไทยตอน worker เริ่ม', async () => {
    const { processor, queue } = setup();

    await processor.onApplicationBootstrap();

    expect(queue.upsertJobScheduler).toHaveBeenCalledWith(
      'media-cleanup-nightly',
      { pattern: '0 3 * * *', tz: 'Asia/Bangkok' },
      { name: 'cleanup-orphan-media' },
    );
  });
});
