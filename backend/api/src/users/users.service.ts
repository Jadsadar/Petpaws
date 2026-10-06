import { Injectable } from '@nestjs/common';
import { InjectDataSource, InjectRepository } from '@nestjs/typeorm';
import { DataSource, EntityManager, In, IsNull, type Repository } from 'typeorm';
import type { QueryDeepPartialEntity } from 'typeorm/query-builder/QueryPartialEntity.js';
import { AppException } from '../common/app-exception.js';
import { homeTypeEnumToLabel, homeTypeLabelToEnum } from '../common/home-type.js';
import { CacheService, type CacheRef } from '../cache/cache.service.js';
import { Pet, Trait, User, UserContact, UserTrait } from '../database/entities/index.js';
import type { UpdateProfileDto } from './dto/update-profile.dto.js';

@Injectable()
export class UsersService {
  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    @InjectRepository(User) private readonly users: Repository<User>,
    @InjectRepository(UserContact) private readonly contacts: Repository<UserContact>,
    private readonly cache: CacheService,
  ) {}

  /** slug ของนิสัย/ไลฟ์สไตล์ที่ผู้ใช้เลือกไว้ */
  private async traitSlugs(userId: string): Promise<string[]> {
    const rows = await this.dataSource
      .createQueryBuilder(UserTrait, 'ut')
      .innerJoin(Trait, 't', 't.id = ut.trait_id')
      .select('t.slug', 'slug')
      .where('ut.user_id = :userId', { userId })
      .orderBy('t.sort_order')
      .getRawMany<{ slug: string }>();
    return rows.map((r) => r.slug);
  }

  /**
   * โปรไฟล์เต็ม (self) — คีย์ตรงกับ currentUserProfile ฝั่ง Flutter เป๊ะ ๆ
   * (name, province, phone, lineId, fbLink, homeType, profileImageUrl, traits)
   * เพื่อให้ ProfileScreen ใช้ response นี้เติม state ได้ตรง ๆ โดยไม่ต้องแปลง key
   */
  async getMe(userId: string) {
    const [u, c, traits] = await Promise.all([
      this.users.findOne({
        select: {
          id: true,
          username: true,
          email: true,
          displayName: true,
          bio: true,
          location: true,
          homeType: true,
          avatarUrl: true,
        },
        where: { id: userId, deletedAt: IsNull() },
      }),
      this.contacts.findOneBy({ userId }),
      this.traitSlugs(userId),
    ]);
    if (!u) throw AppException.notFound('ไม่พบบัญชีผู้ใช้');

    return {
      id: u.id,
      username: u.username,
      email: u.email,
      name: u.displayName,
      province: u.location,
      bio: u.bio,
      homeType: homeTypeEnumToLabel(u.homeType),
      profileImageUrl: u.avatarUrl ?? '',
      phone: c?.phone ?? '',
      lineId: c?.lineId ?? '',
      fbLink: c?.fbName ?? '',
      traits,
    };
  }

  /**
   * โปรไฟล์สาธารณะ — ตรงกับที่ user_profile_screen.dart อ่านจริง (_header/_traits/_contact):
   * displayName, province, profileImageUrl, traits, lineId, fbLink
   * **ไม่มี phone** เพราะหน้านั้นตั้งใจไม่โชว์เบอร์โทรในโปรไฟล์สาธารณะ (ดูคอมเมนต์ในไฟล์นั้น)
   */
  getPublic(userId: string) {
    return this.cache.getOrSet({ ns: 'userPublic', id: userId }, () => this.loadPublic(userId));
  }

  private async loadPublic(userId: string) {
    const [u, c, traits] = await Promise.all([
      this.users.findOne({
        select: { displayName: true, location: true, avatarUrl: true },
        where: { id: userId, deletedAt: IsNull() },
      }),
      this.contacts.findOne({ select: { lineId: true, fbName: true }, where: { userId } }),
      this.traitSlugs(userId),
    ]);
    if (!u) throw AppException.notFound('ไม่พบผู้ใช้นี้');

    return {
      displayName: u.displayName,
      province: u.location,
      profileImageUrl: u.avatarUrl ?? '',
      lineId: c?.lineId ?? '',
      fbLink: c?.fbName ?? '',
      traits,
    };
  }

  async updateMe(userId: string, dto: UpdateProfileDto) {
    await this.dataSource.transaction(async (em) => {
      const patch: QueryDeepPartialEntity<User> = {};
      if (dto.name !== undefined) patch.displayName = dto.name.trim() || 'ผู้ใช้';
      if (dto.province !== undefined) patch.location = dto.province;
      if (dto.bio !== undefined) patch.bio = dto.bio;
      if (dto.homeType !== undefined) {
        const enumValue = homeTypeLabelToEnum(dto.homeType);
        if (!enumValue) throw new AppException('INVALID_HOME_TYPE', 'ประเภทที่พักอาศัยไม่ถูกต้อง');
        patch.homeType = enumValue as User['homeType'];
      }
      if (dto.profileImageUrl !== undefined) patch.avatarUrl = dto.profileImageUrl;
      // เรียก PATCH /users/me สำเร็จครั้งแรก = ถือว่ากรอกโปรไฟล์ครั้งแรกเสร็จแล้ว
      // (แทนที่การเช็ก displayName ว่างแบบเดิมฝั่ง Firebase — ดู migration 011)
      patch.profileCompletedAt = () => 'COALESCE(profile_completed_at, now())';
      await em.update(User, { id: userId }, patch);

      // ส่งมาเฉพาะช่องที่จะแก้ — upsert ตั้งค่าเฉพาะช่องที่ส่งมา ช่องอื่นคงค่าเดิม (updated_at ใช้ trigger)
      const contact: Partial<UserContact> = {};
      if (dto.phone !== undefined) contact.phone = dto.phone;
      if (dto.lineId !== undefined) contact.lineId = dto.lineId;
      if (dto.fbLink !== undefined) contact.fbName = dto.fbLink;
      if (Object.keys(contact).length > 0) {
        await em.upsert(UserContact, { userId, ...contact }, { conflictPaths: ['userId'] });
      }

      if (dto.traits !== undefined) await this.replaceTraits(em, userId, dto.traits);
    });

    await this.invalidateProfile(userId, dto);
    return this.getMe(userId);
  }

  /** ชื่อ/รูปของเจ้าของถูกฝังอยู่ใน JSON ของทุกประกาศ (ownerName/ownerAvatar) ต้องล้างตามด้วย */
  private async invalidateProfile(userId: string, dto: UpdateProfileDto) {
    const refs: CacheRef[] = [{ ns: 'userPublic', id: userId }];
    if (this.cache.enabled && (dto.name !== undefined || dto.profileImageUrl !== undefined)) {
      const pets = await this.dataSource
        .getRepository(Pet)
        .find({ select: { id: true }, where: { ownerId: userId, deletedAt: IsNull() } });
      refs.push({ ns: 'petsByOwner', id: userId }, ...pets.map((p) => ({ ns: 'pet' as const, id: p.id })));
    }
    await this.cache.invalidate(...refs);
  }

  private async replaceTraits(em: EntityManager, userId: string, slugs: string[]) {
    await em.delete(UserTrait, { userId });
    if (slugs.length === 0) return;
    // slug ที่ไม่มีอยู่จริงถูกข้ามเงียบ ๆ เหมือน INSERT ... SELECT เดิม
    const traits = await em.find(Trait, { select: { id: true }, where: { slug: In(slugs) } });
    if (traits.length > 0) await em.insert(UserTrait, traits.map((t) => ({ userId, traitId: t.id })));
  }
}
