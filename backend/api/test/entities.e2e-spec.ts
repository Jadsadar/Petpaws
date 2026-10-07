import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { DataSource } from 'typeorm';
import type { Pool } from 'pg';
import { AppModule } from './../src/app.module.js';
import { ENTITIES } from './../src/database/entities/index.js';
import { PG_POOL } from './../src/database/database.module.js';

// entity ต้องตรงกับตารางจริงที่ migration สร้าง (synchronize: false — TypeORM ไม่ได้สร้างตารางเอง
// ถ้าชื่อคอลัมน์/ชนิดผิด จะรู้ตอน query จริงเท่านั้น) — SELECT ทุกคอลัมน์ของทุก entity กับ DB จริง
describe('TypeORM entities ตรงกับ schema จริง (e2e)', () => {
  let app: INestApplication;
  let dataSource: DataSource;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleFixture.createNestApplication();
    await app.init();
    dataSource = app.get(DataSource);
  });

  afterAll(async () => {
    await app.close();
  });

  it.each(ENTITIES.map((e) => [e.name, e]))('%s: อ่านทุกคอลัมน์ได้', async (_name, entity) => {
    await expect(dataSource.getRepository(entity).find({ take: 1 })).resolves.toBeInstanceOf(Array);
  });

  it('ทุกคอลัมน์ในตารางจริงมีใน entity (ไม่มีคอลัมน์ตกหล่น)', async () => {
    const pool = app.get<Pool>(PG_POOL);
    for (const meta of dataSource.entityMetadatas) {
      const res = await pool.query<{ column_name: string }>(
        `SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1`,
        [meta.tableName],
      );
      const inEntity = new Set(meta.columns.map((c) => c.databaseName));
      expect(res.rows.map((r) => r.column_name).filter((c) => !inEntity.has(c))).toEqual([]);
    }
  });

  it('PG_POOL คือ pool เดียวกับของ TypeORM (ไม่มี pool ที่สองแย่ง connection)', () => {
    expect(app.get(PG_POOL)).toBe((dataSource.driver as unknown as { master: unknown }).master);
  });
});
