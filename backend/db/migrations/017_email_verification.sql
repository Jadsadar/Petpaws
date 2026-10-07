-- =============================================================================
-- 017 — ยืนยันอีเมลด้วยลิงก์ (กดยืนยันในอีเมล)
--
-- ตารางที่เพิ่ม: email_verification_tokens
-- คอลัมน์ users.email_verified_at มีอยู่แล้วตั้งแต่ migration 002 (NULL = ยังไม่ยืนยัน)
--
-- เก็บเฉพาะ hash ของ token (เหมือน password_reset_tokens) — ถ้าฐานข้อมูลรั่ว ผู้โจมตีก็ไม่ได้ลิงก์ที่ใช้ได้จริง
-- =============================================================================

BEGIN;

CREATE TABLE email_verification_tokens (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash char(64)    NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX email_verification_tokens_token_hash_key ON email_verification_tokens (token_hash);
-- ใช้เช็กช่วงพักก่อนส่งลิงก์ซ้ำ (กดส่งรัวๆ ไม่ได้) และหาลิงก์ล่าสุดของผู้ใช้
CREATE INDEX email_verification_tokens_user_created_idx
  ON email_verification_tokens (user_id, created_at DESC);

-- ผู้ใช้ที่มีอยู่แล้วก่อนระบบนี้ถือว่ายืนยันแล้ว — ไม่งั้นทุกคนในระบบจะถูกล็อกไม่ให้เข้าสู่ระบบ
-- (ใช้เวลาสมัครเป็นเวลายืนยัน ไม่ใช่ now() จะได้ไม่ดูเหมือนเพิ่งยืนยันพร้อมกันหมด)
UPDATE users SET email_verified_at = created_at WHERE email_verified_at IS NULL;

COMMIT;
