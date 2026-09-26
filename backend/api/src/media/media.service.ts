import { Injectable, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  CreateBucketCommand,
  DeleteObjectsCommand,
  HeadBucketCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  PutBucketPolicyCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { randomUUID } from 'node:crypto';
import { AppException } from '../common/app-exception.js';

const MAX_UPLOAD_BYTES = 8 * 1024 * 1024; // 8MB — สอดคล้องกับที่ storage.rules เดิมเคยกำหนดไว้
const ALLOWED_CONTENT_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const UPLOAD_PREFIX = 'uploads/';
const S3_DELETE_BATCH = 1000; // เพดานของ DeleteObjects ต่อ 1 request

/**
 * อัปโหลดผ่าน NestJS ตรง ๆ (multipart -> S3 PutObject) แทนที่จะออก presigned URL
 * ให้ client อัปตรงไป S3 เอง (ตามที่ ROADMAP.md Phase 3.1 ตั้งใจไว้ตอนแรก)
 *
 * เหตุผลที่เลือกทางนี้ก่อน: ลดความซับซ้อนของการ wiring ฝั่ง Flutter (ไม่ต้องแยก
 * เรียก 2 ขั้นตอน "ขอ URL" แล้ว "PUT ไฟล์เอง") ให้ทันเวลาที่ทุกฟังก์ชันต้องใช้งานได้
 * ก่อน — แลกกับ throughput ที่ลดลงเพราะไฟล์วิ่งผ่าน API แทนที่จะตรงไป S3
 * ที่สเกลนี้ (โปรเจกต์เรียน) ไม่ใช่ปัญหา ย้ายไป presigned URL ทีหลังได้โดยไม่กระทบ
 * schema เพราะ media_uploads ยังไม่ได้ผูกกับวิธีอัปโหลดวิธีใดวิธีหนึ่งตายตัว
 */
@Injectable()
export class MediaService implements OnModuleInit {
  private readonly client: S3Client;
  private readonly bucket: string;
  private readonly publicEndpoint: string;

  constructor(private readonly config: ConfigService) {
    this.bucket = config.getOrThrow<string>('S3_BUCKET');
    this.publicEndpoint = config.getOrThrow<string>('S3_ENDPOINT');
    this.client = new S3Client({
      endpoint: this.publicEndpoint,
      region: config.getOrThrow<string>('S3_REGION'),
      credentials: {
        accessKeyId: config.getOrThrow<string>('S3_ACCESS_KEY_ID'),
        secretAccessKey: config.getOrThrow<string>('S3_SECRET_ACCESS_KEY'),
      },
      forcePathStyle: config.get<string>('S3_FORCE_PATH_STYLE') === 'true',
    });
  }

  // สร้าง bucket ให้อัตโนมัติตอน boot ถ้ายังไม่มี (dev เท่านั้น — production ควรสร้างไว้ล่วงหน้า)
  async onModuleInit() {
    try {
      await this.client.send(new HeadBucketCommand({ Bucket: this.bucket }));
    } catch {
      await this.client.send(new CreateBucketCommand({ Bucket: this.bucket }));
      // เปิดอ่านสาธารณะ (GetObject) เท่านั้น — เขียนยังต้องผ่าน API + auth เสมอ
      // ตรงกับ storage.rules เดิม: "allow read: if true; allow write: if auth"
      await this.client.send(
        new PutBucketPolicyCommand({
          Bucket: this.bucket,
          Policy: JSON.stringify({
            Version: '2012-10-17',
            Statement: [
              {
                Effect: 'Allow',
                Principal: '*',
                Action: ['s3:GetObject'],
                Resource: [`arn:aws:s3:::${this.bucket}/*`],
              },
            ],
          }),
        }),
      );
    }
  }

  async uploadImage(file: {
    buffer: Buffer;
    mimetype: string;
    size: number;
  }): Promise<{ url: string }> {
    if (!ALLOWED_CONTENT_TYPES.has(file.mimetype)) {
      throw new AppException('INVALID_FILE_TYPE', 'รองรับเฉพาะไฟล์ JPEG, PNG, WEBP');
    }
    if (file.size > MAX_UPLOAD_BYTES) {
      throw new AppException('FILE_TOO_LARGE', 'ไฟล์ต้องมีขนาดไม่เกิน 8MB');
    }

    const ext = file.mimetype.split('/')[1];
    const key = `${UPLOAD_PREFIX}${randomUUID()}.${ext}`;

    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: file.buffer,
        ContentType: file.mimetype,
      }),
    );

    return { url: `${this.publicEndpoint}/${this.bucket}/${key}` };
  }

  /** key ของไฟล์ในโฟลเดอร์อัปโหลดที่ถูกสร้าง/แก้ล่าสุดก่อน cutoff */
  async listUploadsOlderThan(cutoff: Date): Promise<string[]> {
    const keys: string[] = [];
    let token: string | undefined;
    do {
      const page = await this.client.send(
        new ListObjectsV2Command({ Bucket: this.bucket, Prefix: UPLOAD_PREFIX, ContinuationToken: token }),
      );
      for (const obj of page.Contents ?? []) {
        if (obj.Key && obj.LastModified && obj.LastModified < cutoff) keys.push(obj.Key);
      }
      token = page.IsTruncated ? page.NextContinuationToken : undefined;
    } while (token);
    return keys;
  }

  async deleteObjects(keys: string[]): Promise<void> {
    for (let i = 0; i < keys.length; i += S3_DELETE_BATCH) {
      const batch = keys.slice(i, i + S3_DELETE_BATCH);
      await this.client.send(
        new DeleteObjectsCommand({
          Bucket: this.bucket,
          Delete: { Objects: batch.map((Key) => ({ Key })), Quiet: true },
        }),
      );
    }
  }

  /**
   * แปลง URL ที่เก็บใน DB กลับเป็น key ใน bucket — เทียบแค่ path หลัง /{bucket}/
   * ไม่เทียบ host เพราะ S3_ENDPOINT อาจเปลี่ยนตอนย้ายไป production แต่ key เดิม
   * URL ภายนอก (รูป seed จาก dog.ceo ฯลฯ) ได้ null
   */
  keyFromUrl(url: string): string | null {
    try {
      const path = decodeURIComponent(new URL(url).pathname);
      const marker = `/${this.bucket}/`;
      return path.startsWith(marker) ? path.slice(marker.length) : null;
    } catch {
      return null;
    }
  }
}
