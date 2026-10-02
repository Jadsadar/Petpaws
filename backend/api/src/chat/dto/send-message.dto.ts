import { Type } from 'class-transformer';
import { IsOptional, IsString, MaxLength, ValidateNested } from 'class-validator';
import { MessageMediaDto } from './message-media.dto.js';

/** ต้องมี text หรือ media อย่างน้อยหนึ่งอย่าง (ตรวจใน ChatService) — รูปไม่ต้องมีคำบรรยายก็ได้ */
export class SendMessageDto {
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  text?: string;

  @IsOptional()
  @ValidateNested()
  @Type(() => MessageMediaDto)
  media?: MessageMediaDto;
}
