import { Inject, Injectable } from '@nestjs/common';
import type { Pool, PoolClient } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AppException } from '../common/app-exception.js';
import { homeTypeEnumToLabel, homeTypeLabelToEnum } from '../common/home-type.js';
import { CacheService, type CacheRef } from '../cache/cache.service.js';
import type { UpdateProfileDto } from './dto/update-profile.dto.js';

@Injectable()
export class UsersService {
  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly cache: CacheService,
  ) {}

  /**
   * โปรไฟล์เต็ม (self) — คีย์ตรงกับ currentUserProfile ฝั่ง Flutter เป๊ะ ๆ
   * (name, province, phone, lineId, fbLink, homeType, profileImageUrl, traits)
   * เพื่อให้ ProfileScreen ใช้ response นี้เติม state ได้ตรง ๆ โดยไม่ต้องแปลง key
   */
  async getMe(userId: string) {
    const [userRes, contactRes, traitsRes] = await Promise.all([
      this.pool.query(
        `SELECT id, username, email, display_name, bio, location, home_type, avatar_url
         FROM users WHERE id = $1 AND deleted_at IS NULL`,
        [userId],
      ),
      this.pool.query(
        `SELECT phone, line_id, fb_name FROM user_contacts WHERE user_id = $1`,
        [userId],
      ),
      this.pool.query(
        `SELECT t.slug FROM user_traits ut JOIN traits t ON t.id = ut.trait_id
         WHERE ut.user_id = $1`,
        [userId],
      ),
    ]);

    if (userRes.rows.length === 0) throw AppException.notFound('ไม่พบบัญชีผู้ใช้');
    const u = userRes.rows[0];
    const c = contactRes.rows[0] ?? {};

    return {
      id: u.id,
      username: u.username,
      email: u.email,
      name: u.display_name,
      province: u.location,
      bio: u.bio,
      homeType: homeTypeEnumToLabel(u.home_type),
      profileImageUrl: u.avatar_url ?? '',
      phone: c.phone ?? '',
      lineId: c.line_id ?? '',
      fbLink: c.fb_name ?? '',
      traits: traitsRes.rows.map((r) => r.slug),
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
    const [userRes, contactRes, traitsRes] = await Promise.all([
      this.pool.query(
        `SELECT display_name, location, avatar_url FROM users
         WHERE id = $1 AND deleted_at IS NULL`,
        [userId],
      ),
      this.pool.query(
        `SELECT line_id, fb_name FROM user_contacts WHERE user_id = $1`,
        [userId],
      ),
      this.pool.query(
        `SELECT t.slug FROM user_traits ut JOIN traits t ON t.id = ut.trait_id
         WHERE ut.user_id = $1`,
        [userId],
      ),
    ]);

    if (userRes.rows.length === 0) throw AppException.notFound('ไม่พบผู้ใช้นี้');
    const u = userRes.rows[0];
    const c = contactRes.rows[0] ?? {};

    return {
      displayName: u.display_name,
      province: u.location,
      profileImageUrl: u.avatar_url ?? '',
      lineId: c.line_id ?? '',
      fbLink: c.fb_name ?? '',
      traits: traitsRes.rows.map((r) => r.slug),
    };
  }

  async updateMe(userId: string, dto: UpdateProfileDto) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      const userFields: string[] = [];
      const userValues: unknown[] = [];
      let i = 1;

      if (dto.name !== undefined) {
        userFields.push(`display_name = $${i++}`);
        userValues.push(dto.name.trim() || 'ผู้ใช้');
      }
      if (dto.province !== undefined) {
        userFields.push(`location = $${i++}`);
        userValues.push(dto.province);
      }
      if (dto.bio !== undefined) {
        userFields.push(`bio = $${i++}`);
        userValues.push(dto.bio);
      }
      if (dto.homeType !== undefined) {
        const enumValue = homeTypeLabelToEnum(dto.homeType);
        if (!enumValue) throw new AppException('INVALID_HOME_TYPE', 'ประเภทที่พักอาศัยไม่ถูกต้อง');
        userFields.push(`home_type = $${i++}`);
        userValues.push(enumValue);
      }
      if (dto.profileImageUrl !== undefined) {
        userFields.push(`avatar_url = $${i++}`);
        userValues.push(dto.profileImageUrl);
      }

      // เรียก PATCH /users/me สำเร็จครั้งแรก = ถือว่ากรอกโปรไฟล์ครั้งแรกเสร็จแล้ว
      // (แทนที่การเช็ก displayName ว่างแบบเดิมฝั่ง Firebase — ดู migration 011)
      userFields.push('profile_completed_at = COALESCE(profile_completed_at, now())');

      if (userFields.length > 0) {
        userValues.push(userId);
        await client.query(
          `UPDATE users SET ${userFields.join(', ')} WHERE id = $${i}`,
          userValues,
        );
      }

      if (dto.phone !== undefined || dto.lineId !== undefined || dto.fbLink !== undefined) {
        await client.query(
          `INSERT INTO user_contacts (user_id, phone, line_id, fb_name)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (user_id) DO UPDATE SET
             phone = COALESCE($2, user_contacts.phone),
             line_id = COALESCE($3, user_contacts.line_id),
             fb_name = COALESCE($4, user_contacts.fb_name),
             updated_at = now()`,
          [userId, dto.phone ?? null, dto.lineId ?? null, dto.fbLink ?? null],
        );
      }

      if (dto.traits !== undefined) {
        await this.replaceTraits(client, userId, dto.traits);
      }

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    await this.invalidateProfile(userId, dto);
    return this.getMe(userId);
  }

  /** ชื่อ/รูปของเจ้าของถูกฝังอยู่ใน JSON ของทุกประกาศ (ownerName/ownerAvatar) ต้องล้างตามด้วย */
  private async invalidateProfile(userId: string, dto: UpdateProfileDto) {
    const refs: CacheRef[] = [{ ns: 'userPublic', id: userId }];
    if (this.cache.enabled && (dto.name !== undefined || dto.profileImageUrl !== undefined)) {
      const pets = await this.pool.query<{ id: string }>(
        `SELECT id FROM pets WHERE owner_id = $1 AND deleted_at IS NULL`,
        [userId],
      );
      refs.push({ ns: 'petsByOwner', id: userId }, ...pets.rows.map((p) => ({ ns: 'pet' as const, id: p.id })));
    }
    await this.cache.invalidate(...refs);
  }

  private async replaceTraits(client: PoolClient, userId: string, slugs: string[]) {
    await client.query('DELETE FROM user_traits WHERE user_id = $1', [userId]);
    if (slugs.length === 0) return;
    await client.query(
      `INSERT INTO user_traits (user_id, trait_id)
       SELECT $1, id FROM traits WHERE slug = ANY($2::text[])`,
      [userId, slugs],
    );
  }
}
