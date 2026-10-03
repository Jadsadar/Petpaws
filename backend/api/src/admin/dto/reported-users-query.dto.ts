import { IsInt, IsOptional, Min } from 'class-validator';
import { Type } from 'class-transformer';
import { PaginationQueryDto } from './pagination.dto.js';

export const DEFAULT_MIN_REPORTS = 10;

export class ReportedUsersQueryDto extends PaginationQueryDto {
  /** เกณฑ์ขั้นต่ำของจำนวนคนที่รายงาน (นับคนไม่ซ้ำ) — default 10 ตามเดิม */
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  minReports?: number;
}
