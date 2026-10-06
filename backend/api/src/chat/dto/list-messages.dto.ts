import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';

/**
 * แบ่งหน้าแบบ cursor: ไม่ส่ง before = หน้าล่าสุด, ส่ง id ข้อความเก่าสุดที่มีอยู่
 * = ดึงหน้าก่อนหน้านั้น ได้น้อยกว่า limit = ไม่มีข้อความเก่ากว่านี้แล้ว
 */
export class ListMessagesQueryDto {
  @IsOptional()
  @IsUUID()
  before?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;

  /**
   * 'room' = แนบสถานะห้อง (เหมือน GET /chats/:id) มาด้วย หน้าแชทจะได้ไม่ต้องยิงแยก
   * ตอบเป็น { messages, room } แทน array — ต้องขอเองเท่านั้น แอปรุ่นเก่าที่ไม่ส่งยังได้ array เหมือนเดิม
   */
  @IsOptional()
  @IsIn(['room'])
  include?: 'room';
}
