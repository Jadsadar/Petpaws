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
