import { IsIn, IsInt, IsOptional, IsString, Matches, Max, Min } from 'class-validator';

export const MESSAGE_MEDIA_TYPES = ['image', 'video'] as const;
export type MessageMediaType = (typeof MESSAGE_MEDIA_TYPES)[number];

// key ที่ได้จาก POST /chats/media-uploads เท่านั้น — กันส่ง key ของไฟล์ส่วนอื่น
// (รูปประกาศ, avatar) มาแปะในแชท service ยังตรวจเจ้าของไฟล์ซ้ำกับ media_uploads อีกชั้น
const CHAT_KEY = /^chat\/[0-9a-f-]{36}(_thumb)?\.(jpg|png|webp|mp4)$/;

export class MessageMediaDto {
  @IsIn(MESSAGE_MEDIA_TYPES)
  type!: MessageMediaType;

  @IsString()
  @Matches(CHAT_KEY)
  key!: string;

  @IsString()
  @Matches(CHAT_KEY)
  thumbnailKey!: string;

  @IsInt()
  @Min(1)
  @Max(20000)
  width!: number;

  @IsInt()
  @Min(1)
  @Max(20000)
  height!: number;

  // บังคับเฉพาะวิดีโอ (ตรวจใน service — DB มี CHECK กันไว้อีกชั้น)
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(10 * 60 * 1000)
  durationMs?: number;
}
