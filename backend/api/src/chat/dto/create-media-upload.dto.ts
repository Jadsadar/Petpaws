import { IsIn } from 'class-validator';
import { MESSAGE_MEDIA_TYPES, type MessageMediaType } from './message-media.dto.js';

export const CHAT_MEDIA_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'video/mp4'] as const;

export class CreateMediaUploadDto {
  @IsIn(MESSAGE_MEDIA_TYPES)
  type!: MessageMediaType;

  // คู่กับ type ต้องตรงกัน (image/* กับ image, video/* กับ video) — ตรวจใน service
  @IsIn(CHAT_MEDIA_CONTENT_TYPES)
  contentType!: (typeof CHAT_MEDIA_CONTENT_TYPES)[number];
}
