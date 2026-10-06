import { IsUUID } from 'class-validator';

/** หาห้องแชทเดิมของประกาศนี้ระหว่างฉันกับอีกฝ่าย (ปุ่ม "ทักแชท" ไม่รู้ chatId) */
export class LookupChatQueryDto {
  @IsUUID()
  petId!: string;

  @IsUUID()
  otherUserId!: string;
}
