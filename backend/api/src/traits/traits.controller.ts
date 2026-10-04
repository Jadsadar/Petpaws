import { Controller, Get, Inject } from '@nestjs/common';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { CacheService } from '../cache/cache.service.js';

@Controller('traits')
export class TraitsController {
  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly cache: CacheService,
  ) {}

  // ให้ Flutter ดึงชุดแท็กจาก DB ได้โดยตรงในอนาคต (ROADMAP Phase 3.8)
  // ตอนนี้ Flutter ยัง hardcode ชุดเดียวกันไว้ที่ lib/utils/pet_tags.dart
  // สอง endpoint นี้ต้องให้ผลตรงกันเป๊ะ — ห้ามชุดใดชุดหนึ่งหลุดจากอีกชุด
  @Get()
  list() {
    return this.cache.getOrSet({ ns: 'traits', id: 'active' }, async () => {
      const result = await this.pool.query<{
        id: string;
        slug: string;
        label_th: string;
      }>(
        `SELECT id, slug, label_th FROM traits WHERE is_active ORDER BY sort_order`,
      );
      return result.rows.map((r) => ({ id: r.id, slug: r.slug, label: r.label_th }));
    });
  }
}
