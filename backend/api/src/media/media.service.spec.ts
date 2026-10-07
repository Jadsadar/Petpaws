import { describe, expect, it } from 'vitest';
import type { ConfigService } from '@nestjs/config';
import { MediaService } from './media.service.js';

// keyFromUrl ผิด = cleanup job ลบรูปที่ยังใช้งานอยู่ จึงต้องมี test กันไว้
const env: Record<string, string> = {
  S3_BUCKET: 'petpaws-media',
  S3_ENDPOINT: 'http://localhost:9000',
  S3_REGION: 'ap-southeast-1',
  S3_ACCESS_KEY_ID: 'test',
  S3_SECRET_ACCESS_KEY: 'test',
  S3_FORCE_PATH_STYLE: 'true',
};
const config = { getOrThrow: (k: string) => env[k], get: (k: string) => env[k] } as unknown as ConfigService;
const media = new MediaService(config);

describe('MediaService public endpoint', () => {
  const split = (extra: Record<string, string>) => {
    const e: Record<string, string> = { ...env, S3_ENDPOINT: 'http://minio:9000', ...extra };
    const cfg = { getOrThrow: (k: string) => e[k], get: (k: string) => e[k] } as unknown as ConfigService;
    return new MediaService(cfg);
  };

  it('ตั้ง S3_PUBLIC_ENDPOINT แล้ว URL รูปที่ให้แอปใช้ชี้ที่อยู่สาธารณะ ไม่ใช่ชื่อ container', () => {
    const m = split({ S3_PUBLIC_ENDPOINT: 'http://203.0.113.9/' });
    expect(m.urlForKey('uploads/a.jpg')).toBe('http://203.0.113.9/petpaws-media/uploads/a.jpg');
  });

  it('ไม่ตั้ง S3_PUBLIC_ENDPOINT ใช้ S3_ENDPOINT ตามเดิม', () => {
    expect(split({}).urlForKey('uploads/a.jpg')).toBe('http://minio:9000/petpaws-media/uploads/a.jpg');
  });

  it('presigned POST ส่ง url ที่อยู่สาธารณะให้แอป (ไม่ใช่ minio:9000)', async () => {
    const m = split({ S3_PUBLIC_ENDPOINT: 'http://203.0.113.9' });
    const post = await m.presignPost('chat/x.jpg', 'image/jpeg', 1000, 60);
    expect(post.url).toBe('http://203.0.113.9/petpaws-media');
  });
});

describe('MediaService.keyFromUrl', () => {
  it('ดึง key ออกจาก URL ของ bucket เรา', () => {
    expect(media.keyFromUrl('http://localhost:9000/petpaws-media/uploads/a.jpg')).toBe('uploads/a.jpg');
  });

  it('host ต่างกันแต่ bucket เดียวกัน ยังได้ key เดิม (ย้าย endpoint ตอน production)', () => {
    expect(media.keyFromUrl('https://cdn.example.com/petpaws-media/uploads/a.jpg')).toBe('uploads/a.jpg');
  });

  it.each([
    ['https://images.dog.ceo/breeds/mix/cherry.jpg'],
    ['http://localhost:9000/other-bucket/uploads/a.jpg'],
    ['ไม่ใช่ url'],
    [''],
  ])('%j ไม่ใช่ไฟล์ใน bucket เรา ได้ null', (url) => {
    expect(media.keyFromUrl(url)).toBeNull();
  });
});

describe('MediaService.createImageUpload (รูปประกาศ/โปรไฟล์อัปตรงไป storage)', () => {
  it('ออกใบอนุญาตใต้ uploads/ พร้อม URL สาธารณะที่ใช้บันทึกลงประกาศ/โปรไฟล์ได้ทันที', async () => {
    const out = await media.createImageUpload('image/png');

    expect(out.key).toMatch(/^uploads\/[0-9a-f-]{36}\.png$/);
    expect(out.url).toBe(`http://localhost:9000/petpaws-media/${out.key}`);
    // policy ผูกชนิดไฟล์กับ key ไว้ — แอปเปลี่ยนเองไม่ได้
    expect(out.upload.fields).toMatchObject({ key: out.key, 'Content-Type': 'image/png' });
    expect(out.maxBytes).toBe(8 * 1024 * 1024);
  });

  it('ชนิดไฟล์อื่นนอกจาก JPEG/PNG/WEBP ถูกปฏิเสธ', async () => {
    await expect(media.createImageUpload('image/gif')).rejects.toMatchObject({ code: 'INVALID_FILE_TYPE' });
  });
});
