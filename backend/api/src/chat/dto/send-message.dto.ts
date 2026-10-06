import { Type } from 'class-transformer';
import { IsOptional, IsString, IsUUID, MaxLength, ValidateNested } from 'class-validator';
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

  /**
   * id ที่แอปสร้างเองตอนกดส่ง ใช้ค่าเดิมทุกครั้งที่ลองส่งซ้ำ — ข้อความนี้เคยบันทึกแล้ว
   * จะได้ข้อความเดิมกลับไปแทนการบันทึกซ้ำ (ไม่ส่ง = แอปรุ่นก่อน ทำงานแบบเดิม)
   */
  @IsOptional()
  @IsUUID()
  clientId?: string;
}
