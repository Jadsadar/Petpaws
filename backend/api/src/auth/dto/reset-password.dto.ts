import { IsString, MaxLength, MinLength } from 'class-validator';

export class ResetPasswordDto {
  @IsString()
  @MinLength(1)
  token!: string;

  // เพดาน 128: argon2 กินเวลาตามความยาวรหัสผ่าน ไม่ให้ส่งก้อนใหญ่มาถ่วงเซิร์ฟเวอร์
  @IsString()
  @MinLength(8)
  @MaxLength(128)
  newPassword!: string;
}
