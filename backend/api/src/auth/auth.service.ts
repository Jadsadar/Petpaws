import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { InjectDataSource, InjectRepository } from '@nestjs/typeorm';
import { DataSource, IsNull, type Repository } from 'typeorm';
import * as argon2 from 'argon2';
import { randomBytes, randomUUID, createHash } from 'node:crypto';
import { AppException } from '../common/app-exception.js';
import { firstPasswordError } from './password-policy.js';
import { MailService } from '../mail/mail.service.js';
import { verificationEmail, type VerifyOutcome } from './email-templates.js';
import {
  EmailVerificationToken,
  PasswordResetToken,
  RefreshToken,
  User,
} from '../database/entities/index.js';
import type { RegisterDto } from './dto/register.dto.js';
import type { LoginDto } from './dto/login.dto.js';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

const REFRESH_TOKEN_BYTES = 32;
const RESET_TOKEN_BYTES = 32;
const RESET_TOKEN_TTL_SECONDS = 30 * 60;
const VERIFY_TOKEN_BYTES = 32;
const VERIFY_TOKEN_TTL_HOURS = 24;
/** ส่งลิงก์ยืนยันซ้ำถี่กว่านี้ไม่ได้ (ต่อบัญชี) — กันใช้ระบบเป็นเครื่องยิงอีเมลใส่กล่องคนอื่น */
const VERIFY_RESEND_COOLDOWN_SECONDS = 60;
const VERIFY_RESEND_MESSAGE = 'ถ้าบัญชีนี้ยังไม่ได้ยืนยัน ระบบส่งลิงก์ยืนยันไปที่อีเมลแล้ว';

/** วันหมดอายุคิดจากนาฬิกาของ DB (ไม่ใช่ของ API) — เครื่อง API หลายตัวเวลาเพี้ยนกันได้ */
const dbNowPlusSeconds = (seconds: number) => () => `now() + make_interval(secs => ${Math.trunc(seconds)})`;

/** ค้นผู้ใช้ด้วยอีเมลหรือ username (citext — ไม่สนตัวพิมพ์ใหญ่เล็ก) ตามที่ผู้ใช้กรอกมา */
const byIdentifier = (identifier: string) =>
  identifier.includes('@') ? { email: identifier.trim() } : { username: identifier.trim() };

@Injectable()
export class AuthService {
  private readonly logger = new Logger('AuthService');

  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    @InjectRepository(User) private readonly users: Repository<User>,
    @InjectRepository(RefreshToken) private readonly refreshTokens: Repository<RefreshToken>,
    @InjectRepository(PasswordResetToken) private readonly resetTokens: Repository<PasswordResetToken>,
    @InjectRepository(EmailVerificationToken) private readonly verifyTokens: Repository<EmailVerificationToken>,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly mail: MailService,
  ) {}

  private sha256(input: string): string {
    return createHash('sha256').update(input).digest('hex');
  }

  private toUserResponse(user: User) {
    return {
      id: user.id,
      username: user.username,
      email: user.email,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      profileCompleted: user.profileCompletedAt !== null,
      // แอปเก็บไว้เติมจังหวัดเริ่มต้นตอนลงประกาศ ไม่ต้องยิง GET /users/me เพิ่ม
      province: user.location,
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

  /** ออก refresh token ใหม่ผูกกับ family เดิม (หรือ family ใหม่ถ้าเป็นการล็อกอินครั้งแรก) — คืน token และ id ของแถว */
  private async issueRefreshToken(userId: string, familyId: string) {
    const token = randomBytes(REFRESH_TOKEN_BYTES).toString('base64url');
    const ttlSeconds = this.ttlToSeconds(this.config.getOrThrow<string>('JWT_REFRESH_TTL'));
    const result = await this.refreshTokens.insert({
      userId,
      tokenHash: this.sha256(token),
      familyId,
      expiresAt: dbNowPlusSeconds(ttlSeconds),
    });
    return { token, id: result.identifiers[0].id as string };
  }

  private async issueTokenPair(userId: string, familyId: string) {
    const refresh = await this.issueRefreshToken(userId, familyId);
    return {
      tokens: { accessToken: this.signAccessToken(userId), refreshToken: refresh.token } as TokenPair,
      refreshId: refresh.id,
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
    const result = await this.users.insert({
      username,
      email: dto.email.trim(),
      passwordHash,
      displayName: username,
    });
    const userId = result.identifiers[0].id as string;

    // ส่งลิงก์ยืนยันแบบไม่รอ (ผู้ใช้ไม่ต้องรอ API ของผู้ให้บริการอีเมล) — ส่งไม่สำเร็จก็ไม่ทำให้สมัครล้ม
    // ผู้ใช้กด "ส่งลิงก์อีกครั้ง" ได้เอง
    if (this.mail.enabled) {
      void this.issueVerification(userId, dto.email.trim(), username).catch((err: Error) =>
        this.logger.error(`ส่งอีเมลยืนยันไม่สำเร็จ user=${userId}: ${err.message}`),
      );
    }

    // แอปใช้ค่านี้เลือกว่าจะขึ้นหน้า "ตรวจอีเมลของคุณ" หรือกลับไปหน้าล็อกอินตามเดิม
    return { id: userId, verificationRequired: this.mail.enabled };
  }

  /** สร้างลิงก์ยืนยันใหม่ (ลิงก์เก่าที่ยังไม่ถูกใช้ใช้ไม่ได้อีก) แล้วส่งอีเมล — DB เก็บแค่ hash ของ token */
  private async issueVerification(userId: string, email: string, username: string): Promise<void> {
    const token = randomBytes(VERIFY_TOKEN_BYTES).toString('base64url');
    await this.verifyTokens.update({ userId, usedAt: IsNull() }, { usedAt: () => 'now()' });
    await this.verifyTokens.insert({
      userId,
      tokenHash: this.sha256(token),
      expiresAt: dbNowPlusSeconds(VERIFY_TOKEN_TTL_HOURS * 3600),
    });

    const base = (this.config.get<string>('APP_PUBLIC_URL') || `http://localhost:${this.config.get<string>('API_PORT') ?? '3000'}`)
      .replace(/\/+$/, '');
    const link = `${base}/auth/verify-email?token=${token}`;
    const mail = verificationEmail({ username, link, ttlHours: VERIFY_TOKEN_TTL_HOURS });
    await this.mail.send({ to: email, ...mail });
  }

  /** กดลิงก์ในอีเมล — คืนผลให้ controller วาดหน้าเว็บ (ใช้ซ้ำหลังยืนยันแล้วถือว่าสำเร็จ กันโปรแกรมสแกนลิงก์กดซ้ำ) */
  async verifyEmail(token: string): Promise<VerifyOutcome> {
    const row = await this.dataSource
      .createQueryBuilder(EmailVerificationToken, 't')
      .innerJoin(User, 'u', 'u.id = t.user_id AND u.deleted_at IS NULL')
      .select([
        't.id AS id',
        't.user_id AS user_id',
        't.used_at AS used_at',
        't.expires_at AS expires_at',
        'u.email_verified_at AS email_verified_at',
      ])
      .where('t.token_hash = :hash', { hash: this.sha256(token) })
      .getRawOne<{ id: string; user_id: string; used_at: Date | null; expires_at: Date; email_verified_at: Date | null }>();
    if (!row) return 'invalid';

    if (row.email_verified_at) return 'ok';
    if (row.used_at !== null) return 'used';
    if (row.expires_at < new Date()) return 'expired';

    await this.dataSource.transaction(async (em) => {
      await em.update(User, { id: row.user_id, emailVerifiedAt: IsNull() }, { emailVerifiedAt: () => 'now()' });
      await em.update(EmailVerificationToken, { id: row.id }, { usedAt: () => 'now()' });
    });
    return 'ok';
  }

  /**
   * ส่งลิงก์ยืนยันอีกครั้ง — ตอบข้อความเดียวกันเสมอไม่ว่าจะมีบัญชีนี้ ยืนยันแล้ว หรืออยู่ในช่วงพัก
   * (กันคนเดาว่าอีเมล/ชื่อผู้ใช้ไหนมีอยู่ในระบบ)
   */
  async resendVerification(identifier: string) {
    if (!this.mail.enabled) return { message: VERIFY_RESEND_MESSAGE };

    const u = await this.users.findOne({
      select: { id: true, email: true, username: true, emailVerifiedAt: true },
      where: { ...byIdentifier(identifier), deletedAt: IsNull() },
    });
    if (!u || u.emailVerifiedAt) return { message: VERIFY_RESEND_MESSAGE };

    const last = await this.verifyTokens.findOne({
      select: { createdAt: true },
      where: { userId: u.id },
      order: { createdAt: 'DESC' },
    });
    if (last && Date.now() - last.createdAt.getTime() < VERIFY_RESEND_COOLDOWN_SECONDS * 1000) {
      return { message: VERIFY_RESEND_MESSAGE };
    }

    try {
      await this.issueVerification(u.id, u.email, u.username);
    } catch (err) {
      this.logger.error(`ส่งอีเมลยืนยันซ้ำไม่สำเร็จ user=${u.id}: ${(err as Error).message}`);
    }
    return { message: VERIFY_RESEND_MESSAGE };
  }

  async login(dto: LoginDto) {
    const user = await this.users.findOneBy({ ...byIdentifier(dto.identifier), deletedAt: IsNull() });

    // ข้อความ error เดียวกันไม่ว่า identifier ผิดหรือรหัสผ่านผิด
    // กันไม่ให้เดาได้ว่ามี username/email นี้ในระบบไหม
    const genericError = 'ชื่อผู้ใช้/อีเมล หรือรหัสผ่านไม่ถูกต้อง';

    if (!user) {
      throw AppException.unauthorized(genericError);
    }

    const passwordOk = await argon2.verify(user.passwordHash, dto.password);
    if (!passwordOk) {
      throw AppException.unauthorized(genericError);
    }

    // เช็กหลังรหัสผ่านถูกเท่านั้น — ถ้าเช็กก่อน คนเดารหัสจะรู้ได้ว่ามีบัญชีนี้อยู่จริง
    if (user.isSuspended) {
      const until = user.suspendedUntil;
      if (until && until <= new Date()) {
        // แบนหมดเวลาแล้ว ปลดให้เองตอนล็อกอินครั้งถัดไป ไม่ต้องรอแอดมิน
        await this.users.update({ id: user.id }, { isSuspended: false, suspendedUntil: null });
      } else if (until) {
        const when = until.toLocaleString('th-TH', { timeZone: 'Asia/Bangkok' });
        throw AppException.unauthorized(`บัญชีนี้ถูกระงับการใช้งานถึง ${when}`);
      } else {
        throw AppException.unauthorized('บัญชีนี้ถูกระงับการใช้งาน');
      }
    }

    // ต้องยืนยันอีเมลก่อนถึงเข้าได้ (เฉพาะเมื่อมีระบบอีเมลพร้อมส่งจริง) — เช็กหลังรหัสผ่านถูกและไม่ถูกแบนเท่านั้น
    // ไม่งั้นคนเดารหัสจะรู้ว่ามีบัญชีนี้อยู่จริง
    if (this.mail.enabled && !user.emailVerifiedAt) {
      throw new AppException(
        'EMAIL_NOT_VERIFIED',
        'ยังไม่ได้ยืนยันอีเมล กรุณากดลิงก์ยืนยันที่ส่งไปทางอีเมลก่อนเข้าสู่ระบบ',
        HttpStatus.FORBIDDEN,
      );
    }

    await this.users.update({ id: user.id }, { lastLoginAt: () => 'now()' });

    const { tokens } = await this.issueTokenPair(user.id, randomUUID());
    return { ...tokens, user: this.toUserResponse(user) };
  }

  async refresh(refreshToken: string) {
    const row = await this.refreshTokens.findOneBy({ tokenHash: this.sha256(refreshToken) });

    if (!row) {
      throw AppException.unauthorized('refresh token ไม่ถูกต้อง');
    }

    // token เดิมที่เคยถูกใช้ไปแล้วถูกเอามาใช้ซ้ำ = มีสำเนาหลุดออกไป
    // เพิกถอนทั้งสาย (family) ทันที บังคับให้ทุกอุปกรณ์ต้องล็อกอินใหม่
    if (row.usedAt !== null) {
      await this.refreshTokens.update(
        { familyId: row.familyId, revokedAt: IsNull() },
        { revokedAt: () => 'now()', revokedReason: 'reuse_detected' },
      );
      throw AppException.unauthorized(
        'ตรวจพบการใช้ refresh token ซ้ำ ระบบได้เพิกถอน session ทั้งหมดเพื่อความปลอดภัย กรุณาเข้าสู่ระบบใหม่',
      );
    }

    if (row.revokedAt !== null || row.expiresAt < new Date()) {
      throw AppException.unauthorized('refresh token หมดอายุหรือถูกเพิกถอนแล้ว');
    }

    const { tokens, refreshId } = await this.issueTokenPair(row.userId, row.familyId);
    await this.refreshTokens.update(
      { id: row.id },
      { usedAt: () => 'now()', revokedAt: () => 'now()', revokedReason: 'rotated', replacedById: refreshId },
    );

    return tokens;
  }

  async logout(refreshToken: string) {
    await this.refreshTokens.update(
      { tokenHash: this.sha256(refreshToken), revokedAt: IsNull() },
      { revokedAt: () => 'now()', revokedReason: 'logout' },
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

    const user = await this.users.findOne({ select: { id: true }, where: { email: email.trim(), deletedAt: IsNull() } });
    if (!user) {
      return { message };
    }

    const token = randomBytes(RESET_TOKEN_BYTES).toString('base64url');
    await this.resetTokens.insert({
      userId: user.id,
      tokenHash: this.sha256(token),
      expiresAt: dbNowPlusSeconds(RESET_TOKEN_TTL_SECONDS),
    });

    return { message, resetToken: token };
  }

  async resetPassword(token: string, newPassword: string) {
    const row = await this.dataSource
      .createQueryBuilder(PasswordResetToken, 'prt')
      .innerJoin(User, 'u', 'u.id = prt.user_id')
      .select([
        'prt.id AS id',
        'prt.user_id AS user_id',
        'prt.used_at AS used_at',
        'prt.expires_at AS expires_at',
        'u.username AS username',
        'u.email AS email',
      ])
      .where('prt.token_hash = :hash', { hash: this.sha256(token) })
      .getRawOne<{ id: string; user_id: string; used_at: Date | null; expires_at: Date; username: string; email: string }>();

    if (!row) {
      throw AppException.unauthorized('ลิงก์รีเซ็ตรหัสผ่านไม่ถูกต้อง');
    }

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

    await this.dataSource.transaction(async (em) => {
      await em.update(User, { id: row.user_id }, { passwordHash });
      await em.update(PasswordResetToken, { id: row.id }, { usedAt: () => 'now()' });
      // เปลี่ยนรหัสผ่านแล้ว = ทุกอุปกรณ์ที่ล็อกอินค้างอยู่ต้องถูกบังคับให้ล็อกอินใหม่
      // (revoked_reason นี้เตรียมไว้แล้วใน migration 002 ตั้งแต่ตอนออกแบบ refresh_tokens)
      await em.update(
        RefreshToken,
        { userId: row.user_id, revokedAt: IsNull() },
        { revokedAt: () => 'now()', revokedReason: 'password_changed' },
      );
    });

    return { success: true };
  }

  async me(userId: string) {
    const user = await this.users.findOneBy({ id: userId, deletedAt: IsNull() });
    if (!user) throw AppException.notFound('ไม่พบบัญชีผู้ใช้');
    return this.toUserResponse(user);
  }
}
