import { Inject, Injectable } from '@nestjs/common';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AppException } from '../common/app-exception.js';
import type { BanUserDto } from './dto/ban-user.dto.js';
import { toPage } from './dto/pagination.dto.js';
import { CacheService } from '../cache/cache.service.js';

/**
 * รายงานค้างทุกฉบับ พร้อม "ผู้ใช้ที่ถูกรายงานจริง" — รายงานประกาศนับเข้าเจ้าของประกาศ
 * รายงานข้อความนับเข้าคนส่ง รวมกับรายงานตัวผู้ใช้ตรง ๆ เพื่อให้คนที่โดนรายงานผ่าน
 * ประกาศ/ข้อความถึงเกณฑ์ได้เหมือนกัน (reports บังคับเป้าหมายพอดี 1 อย่างอยู่แล้ว)
 */
const PENDING_TARGETS = `
  target AS (
    SELECT r.id, r.reporter_id, r.created_at,
           COALESCE(r.reported_user_id, p.owner_id, m.sender_id) AS user_id
    FROM reports r
    LEFT JOIN pets p     ON p.id = r.reported_pet_id
    LEFT JOIN messages m ON m.id = r.reported_message_id
    WHERE r.status IN ('pending', 'reviewing')
  )`;

/** รูป (ไม่รวมวิดีโอ) ของประกาศ เรียงตามลำดับที่เจ้าของจัด — ใช้ซ้ำทั้งในรีพอร์ตและหน้าโปรไฟล์ */
const PET_PHOTOS_SQL = `
  COALESCE(
    (SELECT json_agg(json_build_object('url', pm.url, 'thumbUrl', pm.thumb_url) ORDER BY pm.sort_order)
     FROM pet_media pm
     WHERE pm.pet_id = p.id AND pm.media_type = 'photo'),
    '[]'::json
  )`;

interface ReportedUserRow {
  id: string;
  username: string;
  email: string;
  display_name: string;
  avatar_url: string | null;
  is_suspended: boolean;
  suspended_until: Date | null;
  report_count: string;
  last_reported_at: Date | null;
  total_count: string;
}

export interface PetPhoto {
  url: string;
  thumbUrl: string | null;
}

interface UserReportRow {
  id: string;
  reason: string;
  detail: string | null;
  created_at: Date;
  reporter_id: string;
  reporter_username: string;
  reporter_name: string;
  reported_user_id: string | null;
  reported_pet_id: string | null;
  pet_name: string | null;
  pet_species: string | null;
  pet_status: string | null;
  pet_deleted: boolean | null;
  pet_description: string | null;
  pet_photos: PetPhoto[] | null;
  reported_message_id: string | null;
  message_body: string | null;
  message_created_at: Date | null;
  total_count: string;
}

interface BannedUserRow {
  id: string;
  username: string;
  email: string;
  display_name: string;
  avatar_url: string | null;
  suspended_until: Date | null;
  total_count: string;
}

interface ProfilePetRow {
  id: string;
  name: string;
  species: string;
  status: string;
  description: string | null;
  location: string;
  created_at: Date;
  deleted: boolean;
  photos: PetPhoto[];
}

export interface PagingArgs {
  page: number;
  pageSize: number;
  offset: number;
}

const totalOf = (rows: { total_count: string }[]) => (rows.length > 0 ? Number(rows[0].total_count) : 0);

@Injectable()
export class AdminService {
  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly cache: CacheService,
  ) {}

  /** แอปโหลดตัวเลขสรุปใหม่ทันทีหลังแอดมินตัดสิน — ต้องล้างก่อน ไม่งั้นเห็นเลขเก่า */
  private invalidateSummary() {
    return this.cache.invalidate({ ns: 'adminSummary', id: 'all' });
  }

  private toUser(r: ReportedUserRow) {
    return {
      id: r.id,
      username: r.username,
      email: r.email,
      displayName: r.display_name,
      avatarUrl: r.avatar_url ?? '',
      reportCount: Number(r.report_count),
      lastReportedAt: r.last_reported_at,
      isSuspended: r.is_suspended,
      suspendedUntil: r.suspended_until,
    };
  }

  /**
   * นับจาก "คนรายงานไม่ซ้ำ" กันคนเดียวรายงานตัว+ประกาศ+ข้อความแล้วนับเป็น 3
   * total = จำนวนผู้ใช้ทั้งหมดที่ถึงเกณฑ์ (ก่อนแบ่งหน้า) ใช้ window count หลัง GROUP BY/HAVING
   */
  async reportedUsers(minReports: number, paging: PagingArgs) {
    const res = await this.pool.query<ReportedUserRow>(
      `WITH ${PENDING_TARGETS}
       SELECT u.id, u.username, u.email, u.display_name, u.avatar_url, u.is_suspended, u.suspended_until,
              count(DISTINCT t.reporter_id) AS report_count,
              max(t.created_at) AS last_reported_at,
              count(*) OVER() AS total_count
       FROM target t
       JOIN users u ON u.id = t.user_id
       WHERE u.deleted_at IS NULL
       GROUP BY u.id
       HAVING count(DISTINCT t.reporter_id) >= $1
       ORDER BY report_count DESC, last_reported_at DESC, u.id
       LIMIT $2 OFFSET $3`,
      [minReports, paging.pageSize, paging.offset],
    );
    return toPage(
      res.rows.map((r) => this.toUser(r)),
      totalOf(res.rows),
      paging.page,
      paging.pageSize,
    );
  }

  /**
   * แอดมินเห็นเฉพาะ "สิ่งที่ถูกรายงาน" เท่านั้น: ข้อความที่ถูกรายงานทีละข้อความ (ไม่ใช่ทั้งแชท)
   * และรูปของประกาศที่ถูกรายงาน ไม่เห็นประวัติแชทส่วนที่เหลือของผู้ใช้
   */
  async userReports(userId: string, paging: PagingArgs) {
    const res = await this.pool.query<UserReportRow>(
      `WITH ${PENDING_TARGETS}
       SELECT r.id, r.reason, r.detail, r.created_at,
              r.reporter_id, ru.username AS reporter_username, ru.display_name AS reporter_name,
              r.reported_user_id, r.reported_pet_id,
              p.name AS pet_name, p.species::text AS pet_species, p.status::text AS pet_status,
              (p.deleted_at IS NOT NULL) AS pet_deleted, p.description AS pet_description,
              ${PET_PHOTOS_SQL} AS pet_photos,
              r.reported_message_id, message_preview(m.body, m.media_type) AS message_body, m.created_at AS message_created_at,
              count(*) OVER() AS total_count
       FROM target t
       JOIN reports r   ON r.id = t.id
       JOIN users ru    ON ru.id = r.reporter_id
       LEFT JOIN pets p     ON p.id = r.reported_pet_id
       LEFT JOIN messages m ON m.id = r.reported_message_id
       WHERE t.user_id = $1
       ORDER BY r.created_at DESC, r.id
       LIMIT $2 OFFSET $3`,
      [userId, paging.pageSize, paging.offset],
    );
    return toPage(
      res.rows.map((r) => this.toReport(r)),
      totalOf(res.rows),
      paging.page,
      paging.pageSize,
    );
  }

  private toReport(r: UserReportRow) {
    const targetType = r.reported_pet_id ? 'pet' : r.reported_message_id ? 'message' : 'user';
    return {
      id: r.id,
      reason: r.reason,
      detail: r.detail ?? '',
      createdAt: r.created_at,
      reporter: { id: r.reporter_id, username: r.reporter_username, displayName: r.reporter_name },
      targetType,
      petId: r.reported_pet_id,
      petName: r.pet_name,
      pet: r.reported_pet_id
        ? {
            id: r.reported_pet_id,
            name: r.pet_name,
            species: r.pet_species,
            status: r.pet_status,
            deleted: r.pet_deleted ?? false,
            description: r.pet_description ?? '',
            photos: r.pet_photos ?? [],
          }
        : null,
      messageId: r.reported_message_id,
      messageBody: r.message_body,
      messageCreatedAt: r.message_created_at,
    };
  }

  async bannedUsers(paging: PagingArgs) {
    const res = await this.pool.query<BannedUserRow>(
      `SELECT id, username, email, display_name, avatar_url, suspended_until,
              count(*) OVER() AS total_count
       FROM users
       WHERE is_suspended AND deleted_at IS NULL
         AND (suspended_until IS NULL OR suspended_until > now())
       ORDER BY suspended_until NULLS FIRST, id
       LIMIT $1 OFFSET $2`,
      [paging.pageSize, paging.offset],
    );
    return toPage(
      res.rows.map((r) => ({
        id: r.id,
        username: r.username,
        email: r.email,
        displayName: r.display_name,
        avatarUrl: r.avatar_url ?? '',
        suspendedUntil: r.suspended_until,
        permanent: r.suspended_until === null,
      })),
      totalOf(res.rows),
      paging.page,
      paging.pageSize,
    );
  }

  /** ตัวเลขสรุปบนแดชบอร์ด (นับทั้งระบบ ไม่ขึ้นกับว่าแอดมินอยู่หน้าไหนของรายการ) */
  summary() {
    return this.cache.getOrSet({ ns: 'adminSummary', id: 'all' }, () => this.loadSummary());
  }

  private async loadSummary() {
    const res = await this.pool.query<{ reported: string; temporary: string; permanent: string }>(
      `WITH ${PENDING_TARGETS}
       SELECT
         (SELECT count(DISTINCT u.id) FROM target t
            JOIN users u ON u.id = t.user_id AND u.deleted_at IS NULL) AS reported,
         (SELECT count(*) FROM users
            WHERE is_suspended AND deleted_at IS NULL AND suspended_until > now()) AS temporary,
         (SELECT count(*) FROM users
            WHERE is_suspended AND deleted_at IS NULL AND suspended_until IS NULL) AS permanent`,
    );
    const r = res.rows[0];
    return { reported: Number(r.reported), temporary: Number(r.temporary), permanent: Number(r.permanent) };
  }

  /**
   * โปรไฟล์ของผู้ใช้ที่ถูกรายงาน + ประกาศทั้งหมดของเขาพร้อมรูป (รวมประกาศที่ถูกลบ/รับเลี้ยงแล้ว
   * เพราะรายงานอาจชี้ไปที่ประกาศที่หายจากเด็คไปแล้ว แอดมินต้องยังเห็นหลักฐาน)
   * ไม่ส่งเบอร์โทร/ไลน์ เพราะแอดมินตัดสินจากเนื้อหาที่ถูกรายงานได้โดยไม่ต้องใช้ช่องทางติดต่อ
   */
  async userProfile(userId: string) {
    const user = await this.pool.query<{
      id: string;
      username: string;
      email: string;
      display_name: string;
      avatar_url: string | null;
      bio: string | null;
      location: string | null;
      home_type: string | null;
      is_admin: boolean;
      is_suspended: boolean;
      suspended_until: Date | null;
      created_at: Date;
      last_login_at: Date | null;
    }>(
      `SELECT id, username, email, display_name, avatar_url, bio, location, home_type::text AS home_type,
              is_admin, is_suspended, suspended_until, created_at, last_login_at
       FROM users WHERE id = $1 AND deleted_at IS NULL`,
      [userId],
    );
    const u = user.rows[0];
    if (!u) throw AppException.notFound('ไม่พบผู้ใช้นี้');

    const pets = await this.pool.query<ProfilePetRow>(
      `SELECT p.id, p.name, p.species::text AS species, p.status::text AS status, p.description,
              p.location, p.created_at, (p.deleted_at IS NOT NULL) AS deleted,
              ${PET_PHOTOS_SQL} AS photos
       FROM pets p
       WHERE p.owner_id = $1
       ORDER BY p.created_at DESC
       LIMIT 50`,
      [userId],
    );

    const pending = await this.pool.query<{ n: string }>(
      `WITH ${PENDING_TARGETS}
       SELECT count(DISTINCT reporter_id) AS n FROM target WHERE user_id = $1`,
      [userId],
    );

    return {
      id: u.id,
      username: u.username,
      email: u.email,
      displayName: u.display_name,
      avatarUrl: u.avatar_url ?? '',
      bio: u.bio ?? '',
      province: u.location ?? '',
      homeType: u.home_type ?? '',
      isAdmin: u.is_admin,
      isSuspended: u.is_suspended,
      suspendedUntil: u.suspended_until,
      createdAt: u.created_at,
      lastLoginAt: u.last_login_at,
      pendingReportCount: Number(pending.rows[0]?.n ?? 0),
      pets: pets.rows.map((p) => ({
        id: p.id,
        name: p.name,
        species: p.species,
        status: p.status,
        description: p.description ?? '',
        location: p.location,
        createdAt: p.created_at,
        deleted: p.deleted,
        photos: p.photos,
      })),
    };
  }

  async ban(adminId: string, userId: string, dto: BanUserDto) {
    if (userId === adminId) throw AppException.forbidden('แบนตัวเองไม่ได้');

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      const target = await client.query<{ is_admin: boolean }>(
        `SELECT is_admin FROM users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`,
        [userId],
      );
      if (target.rows.length === 0) throw AppException.notFound('ไม่พบผู้ใช้นี้');
      if (target.rows[0].is_admin) throw AppException.forbidden('แบนแอดมินด้วยกันไม่ได้');

      const updated = await client.query<{ suspended_until: Date | null }>(
        `UPDATE users
         SET is_suspended = true,
             suspended_until = CASE WHEN $2::int IS NULL THEN NULL
                                    ELSE now() + make_interval(days => $2::int) END
         WHERE id = $1
         RETURNING suspended_until`,
        [userId, dto.days ?? null],
      );

      // เตะออกจากทุกเครื่อง — access token ที่ออกไปแล้วยังใช้ได้จนหมดอายุ (JWT_ACCESS_TTL)
      await client.query(
        `UPDATE refresh_tokens SET revoked_at = now(), revoked_reason = 'suspended'
         WHERE user_id = $1 AND revoked_at IS NULL`,
        [userId],
      );

      // ปิดรายงานค้างของคนนี้ให้หลุดจากคิว (reviewed_at ต้องมีค่าตาม CHECK reports_reviewed_consistent)
      await client.query(
        `WITH ${PENDING_TARGETS}
         UPDATE reports
         SET status = 'actioned', reviewed_by = $2, reviewed_at = now(), review_note = $3
         WHERE id IN (SELECT id FROM target WHERE user_id = $1)`,
        [userId, adminId, dto.note ?? null],
      );

      await client.query('COMMIT');
      await this.invalidateSummary();
      return { success: true, suspendedUntil: updated.rows[0].suspended_until };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async unban(userId: string) {
    const res = await this.pool.query(
      `UPDATE users SET is_suspended = false, suspended_until = NULL
       WHERE id = $1 AND deleted_at IS NULL`,
      [userId],
    );
    if (res.rowCount === 0) throw AppException.notFound('ไม่พบผู้ใช้นี้');
    await this.invalidateSummary();
    return { success: true };
  }

  async dismissReports(adminId: string, userId: string) {
    const res = await this.pool.query(
      `WITH ${PENDING_TARGETS}
       UPDATE reports
       SET status = 'dismissed', reviewed_by = $2, reviewed_at = now()
       WHERE id IN (SELECT id FROM target WHERE user_id = $1)`,
      [userId, adminId],
    );
    await this.invalidateSummary();
    return { success: true, dismissed: res.rowCount ?? 0 };
  }
}
