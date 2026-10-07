import { Injectable } from '@nestjs/common';
import { InjectDataSource, InjectRepository } from '@nestjs/typeorm';
import { DataSource, EntityManager, In, IsNull, type Repository } from 'typeorm';
import type { QueryDeepPartialEntity } from 'typeorm/query-builder/QueryPartialEntity.js';
import { ChatService } from '../chat/chat.service.js';
import { AppException } from '../common/app-exception.js';
import { CacheService } from '../cache/cache.service.js';
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
import { Like, Pass, Pet, PetMedia, PetTrait, Trait, User } from '../database/entities/index.js';

// คอลัมน์ที่ใช้ประกอบ "dog" JSON ให้ตรงกับ Map<String,dynamic> ที่ frontend ใช้
// (ดู lib/data/demo_seed.dart เป็นตัวอย่างรูปทรงที่ต้อง match) — ใช้กับ petQuery()
const PET_COLUMNS = [
  'p.id AS id',
  'p.owner_id AS owner_id',
  'u.display_name AS owner_name',
  'u.avatar_url AS owner_avatar',
  'p.name AS name',
  'p.species::text AS species',
  'p.species_other AS species_other',
  'p.breed AS breed',
  'p.location AS province',
  'p.age_label AS age_label',
  'p.sex AS sex',
  'p.weight_kg AS weight_kg',
  'p.description AS story',
  'p.status AS status',
  'p.like_count AS like_count',
];
const PET_IMAGE_SQL = '(SELECT pm.url FROM pet_media pm WHERE pm.pet_id = p.id ORDER BY pm.sort_order LIMIT 1)';
const PET_TAGS_SQL = `COALESCE(
  (SELECT array_agg(t.slug ORDER BY t.sort_order) FROM pet_traits pt JOIN traits t ON t.id = pt.trait_id WHERE pt.pet_id = p.id),
  '{}')`;

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
    @InjectDataSource() private readonly dataSource: DataSource,
    @InjectRepository(Pet) private readonly pets: Repository<Pet>,
    private readonly chatService: ChatService,
    private readonly cache: CacheService,
  ) {}

  /** นาฬิกา DB ก่อนเปลี่ยนสถานะ ใช้หาข้อความระบบที่ trigger เพิ่งใส่ให้ (ดู ChatService.broadcastSystemMessages) */
  private async dbNow(): Promise<Date> {
    const [row] = await this.dataSource.query<{ now: Date }[]>(`SELECT clock_timestamp() AS now`);
    return row.now;
  }

  /** ประกาศพร้อมชื่อ/รูปเจ้าของ รูปแรก และแท็ก — ต่อ where/order เองตามแต่ละหน้า */
  private petQuery() {
    return this.dataSource
      .createQueryBuilder(Pet, 'p')
      .innerJoin(User, 'u', 'u.id = p.owner_id')
      .select(PET_COLUMNS)
      .addSelect(PET_IMAGE_SQL, 'image_url')
      .addSelect(PET_TAGS_SQL, 'tags');
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
    const petId = await this.dataSource.transaction(async (em) => {
      const res = await em.insert(Pet, {
        ownerId,
        name: dto.name.trim(),
        species: (dto.species ?? 'dog') as Pet['species'],
        speciesOther: dto.species === 'other' ? dto.speciesOther?.trim() || null : null,
        breed: dto.breed?.trim() || 'พันทาง',
        sex: genderLabelToDb(dto.gender) as Pet['sex'],
        location: dto.province,
        ageLabel: dto.age,
        weightKg: weightToDb(dto.weight) as string | null,
        description: dto.story?.trim() || null,
        status: 'available',
      });
      const id = res.identifiers[0].id as string;

      if (dto.imageUrl) await this.insertMedia(em, id, dto.imageUrl);
      if (dto.tags?.length) await this.replaceTags(em, id, dto.tags);
      return id;
    });
    await this.cache.invalidate({ ns: 'petsByOwner', id: ownerId });
    return this.findOne(petId);
  }

  // ผลไม่ขึ้นกับผู้ดู (ไม่มี likedByMe ฯลฯ) จึง cache ร่วมกันทุกคนได้
  findOne(id: string) {
    return this.cache.getOrSet({ ns: 'pet', id }, async () => {
      const row = await this.petQuery()
        .where('p.id = :id AND p.deleted_at IS NULL', { id })
        .getRawOne<PetRow>();
      if (!row) throw AppException.notFound('ไม่พบประกาศนี้');
      return this.toDog(row);
    });
  }

  // ใช้ทั้งหน้า "ประกาศของฉัน" และหน้าโปรไฟล์สาธารณะของผู้ใช้คนอื่น —
  // ประกาศหาบ้านเป็นข้อมูลสาธารณะอยู่แล้ว จึงไม่ต้องกรองต่างกันตามผู้ดู
  // [cached] = false สำหรับหน้า "ประกาศของฉัน" ให้เจ้าของเห็น like_count ล่าสุดเสมอ
  findByOwner(ownerId: string, { cached = true } = {}) {
    const load = async () => {
      const rows = await this.petQuery()
        .where('p.owner_id = :ownerId AND p.deleted_at IS NULL', { ownerId })
        .orderBy('p.created_at', 'DESC')
        .getRawMany<PetRow>();
      return rows.map((r) => this.toDog(r));
    };
    return cached ? this.cache.getOrSet({ ns: 'petsByOwner', id: ownerId }, load) : load();
  }

  private async assertOwner(id: string, ownerId: string) {
    const pet = await this.pets.findOne({ select: { ownerId: true }, where: { id, deletedAt: IsNull() } });
    if (!pet) throw AppException.notFound('ไม่พบประกาศนี้');
    if (pet.ownerId !== ownerId) {
      throw AppException.forbidden('แก้ไขได้เฉพาะประกาศของตัวเองเท่านั้น');
    }
  }

  async update(id: string, ownerId: string, dto: UpdatePetDto) {
    await this.assertOwner(id, ownerId);
    const since = await this.dbNow();

    await this.dataSource.transaction(async (em) => {
      const patch: QueryDeepPartialEntity<Pet> = {};
      const params: Record<string, unknown> = {};

      if (dto.name !== undefined) patch.name = dto.name.trim();
      if (dto.breed !== undefined) patch.breed = dto.breed.trim() || 'พันทาง';
      if (dto.species !== undefined) {
        patch.species = dto.species as Pet['species'];
        // species_other มีได้เฉพาะตอนเป็น 'other' (CHECK ใน DB) — เปลี่ยนชนิดแล้วต้องล้างทิ้งด้วย
        patch.speciesOther = dto.species === 'other' ? dto.speciesOther?.trim() || null : null;
      } else if (dto.speciesOther !== undefined) {
        // แก้แค่ข้อความ "อื่น ๆ" โดยไม่ส่งชนิดมา — ใช้ได้เฉพาะสัตว์ที่เป็น other อยู่แล้ว
        patch.speciesOther = () => `CASE WHEN species::text = 'other' THEN :speciesOther ELSE NULL END`;
        params.speciesOther = dto.speciesOther.trim() || null;
      }
      if (dto.province !== undefined) patch.location = dto.province;
      if (dto.age !== undefined) patch.ageLabel = dto.age;
      if (dto.gender !== undefined) patch.sex = genderLabelToDb(dto.gender) as Pet['sex'];
      if (dto.weight !== undefined) patch.weightKg = weightToDb(dto.weight) as string | null;
      if (dto.story !== undefined) patch.description = dto.story.trim() || null;

      if (dto.status !== undefined) {
        const dbStatus = statusLabelToDb(dto.status);
        patch.status = dbStatus as Pet['status'];
        // CHECK pets_adopted_at_consistent บังคับว่า adopted ต้องมี adopted_at
        // คู่กันเสมอ — ตั้งให้ครบในธุรกรรมเดียวกัน ไม่งั้น DB ปฏิเสธทันที
        patch.adoptedAt = () => (dbStatus === 'adopted' ? 'now()' : 'NULL');
      }

      if (Object.keys(patch).length > 0) {
        await em.createQueryBuilder().update(Pet).set(patch).where('id = :id', { id }).setParameters(params).execute();
      }

      if (dto.imageUrl !== undefined && dto.imageUrl !== '') {
        await em.delete(PetMedia, { petId: id });
        await this.insertMedia(em, id, dto.imageUrl);
      }
      if (dto.tags !== undefined) {
        await this.replaceTags(em, id, dto.tags);
      }
    });

    await this.cache.invalidate({ ns: 'pet', id }, { ns: 'petsByOwner', id: ownerId });
    if (dto.status !== undefined) await this.chatService.broadcastSystemMessages(id, since);
    return this.findOne(id);
  }

  async remove(id: string, ownerId: string) {
    await this.assertOwner(id, ownerId);
    const since = await this.dbNow();
    // soft delete เท่านั้น — ตาราง likes/conversations ของคนอื่นที่อ้าง pet นี้
    // จะพังถ้าลบแถวจริง (เหตุผลเต็มใน backend/db/README.md กลุ่มที่ 2)
    await this.pets.update({ id }, { deletedAt: () => 'now()', status: 'cancelled', adoptedAt: null });
    await this.cache.invalidate({ ns: 'pet', id }, { ns: 'petsByOwner', id: ownerId });
    await this.chatService.broadcastSystemMessages(id, since);
    return { success: true };
  }

  // like_count เปลี่ยนผ่าน trigger — ล้างแค่ตัวประกาศ รายการ by-owner ปล่อยให้หมดอายุตาม TTL
  async like(petId: string, userId: string) {
    await this.recordSwipe('likes', petId, userId);
    await this.cache.invalidate({ ns: 'pet', id: petId });
    return { success: true };
  }

  async unlike(petId: string, userId: string) {
    await this.dataSource.getRepository(Like).delete({ userId, petId });
    await this.cache.invalidate({ ns: 'pet', id: petId });
    return { success: true };
  }

  async pass(petId: string, userId: string) {
    await this.recordSwipe('passes', petId, userId);
    return { success: true };
  }

  /**
   * INSERT เฉพาะประกาศที่ยังอยู่ — ถ้าใส่ตรง ๆ ประกาศที่ไม่มีจะชน FK กลายเป็น 400
   * "จังหวัดหรือแท็กไม่มีอยู่จริง" ซึ่งชวนงง และประกาศที่ลบแล้ว (soft delete) จะยังกดได้
   * ปัดซ้ำ (ON CONFLICT) ยังนับว่าสำเร็จ เพราะผลลัพธ์ที่ผู้ใช้ต้องการเกิดขึ้นแล้ว
   *
   * คงเป็น SQL: เช็กว่ามีประกาศ + INSERT ในคำสั่งเดียว (CTE) — แยกเป็นสองคำสั่งด้วย ORM
   * ช้ากว่าเท่าตัวในเส้นทางที่ถูกเรียกบ่อยที่สุดของแอป (ทุกครั้งที่ปัด)
   */
  private async recordSwipe(table: 'likes' | 'passes', petId: string, userId: string) {
    const [row] = await this.dataSource.query<{ found: boolean }[]>(
      `WITH pet AS (SELECT id FROM pets WHERE id = $2 AND deleted_at IS NULL),
       ins AS (
         INSERT INTO ${table} (user_id, pet_id) SELECT $1, id FROM pet
         ON CONFLICT (user_id, pet_id) DO NOTHING
       )
       SELECT EXISTS (SELECT 1 FROM pet) AS found`,
      [userId, petId],
    );
    if (!row.found) throw AppException.notFound('ไม่พบประกาศนี้');
  }

  async unpass(petId: string, userId: string) {
    await this.dataSource.getRepository(Pass).delete({ userId, petId });
    return { success: true };
  }

  /** รายการที่เคยถูกใจ (favorites_screen.dart -> likedDogs) เรียงจากล่าสุด */
  async myLikes(userId: string) {
    const rows = await this.petQuery()
      .innerJoin(Like, 'l', 'l.pet_id = p.id')
      .where('l.user_id = :userId AND p.deleted_at IS NULL', { userId })
      .orderBy('l.created_at', 'DESC')
      .getRawMany<PetRow>();
    return rows.map((r) => this.toDog(r));
  }

  /**
   * ฟีดสำหรับหน้า Discover — เรียก deck_feed() ที่ฝังกฎกรอง/จัดลำดับทั้งหมดไว้ใน DB แล้ว
   * (ห้ามปัดสัตว์ตัวเอง, ไม่มีตัวที่เคยปัด, ไม่เห็นคนที่บล็อกกัน, จัดลำดับใกล้→ไกล)
   * deck_feed เป็นฟังก์ชันใน DB จึงเรียกด้วย SQL ตรง ๆ (ORM ประกาศฟังก์ชันไม่ได้)
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
      const traits = await this.dataSource
        .getRepository(Trait)
        .find({ select: { id: true }, where: { slug: In(opts.traitSlugs) } });
      traitIds = traits.map((t) => t.id);
    }

    const rows = await this.dataSource.query<{
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
    }[]>(
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
    const ids = rows.map((r) => r.id);
    let details = new Map<string, PetRow>();
    if (ids.length > 0) {
      const detailRows = await this.petQuery().where('p.id IN (:...ids)', { ids }).getRawMany<PetRow>();
      details = new Map(detailRows.map((r) => [r.id, r]));
    }

    const dogs = rows.map((r) => this.toDog(details.get(r.id)!));

    const last = rows.at(-1);
    const nextCursor = last
      ? Buffer.from(
          JSON.stringify({ r: last.proximity_rank, at: last.created_at, id: last.id }),
        ).toString('base64url')
      : null;

    return { dogs, nextCursor, hasMore: dogs.length === (opts.limit ?? 20) };
  }

  private async insertMedia(em: EntityManager, petId: string, url: string) {
    await em.insert(PetMedia, { petId, storageKey: this.storageKeyFromUrl(url), url, sortOrder: 0 });
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

  private async replaceTags(em: EntityManager, petId: string, slugs: string[]) {
    await em.delete(PetTrait, { petId });
    if (slugs.length === 0) return;
    // slug ที่ไม่มีอยู่จริงถูกข้ามเงียบ ๆ เหมือน INSERT ... SELECT เดิม
    const traits = await em.find(Trait, { select: { id: true }, where: { slug: In(slugs) } });
    if (traits.length > 0) await em.insert(PetTrait, traits.map((t) => ({ petId, traitId: t.id })));
  }
}
