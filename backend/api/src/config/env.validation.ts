// ตรวจ .env ตอน boot — ถ้าขาดตัวแปรสำคัญ (เช่น JWT secret) ต้องพังทันที
// ไม่ใช่ปล่อยให้รันไปเรื่อย ๆ แล้วพังตอนมีคนล็อกอินคนแรก
import { plainToInstance } from 'class-transformer';
import {
  IsIn,
  IsNotEmpty,
  IsNumberString,
  IsOptional,
  IsString,
  validateSync,
} from 'class-validator';

class EnvVars {
  @IsString()
  @IsNotEmpty()
  DATABASE_URL!: string;

  @IsString()
  @IsNotEmpty()
  JWT_ACCESS_SECRET!: string;

  @IsString()
  @IsNotEmpty()
  JWT_REFRESH_SECRET!: string;

  @IsString()
  @IsNotEmpty()
  JWT_ACCESS_TTL!: string;

  @IsString()
  @IsNotEmpty()
  JWT_REFRESH_TTL!: string;

  @IsNumberString()
  API_PORT!: string;

  @IsString()
  CORS_ORIGIN!: string;

  @IsString()
  @IsNotEmpty()
  S3_ENDPOINT!: string;

  // ที่อยู่ S3 ที่แอปเข้าถึงได้ (ไม่ตั้ง = ใช้ S3_ENDPOINT) ใช้เมื่อ endpoint ภายในเป็นชื่อ container
  @IsOptional()
  @IsString()
  S3_PUBLIC_ENDPOINT?: string;

  @IsString()
  @IsNotEmpty()
  S3_REGION!: string;

  @IsString()
  @IsNotEmpty()
  S3_BUCKET!: string;

  @IsString()
  @IsNotEmpty()
  S3_ACCESS_KEY_ID!: string;

  @IsString()
  @IsNotEmpty()
  S3_SECRET_ACCESS_KEY!: string;

  @IsIn(['true', 'false'])
  S3_FORCE_PATH_STYLE!: string;

  @IsString()
  @IsNotEmpty()
  REDIS_URL!: string;

  // Redis ตัวแยกสำหรับ cache (ไม่ใช่ตัวเดียวกับคิว) — ว่างได้: ปิด cache อ่าน DB ตรง
  // worker ไม่ใช้ cache จึงไม่ต้องตั้ง (ดู cache/cache.module.ts)
  @IsOptional()
  @IsString()
  REDIS_CACHE_URL?: string;

  // ว่างได้ตอน dev — worker จะข้ามการส่ง push ไปเฉย ๆ (ดู notifications/fcm.service.ts)
  @IsOptional()
  @IsString()
  FCM_PROJECT_ID?: string;

  @IsOptional()
  @IsString()
  FCM_CLIENT_EMAIL?: string;

  @IsOptional()
  @IsString()
  FCM_PRIVATE_KEY?: string;

  // ---------- อีเมล (ยืนยันอีเมลตอนสมัคร) — ไม่ตั้ง MAIL_PROVIDER = ปิดระบบอีเมล ไม่บังคับยืนยัน ----------
  @IsOptional()
  @IsIn(['brevo', 'log'])
  MAIL_PROVIDER?: string;

  @IsOptional()
  @IsString()
  BREVO_API_KEY?: string;

  @IsOptional()
  @IsString()
  MAIL_FROM_EMAIL?: string;

  @IsOptional()
  @IsString()
  MAIL_FROM_NAME?: string;

  // ที่อยู่ของ API ที่ผู้ใช้เปิดได้จากอีเมล (ใช้ประกอบลิงก์ยืนยัน) เช่น http://43.211.6.248
  @IsOptional()
  @IsString()
  APP_PUBLIC_URL?: string;
}

export function validateEnv(config: Record<string, unknown>) {
  const validated = plainToInstance(EnvVars, config, {
    enableImplicitConversion: true,
  });
  const errors = validateSync(validated, { skipMissingProperties: false });

  if (errors.length > 0) {
    const details = errors
      .map((e) => `${e.property}: ${Object.values(e.constraints ?? {}).join(', ')}`)
      .join('\n  ');
    throw new Error(
      `ตั้งค่า .env ไม่ครบหรือไม่ถูกต้อง — แก้ก่อนถึงจะ start ได้:\n  ${details}`,
    );
  }

  return validated;
}
