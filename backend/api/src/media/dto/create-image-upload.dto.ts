import { IsIn } from 'class-validator';

export const IMAGE_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;

/** ขอใบอนุญาตอัปรูปประกาศ/รูปโปรไฟล์ตรงไป storage (แทน POST /media/upload ที่ไฟล์วิ่งผ่าน API) */
export class CreateImageUploadDto {
  @IsIn(IMAGE_CONTENT_TYPES)
  contentType!: (typeof IMAGE_CONTENT_TYPES)[number];
}
