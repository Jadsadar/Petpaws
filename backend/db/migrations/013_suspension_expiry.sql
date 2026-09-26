-- =============================================================================
-- 013 — ให้ deck เห็นประกาศของคนที่แบนหมดอายุแล้ว
--
-- แอดมินแบนแบบกำหนดวันได้ (users.suspended_until) — แต่ deck_feed() ใน 008 กรอง
-- แค่ u.is_suspended = false ทำให้ประกาศของคนที่แบนหมดเวลาไปแล้วยังถูกซ่อนต่อ
-- จนกว่าเจ้าตัวจะล็อกอินกลับมา (login เป็นคนปลด flag ให้อัตโนมัติ)
--
-- แก้ด้วยการถือว่า "แบนที่เลยเวลาแล้ว = ไม่ได้แบน" ตรงนี้ด้วย
-- ฟังก์ชันเป็น STABLE จึงใช้ now() ได้ถูกต้อง
--
-- เนื้อฟังก์ชันคัดลอกจาก 008 ทั้งตัว ต่างกันแค่เงื่อนไข is_suspended บรรทัดเดียว
--
-- DB ที่สร้างไว้แล้ว (volume ไม่ว่าง) ไฟล์นี้จะไม่รันเอง ต้องรันมือครั้งเดียว:
--   docker compose exec -T postgres psql -U petpaws -d petpaws -v ON_ERROR_STOP=1 < db/migrations/013_suspension_expiry.sql
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION deck_feed(
  p_viewer_id    uuid,
  p_limit        int         DEFAULT 20,
  p_cursor_rank  int         DEFAULT NULL,
  p_cursor_at    timestamptz DEFAULT NULL,
  p_cursor_id    uuid        DEFAULT NULL,
  p_location     varchar     DEFAULT NULL,
  p_species      pet_species DEFAULT NULL,
  p_trait_ids    uuid[]      DEFAULT NULL
)
RETURNS TABLE (
  id             uuid,
  owner_id       uuid,
  name           varchar,
  species        pet_species,
  breed          varchar,
  age_months     int,
  sex            pet_sex,
  size           pet_size,
  location       varchar,
  like_count     int,
  created_at     timestamptz,
  media_url      text,
  owner_name     varchar,
  owner_avatar   text,
  proximity_rank int
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    p.id, p.owner_id, p.name, p.species, p.breed, p.age_months, p.sex, p.size,
    p.location, p.like_count, p.created_at,
    pm.url AS media_url,
    u.display_name AS owner_name,
    u.avatar_url AS owner_avatar,
    CASE
      WHEN p_location IS NOT NULL THEN 0
      WHEN p.location = viewer.province THEN 0
      WHEN pv_pet.region IS NOT NULL AND pv_pet.region = viewer.region THEN 1
      ELSE 2
    END AS proximity_rank
  FROM pets p
  JOIN users u ON u.id = p.owner_id
  CROSS JOIN (
    SELECT u2.location AS province, pv.region AS region
    FROM users u2
    LEFT JOIN provinces pv ON pv.name = u2.location
    WHERE u2.id = p_viewer_id
  ) viewer
  LEFT JOIN provinces pv_pet ON pv_pet.name = p.location
  LEFT JOIN LATERAL (
    SELECT pm.url
    FROM pet_media pm
    WHERE pm.pet_id = p.id
    ORDER BY pm.sort_order
    LIMIT 1
  ) pm ON true
  WHERE p.deleted_at IS NULL
    AND p.status = 'available'
    AND p.report_count < 5
    AND p.owner_id <> p_viewer_id
    AND u.deleted_at IS NULL

    -- เปลี่ยนจาก 008: แบนที่เลยกำหนดแล้วถือว่าไม่ได้แบน
    AND (u.is_suspended = false OR u.suspended_until <= now())

    AND NOT EXISTS (
      SELECT 1 FROM likes l
      WHERE l.user_id = p_viewer_id AND l.pet_id = p.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM passes pa
      WHERE pa.user_id = p_viewer_id AND pa.pet_id = p.id
    )
    AND NOT EXISTS (
      SELECT 1 FROM blocks b
      WHERE (b.blocker_id = p_viewer_id AND b.blocked_id = p.owner_id)
         OR (b.blocker_id = p.owner_id  AND b.blocked_id = p_viewer_id)
    )
    AND (p_location IS NULL OR p.location = p_location)
    AND (p_species  IS NULL OR p.species  = p_species)
    AND (
      p_trait_ids IS NULL OR EXISTS (
        SELECT 1 FROM pet_traits pt
        WHERE pt.pet_id = p.id AND pt.trait_id = ANY(p_trait_ids)
      )
    )
    AND (
      p_cursor_at IS NULL
      OR (CASE
            WHEN p_location IS NOT NULL THEN 0
            WHEN p.location = viewer.province THEN 0
            WHEN pv_pet.region IS NOT NULL AND pv_pet.region = viewer.region THEN 1
            ELSE 2
          END) > COALESCE(p_cursor_rank, 0)
      OR (
        (CASE
           WHEN p_location IS NOT NULL THEN 0
           WHEN p.location = viewer.province THEN 0
           WHEN pv_pet.region IS NOT NULL AND pv_pet.region = viewer.region THEN 1
           ELSE 2
         END) = COALESCE(p_cursor_rank, 0)
        AND p.created_at < p_cursor_at
      )
      OR (
        (CASE
           WHEN p_location IS NOT NULL THEN 0
           WHEN p.location = viewer.province THEN 0
           WHEN pv_pet.region IS NOT NULL AND pv_pet.region = viewer.region THEN 1
           ELSE 2
         END) = COALESCE(p_cursor_rank, 0)
        AND p.created_at = p_cursor_at AND p.id < p_cursor_id
      )
    )
  ORDER BY
    (CASE
       WHEN p_location IS NOT NULL THEN 0
       WHEN p.location = viewer.province THEN 0
       WHEN pv_pet.region IS NOT NULL AND pv_pet.region = viewer.region THEN 1
       ELSE 2
     END) ASC,
    p.created_at DESC,
    p.id DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 50);
$$;

COMMIT;
