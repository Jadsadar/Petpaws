import { Controller, Get } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import type { Repository } from 'typeorm';
import { CacheService } from '../cache/cache.service.js';
import { Trait } from '../database/entities/index.js';

@Controller('traits')
export class TraitsController {
  constructor(
    @InjectRepository(Trait) private readonly traits: Repository<Trait>,
    private readonly cache: CacheService,
  ) {}

  // ให้ Flutter ดึงชุดแท็กจาก DB ได้โดยตรงในอนาคต (ROADMAP Phase 3.8)
  // ตอนนี้ Flutter ยัง hardcode ชุดเดียวกันไว้ที่ lib/utils/pet_tags.dart
  // สอง endpoint นี้ต้องให้ผลตรงกันเป๊ะ — ห้ามชุดใดชุดหนึ่งหลุดจากอีกชุด
  @Get()
  list() {
    return this.cache.getOrSet({ ns: 'traits', id: 'active' }, async () => {
      const rows = await this.traits.find({
        select: { id: true, slug: true, labelTh: true },
        where: { isActive: true },
        order: { sortOrder: 'ASC' },
      });
      return rows.map((r) => ({ id: r.id, slug: r.slug, label: r.labelTh }));
    });
  }
}
