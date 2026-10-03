import { Inject, Injectable } from '@nestjs/common';
import type { Pool, PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { ChatService } from '../chat/chat.service.js';
import { AppException } from '../common/app-exception.js';
import {
  genderDbToLabel,
  genderLabelToDb,
  statusDbToLabel,
  statusLabelToDb,
  weightDbToLabel,
  weightToDb,
  PET_SPECIES,
} from './pet-mappers.js';
import type { CreatePetDto } from './dto/create-pet.dto.js';
import type { UpdatePetDto } from './dto/update-pet.dto.js';

// SELECT ร่วมที่ใช้ประกอบ "dog" JSON ให้ตรงกับ Map<String,dynamic> ที่ frontend ใช้
// (ดู lib/data/demo_seed.dart เป็นตัวอย่างรูปทรงที่ต้อง match)
const PET_SELECT = `
  SELECT
    p.id, p.owner_id, u.display_name AS owner_name, u.avatar_url AS owner_avatar,
    p.name, p.species::text AS species, p.species_other, p.breed, p.location AS province, p.age_label, p.sex, p.weight_kg,
    p.description AS story, p.status, p.like_count,
    (SELECT pm.url FROM pet_media pm WHERE pm.pet_id = p.id ORDER BY pm.sort_order LIMIT 1) AS image_url,
    COALESCE(
      (SELECT array_agg(t.slug ORDER BY t.sort_order)
       FROM pet_traits pt JOIN traits t ON t.id = pt.trait_id WHERE pt.pet_id = p.id),
      '{}'
    ) AS tags
  FROM pets p
  JOIN users u ON u.id = p.owner_id
`;

interface PetRow {
  id: string;
  owner_id: string;
  owner_name: string;
  owner_avatar: string | null;
  name: string;
  species: string;
  species_other: string | null;
  breed: string | null;
  province: string;
  age_label: string | null;
  sex: string;
  weight_kg: string | null;
  story: string | null;
  status: string;
  like_count: number;
  image_url: string | null;
  tags: string[];
}

@Injectable()
export class PetsService {
  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly chatService: ChatService,
  ) {}

  /** นาฬิกา DB ก่อนเปลี่ยนสถานะ ใช้หาข้อความระบบที่ trigger เพิ่งใส่ให้ (ดู ChatService.broadcastSystemMessages) */
  private async dbNow(): Promise<Date> {
    const res = await this.pool.query<{ now: Date }>(`SELECT clock_timestamp() AS now`);
    return res.rows[0].now;
  }

  private toDog(row: PetRow) {
    return {
      id: row.id,
      ownerId: row.owner_id,
      ownerName: row.owner_name,
      ownerAvatar: row.owner_avatar ?? '',
      name: row.name,
      species: row.species,
      speciesOther: row.species_other ?? '',
      breed: row.breed ?? 'พันทาง',
      province: row.province,
      age: row.age_label ?? '-',
      gender: genderDbToLabel(row.sex),
      weight: weightDbToLabel(row.weight_kg),
      tags: row.tags,
      story: row.story ?? '',
      imageUrl: row.image_url ?? '',
      status: statusDbToLabel(row.status),
      engagementLikes: row.like_count,
    };
  }

  async create(ownerId: string, dto: CreatePetDto) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      const petRes = await client.query<{ id: string }>(
        `INSERT INTO pets (owner_id, name, species, species_other, breed, sex, location, age_label, weight_kg, description, status)
         VALUES ($1, $2, $3::pet_species, $4, $5, $6, $7, $8, $9, $10, 'available')
         RETURNING id`,
        [
          ownerId,
          dto.name.trim(),
          dto.species ?? 'dog',
          dto.species === 'other' ? dto.speciesOther?.trim() || null : null,
          dto.breed?.trim() || 'พันทาง',
          genderLabelToDb(dto.gender),
          dto.province,
          dto.age,
          weightToDb(dto.weight),
          dto.story?.trim() || null,
        ],
      );
      const petId = petRes.rows[0].id;

      if (dto.imageUrl) {
        await this.insertMedia(client, petId, dto.imageUrl);
      }
      if (dto.tags?.length) {
        await this.replaceTags(client, petId, dto.tags);
      }

      await client.query('COMMIT');
      return this.findOne(petId);
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async findOne(id: string) {
    const res = await this.pool.query<PetRow>(
      `${PET_SELECT} WHERE p.id = $1 AND p.deleted_at IS NULL`,
      [id],
    );
    if (res.rows.length === 0) throw AppException.notFound('ไม่พบประกาศนี้');
    return this.toDog(res.rows[0]);
  }

  // ใช้ทั้งหน้า "ประกาศของฉัน" และหน้าโปรไฟล์สาธารณะของผู้ใช้คนอื่น —
  // ประกาศหาบ้านเป็นข้อมูลสาธารณะอยู่แล้ว จึงไม่ต้องกรองต่างกันตามผู้ดู
  async findByOwner(ownerId: string) {
    const res = await this.pool.query<PetRow>(
      `${PET_SELECT} WHERE p.owner_id = $1 AND p.deleted_at IS NULL ORDER BY p.created_at DESC`,
      [ownerId],
    );
    return res.rows.map((r) => this.toDog(r));
  }

  private async assertOwner(id: string, ownerId: string) {
    const res = await this.pool.query<{ owner_id: string }>(
      `SELECT owner_id FROM pets WHERE id = $1 AND deleted_at IS NULL`,
      [id],
    );
    if (res.rows.length === 0) throw AppException.notFound('ไม่พบประกาศนี้');
    if (res.rows[0].owner_id !== ownerId) {
      throw AppException.forbidden('แก้ไขได้เฉพาะประกาศของตัวเองเท่านั้น');
    }
  }

  async update(id: string, ownerId: string, dto: UpdatePetDto) {
    await this.assertOwner(id, ownerId);
    const since = await this.dbNow();

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      const fields: string[] = [];
      const values: unknown[] = [];
      let i = 1;
      const set = (col: string, val: unknown) => {
        fields.push(`${col} = $${i++}`);
        values.push(val);
      };

      if (dto.name !== undefined) set('name', dto.name.trim());
      if (dto.breed !== undefined) set('breed', dto.breed.trim() || 'พันทาง');
      if (dto.species !== undefined) {
        set('species', dto.species);
        // species_other มีได้เฉพาะตอนเป็น 'other' (CHECK ใน DB) — เปลี่ยนชนิดแล้วต้องล้างทิ้งด้วย
        set('species_other', dto.species === 'other' ? dto.speciesOther?.trim() || null : null);
      } else if (dto.speciesOther !== undefined) {
        // แก้แค่ข้อความ "อื่น ๆ" โดยไม่ส่งชนิดมา — ใช้ได้เฉพาะสัตว์ที่เป็น other อยู่แล้ว
        fields.push(`species_other = CASE WHEN species::text = 'other' THEN $${i++} ELSE NULL END`);
        values.push(dto.speciesOther.trim() || null);
      }
      if (dto.province !== undefined) set('location', dto.province);
      if (dto.age !== undefined) set('age_label', dto.age);
      if (dto.gender !== undefined) set('sex', genderLabelToDb(dto.gender));
      if (dto.weight !== undefined) set('weight_kg', weightToDb(dto.weight));
      if (dto.story !== undefined) set('description', dto.story.trim() || null);

      if (dto.status !== undefined) {
        const dbStatus = statusLabelToDb(dto.status);
        set('status', dbStatus);
        // CHECK pets_adopted_at_consistent บังคับว่า adopted ต้องมี adopted_at
        // คู่กันเสมอ — ตั้งให้ครบในธุรกรรมเดียวกัน ไม่งั้น DB ปฏิเสธทันที
        fields.push(`adopted_at = ${dbStatus === 'adopted' ? 'now()' : 'NULL'}`);
      }

      if (fields.length > 0) {
        values.push(id);
        await client.query(`UPDATE pets SET ${fields.join(', ')} WHERE id = $${i}`, values);
      }

      if (dto.imageUrl !== undefined && dto.imageUrl !== '') {
        await client.query(`DELETE FROM pet_media WHERE pet_id = $1`, [id]);
        await this.insertMedia(client, id, dto.imageUrl);
      }
      if (dto.tags !== undefined) {
        await this.replaceTags(client, id, dto.tags);
      }

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    if (dto.status !== undefined) await this.chatService.broadcastSystemMessages(id, since);
    return this.findOne(id);
  }

  async remove(id: string, ownerId: string) {
    await this.assertOwner(id, ownerId);
    const since = await this.dbNow();
    // soft delete เท่านั้น — ตาราง likes/conversations ของคนอื่นที่อ้าง pet นี้
    // จะพังถ้าลบแถวจริง (เหตุผลเต็มใน backend/db/README.md กลุ่มที่ 2)
    await this.pool.query(
      `UPDATE pets SET deleted_at = now(), status = 'cancelled', adopted_at = NULL WHERE id = $1`,
      [id],
    );
    await this.chatService.broadcastSystemMessages(id, since);
    return { success: true };
  }

  async like(petId: string, userId: string) {
    await this.pool.query(
      `INSERT INTO likes (user_id, pet_id) VALUES ($1, $2)
       ON CONFLICT (user_id, pet_id) DO NOTHING`,
      [userId, petId],
    );
    return { success: true };
  }

  async unlike(petId: string, userId: string) {
    await this.pool.query(`DELETE FROM likes WHERE user_id = $1 AND pet_id = $2`, [
      userId,
      petId,
    ]);
    return { success: true };
  }

  async pass(petId: string, userId: string) {
    await this.pool.query(
      `INSERT INTO passes (user_id, pet_id) VALUES ($1, $2)
       ON CONFLICT (user_id, pet_id) DO NOTHING`,
      [userId, petId],
    );
    return { success: true };
  }

  async unpass(petId: string, userId: string) {
    await this.pool.query(`DELETE FROM passes WHERE user_id = $1 AND pet_id = $2`, [
      userId,
      petId,
    ]);
    return { success: true };
  }

  /** รายการที่เคยถูกใจ (favorites_screen.dart -> likedDogs) เรียงจากล่าสุด */
  async myLikes(userId: string) {
    const res = await this.pool.query<PetRow>(
      `${PET_SELECT}
       JOIN likes l ON l.pet_id = p.id
       WHERE l.user_id = $1 AND p.deleted_at IS NULL
       ORDER BY l.created_at DESC`,
      [userId],
    );
    return res.rows.map((r) => this.toDog(r));
  }

  /**
   * ฟีดสำหรับหน้า Discover — เรียก deck_feed() ที่ฝังกฎกรอง/จัดลำดับทั้งหมดไว้ใน DB แล้ว
   * (ห้ามปัดสัตว์ตัวเอง, ไม่มีตัวที่เคยปัด, ไม่เห็นคนที่บล็อกกัน, จัดลำดับใกล้→ไกล)
   */
  async deck(
    userId: string,
    opts: { cursor?: string; province?: string; species?: string; traitSlugs?: string[]; limit?: number },
  ) {
    let cursorRank: number | null = null;
    let cursorAt: string | null = null;
    let cursorId: string | null = null;
    if (opts.cursor) {
      try {
        const decoded = JSON.parse(Buffer.from(opts.cursor, 'base64url').toString('utf8'));
        cursorRank = decoded.r;
        cursorAt = decoded.at;
        cursorId = decoded.id;
      } catch {
        throw new AppException('INVALID_CURSOR', 'cursor ไม่ถูกต้อง');
      }
    }

    if (opts.species && !(PET_SPECIES as readonly string[]).includes(opts.species)) {
      throw new AppException('INVALID_SPECIES', 'ชนิดสัตว์ไม่ถูกต้อง');
    }

    let traitIds: string[] | null = null;
    if (opts.traitSlugs?.length) {
      const res = await this.pool.query<{ id: string }>(
        `SELECT id FROM traits WHERE slug = ANY($1::text[])`,
        [opts.traitSlugs],
      );
      traitIds = res.rows.map((r) => r.id);
    }

    const result = await this.pool.query<{
      id: string;
      owner_id: string;
      name: string;
      breed: string | null;
      age_months: number | null;
      sex: string;
      size: string | null;
      location: string;
      like_count: number;
      created_at: Date;
      media_url: string | null;
      owner_name: string;
      owner_avatar: string | null;
      proximity_rank: number;
    }>(
      `SELECT * FROM deck_feed($1, $2, $3, $4, $5, $6, $8::pet_species, $7)`,
      [
        userId,
        opts.limit ?? 20,
        cursorRank,
        cursorAt,
        cursorId,
        opts.province ?? null,
        traitIds,
        opts.species ?? null,
      ],
    );

    // deck_feed ไม่มี age_label/story/tags/status ในผลลัพธ์ (ออกแบบมาให้เบาที่สุด
    // สำหรับการ์ดในเด็ค ตาม SKILL.md: "การ์ดในเด็คไม่ต้องได้ description เต็ม ๆ")
    // ต้อง query เพิ่มเพื่อประกอบ "dog" shape ให้ครบตามที่ SwipeableCard ต้องการแสดง
    const ids = result.rows.map((r) => r.id);
    let details = new Map<string, PetRow>();
    if (ids.length > 0) {
      const detailRes = await this.pool.query<PetRow>(
        `${PET_SELECT} WHERE p.id = ANY($1::uuid[])`,
        [ids],
      );
      details = new Map(detailRes.rows.map((r) => [r.id, r]));
    }

    const dogs = result.rows.map((r) => this.toDog(details.get(r.id)!));

    const last = result.rows.at(-1);
    const nextCursor = last
      ? Buffer.from(
          JSON.stringify({ r: last.proximity_rank, at: last.created_at, id: last.id }),
        ).toString('base64url')
      : null;

    return { dogs, nextCursor, hasMore: dogs.length === (opts.limit ?? 20) };
  }

  private async insertMedia(client: PoolClient, petId: string, url: string) {
    await client.query(
      `INSERT INTO pet_media (pet_id, storage_key, url, sort_order) VALUES ($1, $2, $3, 0)`,
      [petId, this.storageKeyFromUrl(url), url],
    );
  }

  // เก็บ path หลัง bucket ไว้เป็น storage_key แบบพอใช้ได้ (ไม่ใช่ที่มาของความจริง
  // เพราะรูปตอนนี้อัปผ่าน media module ที่คืนแค่ URL เต็ม ไม่ได้ส่ง key แยกมาด้วย)
  private storageKeyFromUrl(url: string): string {
    try {
      return new URL(url).pathname.replace(/^\//, '');
    } catch {
      return url;
    }
  }

  private async replaceTags(client: PoolClient, petId: string, slugs: string[]) {
    await client.query(`DELETE FROM pet_traits WHERE pet_id = $1`, [petId]);
    if (slugs.length === 0) return;
    await client.query(
      `INSERT INTO pet_traits (pet_id, trait_id)
       SELECT $1, id FROM traits WHERE slug = ANY($2::text[])`,
      [petId, slugs],
    );
  }
}
