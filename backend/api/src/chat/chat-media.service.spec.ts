import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { ConfigService } from '@nestjs/config';
import type { EntityManager, Repository } from 'typeorm';
import type { MediaUpload } from '../database/entities/index.js';
import type { MediaService } from '../media/media.service.js';
import { ChatMediaService } from './chat-media.service.js';
import type { MessageMediaDto } from './dto/message-media.dto.js';

const USER = '00000000-0000-0000-0000-000000000001';
const ID = '11111111-1111-1111-1111-111111111111';
const KEY = `chat/${ID}.jpg`;
const THUMB = `chat/${ID}_thumb.jpg`;

function setup({
  uploads = [] as { storage_key: string; content_type: string }[],
  sizes = {} as Record<string, number | null>,
} = {}) {
  // repository ปลอม: find คืนแถวในรูปของ entity
  const repo = {
    insert: vi.fn().mockResolvedValue({}),
    find: vi.fn().mockResolvedValue(uploads.map((u) => ({ storageKey: u.storage_key, contentType: u.content_type }))),
  };
  const media = {
    presignPost: vi.fn((key: string) => Promise.resolve({ url: 'http://s3/bucket', fields: { key } })),
    objectSize: vi.fn((key: string) => Promise.resolve(key in sizes ? sizes[key] : 100)),
    urlForKey: vi.fn((key: string) => `http://s3/bucket/${key}`),
  };
  const config = { get: () => undefined } as unknown as ConfigService;
  const service = new ChatMediaService(repo as unknown as Repository<MediaUpload>, media as unknown as MediaService, config);
  return { service, repo, media };
}

const imageDto = (over: Partial<MessageMediaDto> = {}): MessageMediaDto => ({
  type: 'image',
  key: KEY,
  thumbnailKey: THUMB,
  width: 1600,
  height: 1200,
  ...over,
});

const ownedImage = [
  { storage_key: KEY, content_type: 'image/jpeg' },
  { storage_key: THUMB, content_type: 'image/jpeg' },
];

describe('ChatMediaService.createUpload', () => {
  beforeEach(() => vi.clearAllMocks());

  it('ออกใบอนุญาต 2 ใบ (ตัวจริง + thumbnail) และบันทึกทั้งคู่ลง media_uploads', async () => {
    const { service, repo, media } = setup();

    const out = await service.createUpload(USER, { type: 'video', contentType: 'video/mp4' });

    expect(out.key).toMatch(/^chat\/[0-9a-f-]{36}\.mp4$/);
    expect(out.thumbnailKey).toBe(out.key.replace('.mp4', '_thumb.jpg'));
    expect(repo.insert).toHaveBeenCalledWith([
      { userId: USER, storageKey: out.key, contentType: 'video/mp4', expiresAt: expect.any(Date) },
      { userId: USER, storageKey: out.thumbnailKey, contentType: 'image/jpeg', expiresAt: expect.any(Date) },
    ]);
    // วิดีโอได้เพดาน 50MB thumbnail ได้ 1MB และต้องเป็น jpeg เสมอ
    expect(media.presignPost).toHaveBeenCalledWith(out.key, 'video/mp4', 50 * 1024 * 1024, 900);
    expect(media.presignPost).toHaveBeenCalledWith(out.thumbnailKey, 'image/jpeg', 1024 * 1024, 900);
  });

  it('ชนิดไฟล์ไม่ตรงกับประเภท (ขอ video แต่ส่ง image/jpeg) ถูกปฏิเสธ ไม่บันทึกอะไร', async () => {
    const { service, repo } = setup();

    await expect(service.createUpload(USER, { type: 'video', contentType: 'image/jpeg' })).rejects.toMatchObject({
      code: 'INVALID_FILE_TYPE',
    });
    expect(repo.insert).not.toHaveBeenCalled();
  });
});

describe('ChatMediaService.resolve', () => {
  beforeEach(() => vi.clearAllMocks());

  it('ไฟล์ของผู้ส่ง อัปครบแล้ว ได้ URL เต็มกลับมา', async () => {
    const { service } = setup({ uploads: ownedImage });

    const out = await service.resolve(USER, imageDto());

    expect(out).toEqual({
      type: 'image',
      url: `http://s3/bucket/${KEY}`,
      thumbnailUrl: `http://s3/bucket/${THUMB}`,
      width: 1600,
      height: 1200,
      durationMs: null,
      keys: [KEY, THUMB],
    });
  });

  it('ค้นเฉพาะไฟล์ของผู้ส่งที่ยังไม่ถูกใช้ (กันเอา key ของคนอื่น/ของเก่ามาส่งซ้ำ)', async () => {
    const { service, repo } = setup({ uploads: ownedImage });

    await service.resolve(USER, imageDto());

    const { where } = repo.find.mock.calls[0][0];
    expect(where.userId).toBe(USER);
    expect(where.storageKey.value).toEqual([KEY, THUMB]); // In([...])
    expect(where.claimedAt.type).toBe('isNull');
  });

  it.each([
    ['ไม่ใช่ไฟล์ของเรา / ถูกใช้ไปแล้ว (DB ไม่คืนแถว)', [] as typeof ownedImage],
    ['มีแค่ตัวจริง ไม่มี thumbnail', [ownedImage[0]]],
    ['ส่งเป็น image แต่ไฟล์ที่ขอไว้เป็นวิดีโอ', [{ storage_key: KEY, content_type: 'video/mp4' }, ownedImage[1]]],
  ])('%s -> INVALID_MEDIA', async (_name, uploads) => {
    const { service, media } = setup({ uploads });

    await expect(service.resolve(USER, imageDto())).rejects.toMatchObject({ code: 'INVALID_MEDIA' });
    expect(media.objectSize).not.toHaveBeenCalled();
  });

  it('ใช้ key เดียวกันเป็นทั้งตัวจริงและ thumbnail ไม่ได้', async () => {
    const { service } = setup({ uploads: ownedImage });

    await expect(service.resolve(USER, imageDto({ thumbnailKey: KEY }))).rejects.toMatchObject({
      code: 'INVALID_MEDIA',
    });
  });

  it('วิดีโอไม่มีความยาว ถูกปฏิเสธ', async () => {
    const { service } = setup();

    await expect(
      service.resolve(USER, imageDto({ type: 'video', key: `chat/${ID}.mp4` })),
    ).rejects.toMatchObject({ code: 'INVALID_MEDIA' });
  });

  it('ขอใบอนุญาตแล้วแต่ยังไม่ได้อัปไฟล์ขึ้นจริง -> MEDIA_NOT_UPLOADED', async () => {
    const { service } = setup({ uploads: ownedImage, sizes: { [THUMB]: null } });

    await expect(service.resolve(USER, imageDto())).rejects.toMatchObject({ code: 'MEDIA_NOT_UPLOADED' });
  });
});

describe('ChatMediaService.claim', () => {
  it('claim ได้ครบ 2 ไฟล์ ผ่าน', async () => {
    const { service } = setup();
    const em = { update: vi.fn().mockResolvedValue({ affected: 2 }) };

    await expect(service.claim(em as unknown as EntityManager, USER, [KEY, THUMB])).resolves.toBeUndefined();
  });

  it('อีก request claim ตัดหน้าไปแล้ว (ได้ไม่ครบ) โยน error ให้ transaction rollback', async () => {
    const { service } = setup();
    const em = { update: vi.fn().mockResolvedValue({ affected: 1 }) };

    await expect(service.claim(em as unknown as EntityManager, USER, [KEY, THUMB])).rejects.toMatchObject({
      code: 'INVALID_MEDIA',
    });
  });
});
