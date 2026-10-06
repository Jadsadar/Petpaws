-- =============================================================================
-- 020 — deck_feed เร็วขึ้น: อ่านเฉพาะแถวที่ต้องใช้ แทนการจัดอันดับสัตว์ทุกตัวแล้วตัดเหลือ 20
--
-- ฟังก์ชันที่แทน: deck_feed (013) — ชื่อ พารามิเตอร์ คอลัมน์ผลลัพธ์ และลำดับผลลัพธ์เหมือนเดิมทุกอย่าง
-- ดัชนีที่เพิ่ม: pets_deck_species_idx
--
-- ปัญหาของ 013 (EXPLAIN ANALYZE กับสัตว์ 6,000 ตัว): proximity_rank เป็นค่าที่คำนวณสด index
-- ช่วยเรียงไม่ได้ — ต้องอ่าน pets ทุกแถว (Seq Scan) ผ่านเงื่อนไขกรองทั้งหมด หารูปแรกให้ "ทุกแถว"
-- (LATERAL pet_media ~5,200 ครั้ง) แล้วเรียงทั้งก้อนก่อนตัดเหลือ 20 — ช้าลงตามจำนวนประกาศทั้งระบบ
--
-- แบบใหม่:
--   1. แยกเป็น 3 ช่วงตามความใกล้ — 0 จังหวัดเดียวกัน (หรือจังหวัดที่ผู้ใช้กรอง) / 1 ภาคเดียวกัน /
--      2 ที่เหลือ — แต่ละช่วงเรียงด้วย created_at, id ได้ตรง ๆ จึงอ่านตาม index แล้วหยุดเมื่อได้ครบ
--      (ไม่ต้องอ่านทุกแถว) เงื่อนไขกรองแต่ละตัว (ถูกใจ/ปัดผ่าน/บล็อก ฯลฯ) เช็กเฉพาะแถวที่อ่านถึง
--   2. รวมสามช่วงแล้วตัดเหลือ p_limit ก่อน แล้วค่อยหารูปแรก/ชื่อเจ้าของ เฉพาะแถวที่ได้จริง
--   3. cursor (rank, created_at, id) ใช้แบบเดิม: ช่วงที่ rank น้อยกว่า cursor ข้ามทั้งช่วง,
--      ช่วงที่ rank เท่ากันเอาเฉพาะแถวหลัง cursor, ช่วงที่ rank มากกว่าเอาทั้งช่วง
-- =============================================================================

BEGIN;

-- กรองชนิดสัตว์ (หน้า Discover มีปุ่มหมา/แมว/...) — ช่วง "ที่เหลือ" อ่านตาม index นี้ได้เลย
CREATE INDEX IF NOT EXISTS pets_deck_species_idx
  ON pets (status, species, created_at DESC, id DESC)
  WHERE deleted_at IS NULL;

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
  WITH viewer AS (
    -- จังหวัดทั้งหมดในภาคของผู้ดู คิดครั้งเดียวเก็บเป็น array — ช่วง 1/2 ข้างล่างเลยเป็นเงื่อนไขต่อแถว
    -- ธรรมดา (ไม่ต้อง join provinces) planner จึงอ่าน pets ตาม index แล้วหยุดเมื่อได้ครบได้
    SELECT u2.location AS province, pv.region AS region,
           COALESCE((SELECT array_agg(pp.name::text) FROM provinces pp WHERE pp.region = pv.region), '{}') AS region_provinces
    FROM users u2
    LEFT JOIN provinces pv ON pv.name = u2.location
    WHERE u2.id = p_viewer_id
  ),
  -- ประกาศที่ผู้ดูคนนี้มีสิทธิ์เห็น (กฎเดียวกับ 013 ทุกข้อ) — NOT MATERIALIZED: ให้แต่ละช่วงข้างล่าง
  -- ใส่เงื่อนไขของตัวเองแล้วอ่านตาม index เอง ไม่ใช่คำนวณทุกแถวเก็บไว้ก่อน
  eligible AS NOT MATERIALIZED (
    SELECT p.id, p.location, p.created_at
    FROM pets p
    JOIN users u ON u.id = p.owner_id
    WHERE p.deleted_at IS NULL
      AND p.status = 'available'
      AND p.report_count < 5
      AND p.owner_id <> p_viewer_id
      AND u.deleted_at IS NULL
      AND (u.is_suspended = false OR u.suspended_until <= now())
      AND NOT EXISTS (SELECT 1 FROM likes l WHERE l.user_id = p_viewer_id AND l.pet_id = p.id)
      AND NOT EXISTS (SELECT 1 FROM passes pa WHERE pa.user_id = p_viewer_id AND pa.pet_id = p.id)
      AND NOT EXISTS (
        SELECT 1 FROM blocks b
        WHERE (b.blocker_id = p_viewer_id AND b.blocked_id = p.owner_id)
           OR (b.blocker_id = p.owner_id  AND b.blocked_id = p_viewer_id)
      )
      AND (p_species IS NULL OR p.species = p_species)
      AND (
        p_trait_ids IS NULL OR EXISTS (
          SELECT 1 FROM pet_traits pt
          WHERE pt.pet_id = p.id AND pt.trait_id = ANY(p_trait_ids)
        )
      )
  ),
  ranked AS (
    -- ช่วง 0: จังหวัดที่ผู้ใช้กรอง หรือจังหวัดเดียวกับผู้ดู
    (SELECT e.id, e.created_at, 0 AS proximity_rank
       FROM eligible e, viewer v
      WHERE e.location = COALESCE(p_location, v.province)
        AND (p_cursor_at IS NULL OR COALESCE(p_cursor_rank, 0) < 0
             OR (COALESCE(p_cursor_rank, 0) = 0 AND (e.created_at, e.id) < (p_cursor_at, p_cursor_id)))
      ORDER BY e.created_at DESC, e.id DESC
      LIMIT LEAST(GREATEST(p_limit, 1), 50))
    UNION ALL
    -- ช่วง 1: จังหวัดอื่นในภาคเดียวกัน (ไม่มีช่วงนี้ตอนกรองจังหวัด)
    (SELECT e.id, e.created_at, 1
       FROM eligible e, viewer v
      WHERE p_location IS NULL
        AND e.location <> v.province
        AND e.location = ANY(v.region_provinces)
        AND (p_cursor_at IS NULL OR COALESCE(p_cursor_rank, 0) < 1
             OR (COALESCE(p_cursor_rank, 0) = 1 AND (e.created_at, e.id) < (p_cursor_at, p_cursor_id)))
      ORDER BY e.created_at DESC, e.id DESC
      LIMIT LEAST(GREATEST(p_limit, 1), 50))
    UNION ALL
    -- ช่วง 2: ที่เหลือ (ต่างภาค, จังหวัดที่ไม่อยู่ในตาราง provinces, หรือผู้ดูยังไม่ได้ตั้งจังหวัด)
    (SELECT e.id, e.created_at, 2
       FROM eligible e, viewer v
      WHERE p_location IS NULL
        AND e.location IS DISTINCT FROM v.province
        AND NOT (e.location = ANY(v.region_provinces))
        AND (p_cursor_at IS NULL OR COALESCE(p_cursor_rank, 0) < 2
             OR (COALESCE(p_cursor_rank, 0) = 2 AND (e.created_at, e.id) < (p_cursor_at, p_cursor_id)))
      ORDER BY e.created_at DESC, e.id DESC
      LIMIT LEAST(GREATEST(p_limit, 1), 50))
  ),
  page AS (
    SELECT r.id, r.proximity_rank
    FROM ranked r
    ORDER BY r.proximity_rank, r.created_at DESC, r.id DESC
    LIMIT LEAST(GREATEST(p_limit, 1), 50)
  )
  -- รูปแรก/ชื่อเจ้าของ หาเฉพาะแถวที่อยู่ในหน้านี้
  SELECT
    p.id, p.owner_id, p.name, p.species, p.breed, p.age_months, p.sex, p.size,
    p.location, p.like_count, p.created_at,
    pm.url AS media_url,
    u.display_name AS owner_name,
    u.avatar_url AS owner_avatar,
    pg.proximity_rank
  FROM page pg
  JOIN pets p ON p.id = pg.id
  JOIN users u ON u.id = p.owner_id
  LEFT JOIN LATERAL (
    SELECT pm.url FROM pet_media pm WHERE pm.pet_id = p.id ORDER BY pm.sort_order LIMIT 1
  ) pm ON true
  ORDER BY pg.proximity_rank, p.created_at DESC, p.id DESC;
$$;

COMMIT;
