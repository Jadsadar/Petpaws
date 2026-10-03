-- =============================================================================
-- 015 — ข้อความระบบในแชท (สัตว์ได้บ้านแล้ว / ยกเลิกประกาศ) และการลบแชทฝั่งตัวเอง
--
-- ตารางที่แตะ: messages (+kind), conversation_hides (ใหม่)
-- ฟังก์ชันที่แทนที่: close_conversations_for_pet()
-- =============================================================================

BEGIN;

-- 'user' = ข้อความที่คนพิมพ์ / 'system' = ประกาศของระบบ แบบ "เข้าร่วม/ออกจากกลุ่ม" ของไลน์
-- ข้อความระบบใช้ sender_id = เจ้าของประกาศ (ผ่าน FK/trigger เดิมได้ ไม่ต้องมี user พิเศษ)
-- แต่ฝั่งแอปต้องวาดกลางจอ ไม่ใช่ฟองของเจ้าของ และรายงานไม่ได้
ALTER TABLE messages
  ADD COLUMN kind text NOT NULL DEFAULT 'user',
  ADD CONSTRAINT messages_kind_valid CHECK (kind IN ('user', 'system'));

-- ปิดห้อง + ประกาศในห้องในคำสั่งเดียว
--
-- ต้อง INSERT ข้อความ "ก่อน" UPDATE สถานะห้องเป็น closed เพราะ trigger ของ messages
-- ปฏิเสธข้อความใหม่ในห้องที่ปิดแล้ว (และทำที่ DB เหมือนเดิม เพราะสถานะสัตว์เปลี่ยนได้
-- หลายทาง ไม่ต้องไปจำเรียกซ้ำในทุก service)
CREATE OR REPLACE FUNCTION close_conversations_for_pet()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  reason conversation_closed_reason;
  notice text;
BEGIN
  -- ลบประกาศ หรือเจ้าของตั้งสถานะ "ยกเลิกประกาศ" ในหน้าแก้ไข ถือเป็นเรื่องเดียวกัน
  IF (NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL)
     OR (NEW.status::text = 'cancelled' AND OLD.status::text <> 'cancelled') THEN
    reason := 'pet_deleted';
    notice := 'เจ้าของยกเลิกประกาศนี้แล้ว';
  ELSIF NEW.status = 'adopted' AND OLD.status <> 'adopted' THEN
    reason := 'pet_adopted';
    notice := 'มีคนรับเลี้ยงสัตว์ตัวนี้แล้ว';
  ELSE
    RETURN NEW;
  END IF;

  INSERT INTO messages (conversation_id, sender_id, body, kind, created_at)
  SELECT c.id, c.owner_id, notice, 'system', now()
    FROM conversations c
   WHERE c.pet_id = NEW.id AND c.status = 'active';

  UPDATE conversations
     SET status        = 'closed',
         closed_at     = now(),
         closed_reason = reason
   WHERE pet_id = NEW.id
     AND status = 'active';

  RETURN NEW;
END;
$$;

-- ลบแชท = ซ่อนจากรายการของ "ฉัน" เท่านั้น อีกฝ่ายยังเห็นครบ (เหมือนไลน์)
-- เก็บเวลาที่ซ่อน: ข้อความเก่ากว่านั้นจะไม่โผล่กลับมา แต่ถ้ามีข้อความใหม่หลังจากนั้น
-- ห้องจะกลับมาในรายการพร้อมเฉพาะข้อความใหม่
CREATE TABLE conversation_hides (
  conversation_id uuid        NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id         uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  hidden_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);

COMMIT;
