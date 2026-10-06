import { Type } from 'class-transformer';
import { IsOptional, IsString, IsUUID, MaxLength, ValidateNested } from 'class-validator';
import { MessageMediaDto } from './message-media.dto.js';

// SKILL.md: "ห้องแชทเกิดตอนผู้ใช้กดส่งข้อความแรกเท่านั้น" — DB บังคับด้วย deferred
// constraint trigger (conversations_require_first_message) จึงไม่มี endpoint
// "สร้างห้องเปล่า" แยกต่างหาก ต้องส่งข้อความแรกมาพร้อมกันเสมอ
// ข้อความแรกเป็นรูป/วิดีโอได้ ต้องมี message หรือ media อย่างน้อยหนึ่งอย่าง
export class CreateChatDto {
  @IsUUID()
  petId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  message?: string;

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
