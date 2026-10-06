import { IsString, MaxLength, MinLength } from 'class-validator';

/** อีเมลหรือชื่อผู้ใช้ก็ได้ (หน้าล็อกอินรู้แค่สิ่งที่ผู้ใช้พิมพ์) */
export class ResendVerificationDto {
  @IsString()
  @MinLength(3)
  @MaxLength(254)
  identifier!: string;
}
