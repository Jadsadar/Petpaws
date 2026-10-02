import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';

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
}
