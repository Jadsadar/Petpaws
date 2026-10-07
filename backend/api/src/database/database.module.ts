import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import type { Pool } from 'pg';
import { ENTITIES } from './entities/index.js';

export const PG_POOL = Symbol('PG_POOL');

/**
 * TypeORM เป็นเจ้าของการเชื่อมต่อ DB — กติกาของโปรเจกต์นี้:
 *
 * - synchronize: false เสมอ: ตาราง/constraint/trigger/ฟังก์ชันมาจาก backend/db/migrations (SQL)
 *   เท่านั้น entity แค่ "อธิบาย" ตารางที่มีอยู่ ถ้าให้ TypeORM สร้าง/แก้ตารางเองจะลบของที่ entity
 *   ประกาศไม่ได้ทิ้ง (partial index, composite FK, deferrable trigger, deck_feed ฯลฯ)
 * - คอลัมน์ที่ trigger/DB ดูแล (like_count, unread_count, last_message_*, created_at, updated_at)
 *   ประกาศ insert/update: false ใน entity — save() จะไม่เขียนค่าเก่าทับค่าที่ trigger อัปเดต
 * - โค้ดธุรกิจใช้ repository / QueryBuilder / dataSource.query ของ TypeORM — query ที่ใช้
 *   ความสามารถเฉพาะของ Postgres (deck_feed, CTE รายงาน, unnest) เขียนเป็น SQL ผ่าน dataSource.query
 * - PG_POOL (pool ของ pg ตัวเดียวกับของ TypeORM ไม่ใช่ pool แยก) เหลือไว้ให้งานระบบที่เป็น SQL ล้วน:
 *   health check, pg_stat_statements (metrics), งานกวาดไฟล์ค้าง และ push worker — และให้เทสต์ e2e ใช้
 *
 * Global ให้ทุก module inject PG_POOL / DataSource ได้โดยไม่ต้อง import ซ้ำ
 */
@Global()
@Module({
  imports: [
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres' as const,
        url: config.getOrThrow<string>('DATABASE_URL'),
        entities: ENTITIES,
        synchronize: false,
        migrationsRun: false,
        // pool เล็กพอสำหรับเครื่องเดียว — API หลายตัว × 10 ต้องไม่เกิน max_connections ของ Postgres
        extra: { max: 10 },
      }),
    }),
  ],
  providers: [
    {
      provide: PG_POOL,
      inject: [DataSource],
      // pool ของ pg ที่ TypeORM สร้างไว้ (driver.master) — SQL ดิบกับ repository ใช้ connection ชุดเดียวกัน
      useFactory: (dataSource: DataSource): Pool => (dataSource.driver as unknown as { master: Pool }).master,
    },
  ],
  exports: [PG_POOL, TypeOrmModule],
})
export class DatabaseModule {}
