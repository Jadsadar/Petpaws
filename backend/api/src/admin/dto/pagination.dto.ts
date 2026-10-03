import { IsInt, IsOptional, Max, Min } from 'class-validator';
import { Type } from 'class-transformer';

export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 50;

/**
 * query ?page=1&pageSize=20 ของทุก endpoint ที่คืนเป็นรายการในหน้าแอดมิน
 * page เริ่มที่ 1 (ไม่ใช่ 0) เพื่อให้ตรงกับที่แอดมินเห็นบนหน้าจอ "หน้า 1 / 5"
 */
export class PaginationQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_PAGE_SIZE)
  pageSize?: number;
}

export interface Page<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
}

export function resolvePaging(query: PaginationQueryDto): { page: number; pageSize: number; offset: number } {
  const page = query.page ?? 1;
  const pageSize = query.pageSize ?? DEFAULT_PAGE_SIZE;
  return { page, pageSize, offset: (page - 1) * pageSize };
}

/** ห่อผลลัพธ์ให้เป็นรูปแบบเดียวกันทุก endpoint (total = จำนวนทั้งหมดก่อนแบ่งหน้า) */
export function toPage<T>(items: T[], total: number, page: number, pageSize: number): Page<T> {
  return { items, total, page, pageSize };
}
