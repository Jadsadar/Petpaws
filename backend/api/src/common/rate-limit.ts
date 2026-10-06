import { ExecutionContext, HttpStatus, Injectable } from '@nestjs/common';
import { ThrottlerGuard, minutes, normalizeIp, type ThrottlerLimitDetail } from '@nestjs/throttler';
import { AppException } from './app-exception.js';

/**
 * เพดานกลางของทุก route (ต่อผู้ใช้ที่ล็อกอิน หรือต่อ IP ถ้ายังไม่ล็อกอิน) — ตั้งกว้างพอให้
 * ใช้งานจริงไม่ชน (ปัด deck รัว ๆ, ส่งรูปทีละ 10 รูป = ขอใบอนุญาต 10 + ส่ง 10 ข้อความ)
 * มีไว้กันสคริปต์ยิงถล่ม ไม่ใช่กันผู้ใช้ปกติ
 */
export const DEFAULT_RATE_LIMIT = { ttl: minutes(1), limit: 300 };

/** อีเมลที่ส่งมาใน body (login / forgot-password) — ใช้แยกนับต่อบัญชี */
const emailOf = (req: Record<string, any>) =>
  typeof req.body?.email === 'string' ? req.body.email.trim().toLowerCase() : '';

const ipOf = (req: Record<string, any>) => normalizeIp(req.ip ?? '', 64);

/** resend-verification รับ identifier (อีเมลหรือชื่อผู้ใช้) — นับต่อ IP + identifier */
const identifierOf = (req: Record<string, any>) =>
  typeof req.body?.identifier === 'string' ? req.body.identifier.trim().toLowerCase() : '';

/**
 * นับ "IP + อีเมล" ไม่ใช่ IP อย่างเดียว: กันเดารหัสผ่านของบัญชีเดียว แต่ไม่ล็อกทั้งห้องเรียน
 * ที่ล็อกอินพร้อมกันผ่าน Wi-Fi วงเดียว (ทุกคนออกเน็ตด้วย IP เดียวกัน)
 */
const byIpAndEmail = (req: Record<string, any>) => `ip:${ipOf(req)}|email:${emailOf(req)}`;

/** เพดานเฉพาะ route ที่โดนโจมตีบ่อย — ใช้กับ @Throttle({ default: ... }) */
export const AUTH_RATE_LIMITS = {
  // ผิด 5 ครั้งใน 1 นาที -> พัก 5 นาที
  login: { ttl: minutes(1), limit: 5, blockDuration: minutes(5), getTracker: byIpAndEmail },
  // ส่งอีเมลรีเซ็ตได้ 3 ครั้งต่อ 15 นาทีต่อบัญชี กันใช้เราเป็นเครื่องยิงสแปมใส่กล่องคนอื่น
  forgotPassword: { ttl: minutes(15), limit: 3, getTracker: byIpAndEmail },
  register: { ttl: minutes(10), limit: 20 },
  // กดลิงก์ในอีเมล (GET) — กันการสุ่มเดา token
  verifyEmail: { ttl: minutes(1), limit: 20 },
  // ส่งลิงก์ยืนยันซ้ำ: 5 ครั้งต่อ 15 นาทีต่อบัญชี (นอกจากนี้ตัว service ยังพัก 60 วินาทีต่อบัญชี)
  resendVerification: {
    ttl: minutes(15),
    limit: 5,
    getTracker: (req: Record<string, any>) => `ip:${ipOf(req)}|id:${identifierOf(req)}`,
  },
  resetPassword: { ttl: minutes(15), limit: 10 },
};

/**
 * ThrottlerGuard ที่ปรับให้เข้ากับระบบนี้:
 * - ต้องลงทะเบียนเป็น APP_GUARD "หลัง" JwtAuthGuard เพื่อให้ request.user มีค่าแล้ว
 *   ผู้ใช้ที่ล็อกอินนับต่อบัญชี (มือถือหลายเครื่องในเครือข่ายมือถือมักใช้ IP ร่วมกัน)
 * - ข้าม WebSocket — ChatGateway ไม่มี request แบบ HTTP ให้ดึง IP/header
 * - error เป็นรูปแบบ { error: { code, message } } เดียวกับทั้งระบบ
 *
 * ตัวนับเก็บใน Redis (RedisThrottlerStorage) — ถูกต้องแม้มี API หลายตัวหลัง load balancer
 */
@Injectable()
export class AppThrottlerGuard extends ThrottlerGuard {
  protected override async shouldSkip(context: ExecutionContext): Promise<boolean> {
    return context.getType() !== 'http';
  }

  protected override async getTracker(req: Record<string, any>): Promise<string> {
    const userId = req.user?.id as string | undefined;
    return userId ? `user:${userId}` : `ip:${ipOf(req)}`;
  }

  protected override async throwThrottlingException(
    _context: ExecutionContext,
    detail: ThrottlerLimitDetail,
  ): Promise<void> {
    const wait = Math.max(1, Math.ceil(detail.timeToBlockExpire || detail.timeToExpire));
    throw new AppException(
      'RATE_LIMITED',
      `ทำรายการถี่เกินไป กรุณารอ ${wait} วินาทีแล้วลองใหม่`,
      HttpStatus.TOO_MANY_REQUESTS,
    );
  }
}
