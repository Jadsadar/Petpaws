import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Queue } from 'bullmq';
import type { Pool } from 'pg';
import type { MediaService } from './media.service.js';
import { MediaCleanupProcessor } from './media-cleanup.processor.js';

const BUCKET_URL = 'http://localhost:9000/petpaws-media/';

function setup({ candidates = [] as string[], referencedUrls = [] as string[] } = {}) {
  const pool = { query: vi.fn().mockResolvedValue({ rows: referencedUrls.map((url) => ({ url })) }) };
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

  it('ไม่มีไฟล์เก่าเลย ไม่ต้อง query DB และไม่ลบอะไร', async () => {
    const { processor, pool, media } = setup({ candidates: [] });

    const out = await processor.process();

    expect(out).toEqual({ deleted: 0 });
    expect(pool.query).not.toHaveBeenCalled();
    expect(media.deleteObjects).not.toHaveBeenCalled();
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
    expect(out).toEqual({ deleted: 2, checked: 4 });
  });

  it('ทุกไฟล์ถูกอ้างถึงอยู่ ไม่ลบอะไรเลย', async () => {
    const { processor, media } = setup({
      candidates: ['uploads/pet.jpg'],
      referencedUrls: [`${BUCKET_URL}uploads/pet.jpg`],
    });

    const out = await processor.process();

    expect(media.deleteObjects).toHaveBeenCalledWith([]);
    expect(out).toEqual({ deleted: 0, checked: 1 });
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
