import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { In, IsNull, type EntityManager, type Repository } from 'typeorm';
import { randomUUID } from 'node:crypto';
import { MediaUpload } from '../database/entities/index.js';
import { AppException } from '../common/app-exception.js';
import { MediaService } from '../media/media.service.js';
import type { CreateMediaUploadDto } from './dto/create-media-upload.dto.js';
import type { MessageMediaDto, MessageMediaType } from './dto/message-media.dto.js';

export const CHAT_MEDIA_PREFIX = 'chat/';

// แอปย่อรูปเหลือ ~1600px ก่อนอัป (ไม่กี่ร้อย KB) และบีบวิดีโอเหลือ 720p —
// เพดานพวกนี้มีไว้กันคนยิงไฟล์ดิบตรง ๆ ไม่ใช่ขนาดที่ใช้งานปกติ
const MAX_BYTES: Record<MessageMediaType, number> = {
  image: 8 * 1024 * 1024,
  video: 50 * 1024 * 1024,
};
const MAX_THUMBNAIL_BYTES = 1024 * 1024;
const THUMBNAIL_CONTENT_TYPE = 'image/jpeg';

const EXTENSIONS: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'video/mp4': 'mp4',
};

const DEFAULT_UPLOAD_TTL_SECONDS = 900;

/** สื่อที่ตรวจแล้วว่าเป็นของผู้ส่งจริงและอัปขึ้นไปครบแล้ว พร้อมบันทึกลง messages */
export interface ResolvedMedia {
  type: MessageMediaType;
  url: string;
  thumbnailUrl: string;
  width: number;
  height: number;
  durationMs: number | null;
  keys: [string, string];
}

/**
 * รูป/วิดีโอในแชท อัปแบบ presigned POST ตรงไป S3 ไม่ผ่าน API:
 *
 *   1. POST /chats/media-uploads  -> ออกใบอนุญาต 2 ใบ (ตัวจริง + thumbnail)
 *                                    บันทึกลง media_uploads ว่าใบนี้ออกให้ใคร
 *   2. แอปอัปไฟล์ตรงไป S3 เอง      -> S3 บังคับขนาด/ชนิดไฟล์ตาม policy
 *   3. POST /chats/:id/messages    -> ตรวจว่า key เป็นของผู้ส่ง ยังไม่ถูกใช้ และมีไฟล์จริง
 *                                    แล้ว claim ใน transaction เดียวกับ INSERT ข้อความ
 *
 * ใบที่ออกแล้วไม่ถูก claim ภายใน 24 ชม. ถูก MediaCleanupProcessor กวาดทิ้งพร้อมไฟล์
 */
@Injectable()
export class ChatMediaService {
  private readonly ttlSeconds: number;

  constructor(
    @InjectRepository(MediaUpload) private readonly uploads: Repository<MediaUpload>,
    private readonly media: MediaService,
    config: ConfigService,
  ) {
    this.ttlSeconds = Number(config.get<string>('S3_UPLOAD_URL_TTL')) || DEFAULT_UPLOAD_TTL_SECONDS;
  }

  async createUpload(userId: string, dto: CreateMediaUploadDto) {
    if (!dto.contentType.startsWith(`${dto.type}/`)) {
      throw new AppException('INVALID_FILE_TYPE', 'ชนิดไฟล์ไม่ตรงกับประเภทสื่อ');
    }

    // ตัวจริงกับ thumbnail ใช้ UUID เดียวกัน ดูใน bucket แล้วรู้ว่าเป็นคู่กัน
    const id = randomUUID();
    const key = `${CHAT_MEDIA_PREFIX}${id}.${EXTENSIONS[dto.contentType]}`;
    const thumbnailKey = `${CHAT_MEDIA_PREFIX}${id}_thumb.jpg`;
    const expiresAt = new Date(Date.now() + this.ttlSeconds * 1000);

    await this.uploads.insert([
      { userId, storageKey: key, contentType: dto.contentType, expiresAt },
      { userId, storageKey: thumbnailKey, contentType: THUMBNAIL_CONTENT_TYPE, expiresAt },
    ]);

    const [upload, thumbnailUpload] = await Promise.all([
      this.media.presignPost(key, dto.contentType, MAX_BYTES[dto.type], this.ttlSeconds),
      this.media.presignPost(thumbnailKey, THUMBNAIL_CONTENT_TYPE, MAX_THUMBNAIL_BYTES, this.ttlSeconds),
    ]);

    return {
      key,
      upload,
      thumbnailKey,
      thumbnailUpload,
      maxBytes: MAX_BYTES[dto.type],
      expiresAt,
    };
  }

  /**
   * ตรวจก่อนเปิด transaction (HEAD ไป S3 ช้ากว่า query ไม่ควรถือ lock ระหว่างรอ)
   * ส่วนการกันใช้ key ซ้ำทำใน claim() ซึ่งอยู่ใน transaction เดียวกับ INSERT ข้อความ
   */
  async resolve(userId: string, dto: MessageMediaDto): Promise<ResolvedMedia> {
    if (dto.key === dto.thumbnailKey) throw this.invalid();
    if (dto.type === 'video' && !dto.durationMs) {
      throw new AppException('INVALID_MEDIA', 'วิดีโอต้องระบุความยาว');
    }

    // เฉพาะไฟล์ของผู้ส่งที่ยังไม่ถูกใช้ — กันเอา key ของคนอื่น/ของเก่ามาส่งซ้ำ
    const rows = await this.uploads.find({
      select: { storageKey: true, contentType: true },
      where: { userId, storageKey: In([dto.key, dto.thumbnailKey]), claimedAt: IsNull() },
    });
    const contentTypes = new Map(rows.map((r) => [r.storageKey, r.contentType]));
    const mediaType = contentTypes.get(dto.key);
    const thumbnailType = contentTypes.get(dto.thumbnailKey);
    // ไม่บอกว่าผิดเพราะอะไร (ไม่ใช่ของเรา / ใช้ไปแล้ว / ไม่มีอยู่) — ไม่ให้ไล่เดา key คนอื่น
    if (!mediaType?.startsWith(`${dto.type}/`) || thumbnailType !== THUMBNAIL_CONTENT_TYPE) {
      throw this.invalid();
    }

    const [size, thumbnailSize] = await Promise.all([
      this.media.objectSize(dto.key),
      this.media.objectSize(dto.thumbnailKey),
    ]);
    if (!size || !thumbnailSize) {
      throw new AppException('MEDIA_NOT_UPLOADED', 'ไฟล์ยังอัปโหลดไม่เสร็จ กรุณาลองใหม่อีกครั้ง');
    }

    return {
      type: dto.type,
      url: this.media.urlForKey(dto.key),
      thumbnailUrl: this.media.urlForKey(dto.thumbnailKey),
      width: dto.width,
      height: dto.height,
      durationMs: dto.type === 'video' ? dto.durationMs! : null,
      keys: [dto.key, dto.thumbnailKey],
    };
  }

  /**
   * เรียกใน transaction เดียวกับ INSERT ข้อความ — ส่งข้อความเดียวกันซ้ำพร้อมกัน 2 request
   * ตัวที่สองจะ claim ไม่ได้ (rowCount < 2) แล้ว rollback ไม่เกิดข้อความซ้ำที่ชี้ไฟล์เดียวกัน
   */
  async claim(em: EntityManager, userId: string, keys: [string, string]) {
    const res = await em.update(
      MediaUpload,
      { userId, storageKey: In(keys), claimedAt: IsNull() },
      { claimedAt: () => 'now()' },
    );
    if (res.affected !== keys.length) throw this.invalid();
  }

  private invalid() {
    return new AppException('INVALID_MEDIA', 'ไฟล์แนบไม่ถูกต้องหรือถูกใช้ไปแล้ว');
  }
}
