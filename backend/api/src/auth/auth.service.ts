import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as argon2 from 'argon2';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import type { Pool } from 'pg';
import { PG_POOL } from '../database/database.module.js';
import { AppException } from '../common/app-exception.js';
import { firstPasswordError } from './password-policy.js';
import type { RegisterDto } from './dto/register.dto.js';
import type { LoginDto } from './dto/login.dto.js';

interface UserRow {
  id: string;
  username: string;
  email: string;
  display_name: string;
  avatar_url: string | null;
  profile_completed_at: Date | null;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

const REFRESH_TOKEN_BYTES = 32;
const RESET_TOKEN_BYTES = 32;
const RESET_TOKEN_TTL_SECONDS = 30 * 60;

@Injectable()
export class AuthService {
  constructor(
    @Inject(PG_POOL) private readonly pool: Pool,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  private sha256(input: string): string {
    return createHash('sha256').update(input).digest('hex');
  }

  private toUserResponse(row: UserRow) {
    return {
      id: row.id,
      username: row.username,
      email: row.email,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      profileCompleted: row.profile_completed_at !== null,
    };
  }

  private signAccessToken(userId: string): string {
    return this.jwt.sign(
      { sub: userId },
      {
        secret: this.config.getOrThrow<string>('JWT_ACCESS_SECRET'),
        // @nestjs/jwt พิมพ์ expiresIn เป็น literal template ("15m"/"30d" ฯลฯ) ที่แคบกว่า
        // string ธรรมดา — ค่ามาจาก .env (validate แล้วว่าเป็น non-empty string ที่ถูกต้อง
        // ผ่าน validateEnv ตอน boot) จึงยืนยันชนิดตรงนี้แทนการเขียน literal type ซ้ำ
        expiresIn: this.config.getOrThrow<string>('JWT_ACCESS_TTL') as `${number}${'s' | 'm' | 'h' | 'd'}`,
      },
    );
  }

  /** parse '30d' / '15m' รูปแบบง่าย ๆ เป็นวินาที ไว้คำนวณ expires_at ของ refresh token แถวใน DB */
  private ttlToSeconds(ttl: string): number {
    const match = /^(\d+)([smhd])$/.exec(ttl);
    if (!match) return 60 * 60 * 24 * 30;
    const value = Number(match[1]);
    const unit = match[2];
    const multiplier = { s: 1, m: 60, h: 3600, d: 86400 }[unit] ?? 1;
    return value * multiplier;
  }

  /** ออก refresh token ใหม่ผูกกับ family เดิม (หรือ family ใหม่ถ้าเป็นการล็อกอินครั้งแรก) */
  private async issueRefreshToken(
    userId: string,
    familyId: string,
  ): Promise<string> {
    const token = randomBytes(REFRESH_TOKEN_BYTES).toString('base64url');
    const tokenHash = this.sha256(token);
    const ttlSeconds = this.ttlToSeconds(
      this.config.getOrThrow<string>('JWT_REFRESH_TTL'),
    );

    await this.pool.query(
      `INSERT INTO refresh_tokens (user_id, token_hash, family_id, expires_at)
       VALUES ($1, $2, $3, now() + ($4 || ' seconds')::interval)`,
      [userId, tokenHash, familyId, ttlSeconds],
    );

    return token;
  }

  private async issueTokenPair(userId: string, familyId: string): Promise<TokenPair> {
    return {
      accessToken: this.signAccessToken(userId),
      refreshToken: await this.issueRefreshToken(userId, familyId),
    };
  }

  async register(dto: RegisterDto) {
    const passwordError = firstPasswordError(dto.password, {
      username: dto.username,
      email: dto.email,
    });
    if (passwordError) {
      throw new AppException('WEAK_PASSWORD', passwordError);
    }

    const passwordHash = await argon2.hash(dto.password);

    // display_name ต้องมีค่าเสมอ (CHECK users_display_name_not_blank) — ใช้ username
    // ไปก่อน แล้วให้ profile_completed_at เป็น NULL เป็นตัวบอกว่ายังไม่ได้กรอกโปรไฟล์จริง
    // (ดูเหตุผลเต็มใน migration 011_profile_completed.sql)
    const username = dto.username.trim();
    // ส่ง username แยกเป็น $1 กับ $4 คนละตัว (แม้ค่าจะเหมือนกัน) เพราะ username กับ
    // display_name เป็นคอลัมน์คนละชนิด (citext vs varchar) — ใช้ $1 ซ้ำสองคอลัมน์ทำให้
    // Postgres infer type ของ parameter ไม่ได้ ("inconsistent types deduced for parameter $1")
    const result = await this.pool.query<{ id: string }>(
      `INSERT INTO users (username, email, password_hash, display_name)
       VALUES ($1, $2, $3, $4)
       RETURNING id`,
      [username, dto.email.trim(), passwordHash, username],
    );

    return { id: result.rows[0].id };
  }

  async login(dto: LoginDto) {
    const isEmail = dto.identifier.includes('@');
    const result = await this.pool.query<
      UserRow & { password_hash: string; is_suspended: boolean; suspended_until: Date | null }
    >(
      `SELECT id, username, email, display_name, avatar_url, profile_completed_at,
              password_hash, is_suspended, suspended_until
       FROM users
       WHERE deleted_at IS NULL AND ${isEmail ? 'email' : 'username'} = $1`,
      [dto.identifier.trim()],
    );

    // ข้อความ error เดียวกันไม่ว่า identifier ผิดหรือรหัสผ่านผิด
    // กันไม่ให้เดาได้ว่ามี username/email นี้ในระบบไหม
    const genericError = 'ชื่อผู้ใช้/อีเมล หรือรหัสผ่านไม่ถูกต้อง';

    if (result.rows.length === 0) {
      throw AppException.unauthorized(genericError);
    }
    const user = result.rows[0];

    const passwordOk = await argon2.verify(user.password_hash, dto.password);
    if (!passwordOk) {
      throw AppException.unauthorized(genericError);
    }

    // เช็กหลังรหัสผ่านถูกเท่านั้น — ถ้าเช็กก่อน คนเดารหัสจะรู้ได้ว่ามีบัญชีนี้อยู่จริง
    if (user.is_suspended) {
      const until = user.suspended_until;
      if (until && until <= new Date()) {
        // แบนหมดเวลาแล้ว ปลดให้เองตอนล็อกอินครั้งถัดไป ไม่ต้องรอแอดมิน
        await this.pool.query(
          `UPDATE users SET is_suspended = false, suspended_until = NULL WHERE id = $1`,
          [user.id],
        );
      } else if (until) {
        const when = until.toLocaleString('th-TH', { timeZone: 'Asia/Bangkok' });
        throw AppException.unauthorized(`บัญชีนี้ถูกระงับการใช้งานถึง ${when}`);
      } else {
        throw AppException.unauthorized('บัญชีนี้ถูกระงับการใช้งาน');
      }
    }

    await this.pool.query('UPDATE users SET last_login_at = now() WHERE id = $1', [
      user.id,
    ]);

    const familyId = randomUUID();
    const tokens = await this.issueTokenPair(user.id, familyId);

    return { ...tokens, user: this.toUserResponse(user) };
  }

  async refresh(refreshToken: string) {
    const tokenHash = this.sha256(refreshToken);

    const result = await this.pool.query<{
      id: string;
      user_id: string;
      family_id: string;
      used_at: Date | null;
      revoked_at: Date | null;
      expires_at: Date;
    }>(
      `SELECT id, user_id, family_id, used_at, revoked_at, expires_at
       FROM refresh_tokens WHERE token_hash = $1`,
      [tokenHash],
    );

    if (result.rows.length === 0) {
      throw AppException.unauthorized('refresh token ไม่ถูกต้อง');
    }
    const row = result.rows[0];

    // token เดิมที่เคยถูกใช้ไปแล้วถูกเอามาใช้ซ้ำ = มีสำเนาหลุดออกไป
    // เพิกถอนทั้งสาย (family) ทันที บังคับให้ทุกอุปกรณ์ต้องล็อกอินใหม่
    if (row.used_at !== null) {
      await this.pool.query(
        `UPDATE refresh_tokens SET revoked_at = now(), revoked_reason = 'reuse_detected'
         WHERE family_id = $1 AND revoked_at IS NULL`,
        [row.family_id],
      );
      throw AppException.unauthorized(
        'ตรวจพบการใช้ refresh token ซ้ำ ระบบได้เพิกถอน session ทั้งหมดเพื่อความปลอดภัย กรุณาเข้าสู่ระบบใหม่',
      );
    }

    if (row.revoked_at !== null || row.expires_at < new Date()) {
      throw AppException.unauthorized('refresh token หมดอายุหรือถูกเพิกถอนแล้ว');
    }

    const tokens = await this.issueTokenPair(row.user_id, row.family_id);
    const newTokenHash = this.sha256(tokens.refreshToken);

    const newRow = await this.pool.query<{ id: string }>(
      `SELECT id FROM refresh_tokens WHERE token_hash = $1`,
      [newTokenHash],
    );

    await this.pool.query(
      `UPDATE refresh_tokens
       SET used_at = now(), revoked_at = now(), revoked_reason = 'rotated', replaced_by_id = $2
       WHERE id = $1`,
      [row.id, newRow.rows[0].id],
    );

    return tokens;
  }

  async logout(refreshToken: string) {
    const tokenHash = this.sha256(refreshToken);
    await this.pool.query(
      `UPDATE refresh_tokens SET revoked_at = now(), revoked_reason = 'logout'
       WHERE token_hash = $1 AND revoked_at IS NULL`,
      [tokenHash],
    );
    return { success: true };
  }

  /**
   * ยังไม่มี email provider ต่อไว้ (ดู .env.example) — endpoint นี้จึงคืน resetToken
   * ตรง ๆ ใน response แทนการส่งอีเมลจริง เหมาะกับโปรเจกต์เรียน/dev เท่านั้น
   * ก่อนขึ้น production ต้องเปลี่ยนเป็นส่งอีเมลแล้วเอา resetToken ออกจาก response
   *
   * ไม่ตอบข้อความต่างกันระหว่าง "ไม่มีอีเมลนี้ในระบบ" กับ "มี" (ข้อความเหมือนกันเสมอ)
   * แต่การมี/ไม่มี resetToken ในตอบกลับยังทำให้เดาได้อยู่ดี —ยอมรับ trade-off นี้
   * เพราะไม่มีอีเมลจริงให้ส่ง ถ้าต่อ email provider แล้วต้องลบ resetToken ออกจาก response
   */
  async forgotPassword(email: string) {
    const message = 'ถ้ามีบัญชีนี้อยู่ในระบบ ระบบได้ออกลิงก์รีเซ็ตรหัสผ่านแล้ว';

    const userRes = await this.pool.query<{ id: string }>(
      `SELECT id FROM users WHERE email = $1 AND deleted_at IS NULL`,
      [email.trim()],
    );
    if (userRes.rows.length === 0) {
      return { message };
    }
    const userId = userRes.rows[0].id;

    const token = randomBytes(RESET_TOKEN_BYTES).toString('base64url');
    const tokenHash = this.sha256(token);

    await this.pool.query(
      `INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
       VALUES ($1, $2, now() + ($3 || ' seconds')::interval)`,
      [userId, tokenHash, RESET_TOKEN_TTL_SECONDS],
    );

    return { message, resetToken: token };
  }

  async resetPassword(token: string, newPassword: string) {
    const tokenHash = this.sha256(token);

    const result = await this.pool.query<{
      id: string;
      user_id: string;
      used_at: Date | null;
      expires_at: Date;
      username: string;
      email: string;
    }>(
      `SELECT prt.id, prt.user_id, prt.used_at, prt.expires_at, u.username, u.email
       FROM password_reset_tokens prt
       JOIN users u ON u.id = prt.user_id
       WHERE prt.token_hash = $1`,
      [tokenHash],
    );

    if (result.rows.length === 0) {
      throw AppException.unauthorized('ลิงก์รีเซ็ตรหัสผ่านไม่ถูกต้อง');
    }
    const row = result.rows[0];

    if (row.used_at !== null || row.expires_at < new Date()) {
      throw AppException.unauthorized('ลิงก์รีเซ็ตรหัสผ่านหมดอายุหรือถูกใช้ไปแล้ว');
    }

    const passwordError = firstPasswordError(newPassword, {
      username: row.username,
      email: row.email,
    });
    if (passwordError) {
      throw new AppException('WEAK_PASSWORD', passwordError);
    }

    const passwordHash = await argon2.hash(newPassword);

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('UPDATE users SET password_hash = $1 WHERE id = $2', [
        passwordHash,
        row.user_id,
      ]);
      await client.query('UPDATE password_reset_tokens SET used_at = now() WHERE id = $1', [
        row.id,
      ]);
      // เปลี่ยนรหัสผ่านแล้ว = ทุกอุปกรณ์ที่ล็อกอินค้างอยู่ต้องถูกบังคับให้ล็อกอินใหม่
      // (revoked_reason นี้เตรียมไว้แล้วใน migration 002 ตั้งแต่ตอนออกแบบ refresh_tokens)
      await client.query(
        `UPDATE refresh_tokens SET revoked_at = now(), revoked_reason = 'password_changed'
         WHERE user_id = $1 AND revoked_at IS NULL`,
        [row.user_id],
      );
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }

    return { success: true };
  }

  async me(userId: string) {
    const result = await this.pool.query<UserRow>(
      `SELECT id, username, email, display_name, avatar_url, profile_completed_at
       FROM users WHERE id = $1 AND deleted_at IS NULL`,
      [userId],
    );
    if (result.rows.length === 0) throw AppException.notFound('ไม่พบบัญชีผู้ใช้');
    return this.toUserResponse(result.rows[0]);
  }
}
