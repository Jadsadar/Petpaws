-- =============================================================================
-- 016 — ชนิดสัตว์เลี้ยง: เพิ่ม "ปลา" และช่องระบุเองสำหรับ "อื่น ๆ"
--
-- แอปมีชนิด: สุนัข / แมว / นก / ปลา / กระต่าย / อื่น ๆ (ระบุ...)
-- enum เดิมมี dog, cat, rabbit, bird, other — ขาดแค่ fish
-- =============================================================================

-- ADD VALUE ไว้นอกธุรกรรมโดยตั้งใจ: ค่า enum ใหม่ใช้ในธุรกรรมเดียวกันกับที่เพิ่มไม่ได้
ALTER TYPE pet_species ADD VALUE IF NOT EXISTS 'fish';

BEGIN;

-- ข้อความที่ผู้ลงประกาศพิมพ์เองเมื่อเลือก "อื่น ๆ" (เช่น หนู, เต่า, งู)
-- เก็บเฉพาะตอน species = 'other' — ถ้าเปลี่ยนไปเลือกชนิดอื่นต้องถูกล้างทิ้ง
-- ไม่ให้ค้างเป็นข้อมูลขยะ (CHECK ด้านล่างบังคับที่ DB)
ALTER TABLE pets
  ADD COLUMN species_other varchar(50),
  ADD CONSTRAINT pets_species_other_only_when_other
    CHECK (species_other IS NULL OR species::text = 'other');

COMMIT;
