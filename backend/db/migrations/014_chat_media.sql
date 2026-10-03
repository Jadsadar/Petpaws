-- =============================================================================
-- 014 — รูปภาพ / วิดีโอในแชท
--
-- แก้ตาราง: messages (เพิ่มคอลัมน์ media), on_message_inserted (preview)
-- เพิ่ม: message_media_type, message_preview()
--
-- ฐานข้อมูลที่รันไปแล้ว (initdb ไม่รันไฟล์ใหม่ให้เอง) ต้องรันไฟล์นี้เอง:
--   Get-Content db\migrations\014_chat_media.sql -Raw -Encoding UTF8 | docker exec -i petpaws-postgres psql -U petpaws -d petpaws -v ON_ERROR_STOP=1
-- =============================================================================

BEGIN;

CREATE TYPE message_media_type AS ENUM ('image', 'video');

-- -----------------------------------------------------------------------------
-- 1 ข้อความมีสื่อได้ไม่เกิน 1 ชิ้น (แนบหลายรูป = ส่งหลายข้อความ) จึงเก็บเป็นคอลัมน์
-- ในแถวเดียวกัน ไม่แยกตาราง message_attachments — ไม่ต้อง join ตอนดึงประวัติ
--
-- เก็บเป็น URL เต็มเหมือน pet_media.url / users.avatar_url เพื่อให้ MediaService.keyFromUrl
-- และงานกวาดไฟล์ใช้วิธีเดียวกันทั้งระบบ
--
-- ทุกชนิดต้องมี thumbnail: bubble ในห้องแชทโหลดแค่ thumbnail (~30KB) ตัวจริงโหลด
-- ตอนกดเปิดดูเท่านั้น — ห้องที่มีรูป 50 รูปจะได้ไม่ต้องโหลดหลายสิบ MB
--
-- width/height เก็บไว้ให้แอปจองขนาด bubble ได้ก่อนรูปโหลดเสร็จ (จอไม่กระตุก)
-- -----------------------------------------------------------------------------
ALTER TABLE messages
  ADD COLUMN media_type        message_media_type,
  ADD COLUMN media_url         text,
  ADD COLUMN thumbnail_url     text,
  ADD COLUMN media_width       int,
  ADD COLUMN media_height      int,
  ADD COLUMN media_duration_ms int;

-- ข้อความที่มีสื่อไม่ต้องมีคำบรรยายก็ได้ (body = '')
-- body ยังเป็น NOT NULL ไว้ตามเดิม โค้ดที่อ่าน body อยู่แล้ว (push, admin) จะไม่เจอ null
ALTER TABLE messages DROP CONSTRAINT messages_body_not_blank;
ALTER TABLE messages
  ADD CONSTRAINT messages_body_or_media CHECK (
    length(btrim(body)) > 0 OR media_type IS NOT NULL
  ),
  -- มีสื่อ = ต้องครบทุกช่อง ไม่มีสื่อ = ต้องว่างทุกช่อง (กันแถวครึ่ง ๆ กลาง ๆ)
  --
  -- ระวัง: CHECK ที่ได้ผลเป็น NULL ถือว่า "ผ่าน" — ห้ามเขียน media_width > 0 เปล่า ๆ
  -- เพราะ width เป็น NULL จะได้ NULL แล้วหลุดไปได้ ต้อง COALESCE ให้เป็น false เสมอ
  ADD CONSTRAINT messages_media_complete CHECK (
    (media_type IS NULL
      AND media_url IS NULL AND thumbnail_url IS NULL
      AND media_width IS NULL AND media_height IS NULL AND media_duration_ms IS NULL)
    OR
    (media_type IS NOT NULL
      AND media_url IS NOT NULL AND thumbnail_url IS NOT NULL
      AND COALESCE(media_width, 0) > 0 AND COALESCE(media_height, 0) > 0)
  ),
  -- ความยาววิดีโอบังคับเฉพาะวิดีโอ รูปต้องไม่มี
  ADD CONSTRAINT messages_media_duration CHECK (
    CASE WHEN media_type = 'video' THEN COALESCE(media_duration_ms, 0) > 0
         ELSE media_duration_ms IS NULL
    END
  );


-- -----------------------------------------------------------------------------
-- ข้อความสั้นสำหรับรายการห้องแชท / push / หน้าแอดมิน — นิยามที่เดียวให้ทุกที่ตรงกัน
--   ข้อความล้วน        -> ตัวข้อความ
--   รูป + คำบรรยาย      -> "📷 คำบรรยาย"
--   รูปเฉย ๆ            -> "📷 รูปภาพ"
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION message_preview(body text, media message_media_type)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE media
           WHEN 'image' THEN '📷 ' || COALESCE(NULLIF(btrim(body), ''), 'รูปภาพ')
           WHEN 'video' THEN '🎬 ' || COALESCE(NULLIF(btrim(body), ''), 'วิดีโอ')
           ELSE body
         END
$$;


-- -----------------------------------------------------------------------------
-- on_message_inserted — เหมือน 005 ทุกอย่าง ต่างแค่ last_message_preview
-- ใช้ message_preview() แทน left(body) (ไม่งั้นข้อความรูปเปล่าจะได้ preview ว่าง)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION on_message_inserted()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  conv conversations%ROWTYPE;
BEGIN
  SELECT * INTO conv FROM conversations WHERE id = NEW.conversation_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ไม่พบห้องแชท %', NEW.conversation_id
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  IF NEW.sender_id <> conv.initiator_id AND NEW.sender_id <> conv.owner_id THEN
    RAISE EXCEPTION 'ผู้ใช้ % ไม่ใช่คู่สนทนาของห้อง %', NEW.sender_id, NEW.conversation_id
      USING ERRCODE = 'check_violation';
  END IF;

  IF conv.status <> 'active' THEN
    RAISE EXCEPTION 'ห้องแชท % ถูกปิดแล้ว (%) ส่งข้อความใหม่ไม่ได้',
      NEW.conversation_id, conv.closed_reason
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE conversations SET
    last_message_at        = NEW.created_at,
    last_message_preview   = left(message_preview(NEW.body, NEW.media_type), 120),
    last_message_sender_id = NEW.sender_id,
    initiator_unread_count = initiator_unread_count
      + CASE WHEN NEW.sender_id <> initiator_id THEN 1 ELSE 0 END,
    owner_unread_count     = owner_unread_count
      + CASE WHEN NEW.sender_id <> owner_id THEN 1 ELSE 0 END
  WHERE id = NEW.conversation_id;

  RETURN NEW;
END;
$$;

COMMIT;
