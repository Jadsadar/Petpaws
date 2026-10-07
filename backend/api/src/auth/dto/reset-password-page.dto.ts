import { IsString, MaxLength, MinLength } from 'class-validator';

/** ?token=... ที่ลิงก์ในอีเมลพามา (เปิดในเบราว์เซอร์) */
export class ResetPasswordQueryDto {
  @IsString()
  @MinLength(20)
  @MaxLength(200)
  token!: string;
}

/** ฟอร์มบนหน้าเว็บตั้งรหัสผ่านใหม่ (application/x-www-form-urlencoded) */
export class ResetPasswordFormDto {
  @IsString()
  @MinLength(20)
  @MaxLength(200)
  token!: string;

  // เพดาน 128: argon2 กินเวลาตามความยาวรหัสผ่าน ไม่ให้ส่งก้อนใหญ่มาถ่วงเซิร์ฟเวอร์
  @IsString()
  @MaxLength(128)
  newPassword!: string;

  @IsString()
  @MaxLength(128)
  confirmPassword!: string;
}
