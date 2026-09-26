import { ConfigModule } from '@nestjs/config';
import { validateEnv } from './env.validation.js';

// ใช้ร่วมกันทั้ง API (main.ts) และ worker (worker.ts) — อ่าน .env ไฟล์เดียวกัน
// รันจาก backend/api เสมอ .env จริงอยู่ที่ backend/.env (ไฟล์เดียวกับที่ docker-compose ใช้)
export const AppConfigModule = ConfigModule.forRoot({
  isGlobal: true,
  envFilePath: ['../.env', '.env'],
  validate: validateEnv,
});
