-- =============================================================================
-- 003_demo_accounts.sql — 10 บัญชีพร้อมประกาศ ที่ "ล็อกอินเข้าแอปได้จริง"
--
-- รันด้วย (จากโฟลเดอร์ backend/):
--   docker compose exec -T postgres psql -U petpaws -d petpaws -v ON_ERROR_STOP=1 < db/seeds/003_demo_accounts.sql
--
--   +-------------------------------------------------------------+
--   |  ล็อกอินได้ทั้ง 10 บัญชี                                      |
--   |    ชื่อผู้ใช้ : demo01 ... demo10   (หรือใช้อีเมลก็ได้)          |
--   |    แอดมิน   : admin                                          |
--   |    รหัสผ่าน  : Petpaws1!            (เหมือนกันทุกบัญชี)         |
--   +-------------------------------------------------------------+
--
-- ต่างจาก seed อีก 2 ไฟล์ตรงไหน:
--   001_dev_seed.sql      (@petpaws.dev)  — ชุดเล็กไว้ไล่ flow ทั่วไป  · ล็อกอินไม่ได้
--   002_test_accounts.sql (@petpaws.test) — ชุด edge case ของ schema  · ล็อกอินไม่ได้
--   003 (ไฟล์นี้)          (@petpaws.demo) — ชุดสาธิต "เปิดแอปแล้วใช้ได้เลย" · ล็อกอินได้
--
-- ทั้ง 3 ไฟล์ใช้คนละโดเมนอีเมล จึงล้าง/รันแยกกันได้อิสระ และรันพร้อมกันได้
-- ไฟล์นี้รันซ้ำได้ไม่พัง (ล้างบัญชี @petpaws.demo เดิมก่อนเสมอ)
--
-- สิ่งที่ตั้งใจให้ชุดนี้ต่างจาก 002 (ซึ่งเน้น edge case จนใช้สาธิตไม่สะดวก):
--   1. password_hash เป็น argon2id ของจริง  -> ล็อกอินผ่าน POST /auth/login ได้
--   2. profile_completed_at ตั้งค่าให้ทุกบัญชี -> เข้าแอปแล้วเข้าหน้าหลักเลย
--                                              ไม่ถูกเด้งไปหน้าสร้างโปรไฟล์ก่อน
--   3. ใส่ age_label ทุกตัว -> หน้าประกาศโชว์อายุจริง ไม่ใช่ "-"
--      (pets.service.ts อ่าน age_label ไม่ใช่ age_months — ดู migration 012)
--   4. ทั้ง 10 บัญชีมีประกาศของตัวเอง และกระจายครบทั้ง 6 ภาค
--      -> deck มีของให้ปัดเสมอไม่ว่าล็อกอินด้วยบัญชีไหน และได้เห็น proximity rank
--         ทำงานจริง (จังหวัดเดียวกัน -> ภาคเดียวกัน -> ที่เหลือ)
--   5. มี user_contacts / user_traits ครบทุกคน -> หน้าโปรไฟล์ไม่มีช่องว่าง
--   6. รูปโปรไฟล์เป็นรูปหน้าคนจริงทุกบัญชี (randomuser.me) และรูปประกาศตรงกับ
--      ชนิด/สายพันธุ์ที่เขียนไว้จริง ไม่ใช่รูปสุ่ม
--
-- ห้ามนำไฟล์นี้ไปรันบน production (รหัสผ่านเป็นค่าสาธารณะที่รู้กันทั้งทีม)
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---------- ล้างข้อมูลเดิมของโดเมนนี้ ----------
-- ลบไล่จากตารางลูกขึ้นไปหาตารางแม่ เพราะ conversations/pets ใช้ ON DELETE RESTRICT
DELETE FROM messages       WHERE conversation_id IN (
  SELECT c.id FROM conversations c
  JOIN users u ON u.id = c.initiator_id WHERE u.email LIKE '%@petpaws.demo');
DELETE FROM conversations  WHERE initiator_id IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo')
                              OR owner_id     IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo');
DELETE FROM reports        WHERE reporter_id IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo')
                              OR reported_pet_id IN (
                                SELECT p.id FROM pets p JOIN users u ON u.id = p.owner_id
                                WHERE u.email LIKE '%@petpaws.demo');
DELETE FROM blocks         WHERE blocker_id  IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo')
                              OR blocked_id  IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo');
DELETE FROM likes          WHERE user_id     IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo');
DELETE FROM passes         WHERE user_id     IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo');
DELETE FROM pet_traits     WHERE pet_id IN (
  SELECT p.id FROM pets p JOIN users u ON u.id = p.owner_id WHERE u.email LIKE '%@petpaws.demo');
DELETE FROM pet_media      WHERE pet_id IN (
  SELECT p.id FROM pets p JOIN users u ON u.id = p.owner_id WHERE u.email LIKE '%@petpaws.demo');
DELETE FROM pets           WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo');
DELETE FROM user_traits    WHERE user_id  IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo');
DELETE FROM user_contacts  WHERE user_id  IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo');
DELETE FROM device_tokens  WHERE user_id  IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo');
DELETE FROM refresh_tokens WHERE user_id  IN (SELECT id FROM users WHERE email LIKE '%@petpaws.demo');
DELETE FROM users          WHERE email LIKE '%@petpaws.demo';


DO $seed$
DECLARE
  -- argon2id ของจริงสำหรับรหัสผ่าน 'Petpaws1!'
  -- แฮชมี salt ฝังอยู่ในตัวเอง จึงใช้ค่าเดียวซ้ำได้ทุกบัญชี (argon2.verify ผ่านหมด)
  -- สร้างด้วย: node -e "require('argon2').hash('Petpaws1!').then(console.log)"
  pw text := '$argon2id$v=19$m=65536,p=4,t=3$UQ2PB13Bs0Xp4c8uy1Ni4A$vP1W/5V/LhBi5q5ptlxkke9Ug6tOgV5mYGDpmclXH7g';

  u01 uuid; u02 uuid; u03 uuid; u04 uuid; u05 uuid;
  u06 uuid; u07 uuid; u08 uuid; u09 uuid; u10 uuid;
  uadmin uuid;

  p01a uuid; p01b uuid; p02a uuid; p02b uuid; p03 uuid; p04 uuid;
  p05 uuid; p06 uuid; p07 uuid; p08 uuid; p09a uuid; p09b uuid; p10 uuid;

  conv uuid;

  t_energetic uuid; t_chill uuid; t_affectionate uuid; t_independent uuid;
  t_talkative uuid; t_quiet uuid; t_social uuid; t_kid_friendly uuid;
  t_foodie uuid; t_tidy uuid;
BEGIN
  SELECT id INTO t_energetic    FROM traits WHERE slug = 'energetic';
  SELECT id INTO t_chill        FROM traits WHERE slug = 'chill';
  SELECT id INTO t_affectionate FROM traits WHERE slug = 'affectionate';
  SELECT id INTO t_independent  FROM traits WHERE slug = 'independent';
  SELECT id INTO t_talkative    FROM traits WHERE slug = 'talkative';
  SELECT id INTO t_quiet        FROM traits WHERE slug = 'quiet';
  SELECT id INTO t_social       FROM traits WHERE slug = 'social';
  SELECT id INTO t_kid_friendly FROM traits WHERE slug = 'kid_friendly';
  SELECT id INTO t_foodie       FROM traits WHERE slug = 'foodie';
  SELECT id INTO t_tidy         FROM traits WHERE slug = 'tidy';

  -- ==========================================================================
  -- ผู้ใช้ 10 คน — กระจายครบ 6 ภาค เพื่อให้เห็น proximity ranking ทำงานจริง
  --   กลาง     : demo01 กรุงเทพฯ, demo06 นนทบุรี
  --   เหนือ    : demo02 เชียงใหม่, demo08 เชียงราย
  --   ใต้      : demo03 ภูเก็ต, demo07 สงขลา, demo10 สุราษฎร์ธานี
  --   อีสาน    : demo04 ขอนแก่น, demo09 นครราชสีมา
  --   ตะวันออก : demo05 ชลบุรี
  --
  -- profile_completed_at ตั้งให้ทุกคน = ล็อกอินแล้วเข้าหน้าหลักทันที
  -- ==========================================================================
  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, avatar_url, email_verified_at, profile_completed_at)
  VALUES ('demo01', 'demo01@petpaws.demo', pw, 'ฟ้าใส รักสัตว์',
          'เลี้ยงหมาแมวมา 10 ปี ตอนนี้ช่วยหาบ้านให้น้อง ๆ ที่เก็บมาจากข้างถนน',
          'กรุงเทพมหานคร', 'detached_house',
          'https://randomuser.me/api/portraits/women/65.jpg', now(), now())
  RETURNING id INTO u01;

  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, avatar_url, email_verified_at, profile_completed_at)
  VALUES ('demo02', 'demo02@petpaws.demo', pw, 'ภูผา ใจดี',
          'อาสาสมัครบ้านพักสัตว์จรในเชียงใหม่ ยินดีตอบทุกคำถามก่อนรับเลี้ยง',
          'เชียงใหม่', 'townhouse',
          'https://randomuser.me/api/portraits/men/32.jpg', now(), now())
  RETURNING id INTO u02;

  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, avatar_url, email_verified_at, profile_completed_at)
  VALUES ('demo03', 'demo03@petpaws.demo', pw, 'ทราย ทะเลใส',
          'อยู่ภูเก็ต มีแมวส้มที่เก็บมาเลี้ยงกำลังหาบ้านอบอุ่นให้',
          'ภูเก็ต', 'condo',
          'https://randomuser.me/api/portraits/women/44.jpg', now(), now())
  RETURNING id INTO u03;

  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, avatar_url, email_verified_at, profile_completed_at)
  VALUES ('demo04', 'demo04@petpaws.demo', pw, 'อีสาน บ้านนา',
          'บ้านมีพื้นที่กว้าง เลี้ยงหมาใหญ่ได้สบาย ตอนนี้หาบ้านให้น้องที่เก็บมา',
          'ขอนแก่น', 'detached_house',
          'https://randomuser.me/api/portraits/men/75.jpg', now(), now())
  RETURNING id INTO u04;

  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, avatar_url, email_verified_at, profile_completed_at)
  VALUES ('demo05', 'demo05@petpaws.demo', pw, 'ชล ริมหาด',
          'ทำร้านกาแฟที่ชลบุรี มีแมวแวะมาประจำจนต้องช่วยหาบ้านให้',
          'ชลบุรี', 'apartment',
          'https://randomuser.me/api/portraits/men/11.jpg', now(), now())
  RETURNING id INTO u05;

  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, avatar_url, email_verified_at, profile_completed_at)
  VALUES ('demo06', 'demo06@petpaws.demo', pw, 'นนท์ สวนผัก',
          'เลี้ยงกระต่ายกับหนูแฮมสเตอร์มานาน ยินดีให้คำแนะนำมือใหม่',
          'นนทบุรี', 'townhouse',
          'https://randomuser.me/api/portraits/women/22.jpg', now(), now())
  RETURNING id INTO u06;

  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, avatar_url, email_verified_at, profile_completed_at)
  VALUES ('demo07', 'demo07@petpaws.demo', pw, 'ใต้ หาดใหญ่',
          'ช่วยเหลือหมาจรในหาดใหญ่ ทำหมันและฉีดวัคซีนให้ก่อนส่งต่อทุกตัว',
          'สงขลา', 'detached_house',
          'https://randomuser.me/api/portraits/men/56.jpg', now(), now())
  RETURNING id INTO u07;

  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, avatar_url, email_verified_at, profile_completed_at)
  VALUES ('demo08', 'demo08@petpaws.demo', pw, 'ดอย หมอกเหนือ',
          'อยู่เชียงราย ชอบสัตว์เงียบ ๆ ขี้อ้อน ตอนนี้หาบ้านให้แมวสองตัวแม่ลูก',
          'เชียงราย', 'detached_house',
          'https://randomuser.me/api/portraits/women/8.jpg', now(), now())
  RETURNING id INTO u08;

  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, avatar_url, email_verified_at, profile_completed_at)
  VALUES ('demo09', 'demo09@petpaws.demo', pw, 'โคราช ใจกว้าง',
          'เคยส่งน้องไปอยู่บ้านใหม่มาแล้วหลายตัว ดูโพสต์ที่สำเร็จแล้วได้ในโปรไฟล์',
          'นครราชสีมา', 'detached_house',
          'https://randomuser.me/api/portraits/women/90.jpg', now(), now())
  RETURNING id INTO u09;

  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, avatar_url, email_verified_at, profile_completed_at)
  VALUES ('demo10', 'demo10@petpaws.demo', pw, 'สุราษฎร์ ปลายทาง',
          'ทำสวนอยู่สุราษฎร์ฯ มีหมาเฝ้าสวนที่ออกลูกมา กำลังหาบ้านให้ลูก ๆ',
          'สุราษฎร์ธานี', 'detached_house',
          'https://randomuser.me/api/portraits/men/40.jpg', now(), now())
  RETURNING id INTO u10;

  -- แอดมิน — ไม่มี endpoint ยกระดับตัวเอง (ตั้งใจไว้ใน migration 002) จึงต้องตั้งผ่าน SQL
  INSERT INTO users (username, email, password_hash, display_name, bio, location,
                     home_type, is_admin, email_verified_at, profile_completed_at)
  VALUES ('admin', 'admin@petpaws.demo', pw, 'แอดมิน PetPaws',
          'บัญชีผู้ดูแลระบบสำหรับทดสอบหน้าจัดการรายงาน',
          'กรุงเทพมหานคร', 'condo', true, now(), now())
  RETURNING id INTO uadmin;

  -- ---------- ข้อมูลติดต่อ (เห็นในหน้าโปรไฟล์ / หน้าประกาศ) ----------
  INSERT INTO user_contacts (user_id, phone, line_id, fb_name) VALUES
    (u01, '0812345601', 'demo_fahsai',  'ฟ้าใส รักสัตว์'),
    (u02, '0812345602', 'demo_phupha',  'ภูผา ใจดี'),
    (u03, '0812345603', 'demo_sai',     'ทราย ทะเลใส'),
    (u04, '0812345604', 'demo_isan',    'อีสาน บ้านนา'),
    (u05, '0812345605', 'demo_chon',    'ชล ริมหาด'),
    (u06, '0812345606', 'demo_non',     'นนท์ สวนผัก'),
    (u07, '0812345607', 'demo_tai',     'ใต้ หาดใหญ่'),
    (u08, '0812345608', 'demo_doi',     'ดอย หมอกเหนือ'),
    (u09, '0812345609', 'demo_korat',   'โคราช ใจกว้าง'),
    (u10, '0812345610', 'demo_surat',   'สุราษฎร์ ปลายทาง');

  -- ---------- นิสัยของผู้ใช้ (ใช้จับคู่กับแท็กของสัตว์) ----------
  INSERT INTO user_traits (user_id, trait_id) VALUES
    (u01, t_energetic), (u01, t_kid_friendly),
    (u02, t_chill),     (u02, t_quiet),
    (u03, t_independent),(u03, t_tidy),
    (u04, t_energetic), (u04, t_social),
    (u05, t_foodie),    (u05, t_chill),
    (u06, t_quiet),     (u06, t_tidy),
    (u07, t_kid_friendly),(u07, t_affectionate),
    (u08, t_affectionate),(u08, t_quiet),
    (u09, t_social),    (u09, t_talkative),
    (u10, t_energetic), (u10, t_kid_friendly);

  -- ==========================================================================
  -- ประกาศ 13 รายการ (12 เปิดรับ + 1 ได้บ้านแล้ว)
  --
  -- ใส่ age_label ทุกตัวเสมอ — pets.service.ts แสดงผลจากคอลัมน์นี้
  -- ส่วน age_months เป็นตัวเลขประมาณไว้กรองช่วงอายุ (ดู migration 012)
  -- created_at ไล่ระดับกันเพื่อให้ลำดับในฟีดดูเป็นธรรมชาติ
  -- ==========================================================================

  -- demo01 — กรุงเทพฯ (2 ตัว)
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u01, 'ต้นหอม', 'dog', 'พันทาง', '8 เดือน', 8, 'male', 'small', true, false, 7.20,
          'ต้นหอมเก็บมาจากหน้าปากซอย ฉีดวัคซีนครบแล้ว ขี้เล่นมากและเข้ากับเด็กได้ดี '
          'เหมาะกับบ้านที่มีคนอยู่ด้วยตอนกลางวัน',
          'กรุงเทพมหานคร', now() - interval '3 hours')
  RETURNING id INTO p01a;

  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u01, 'ขนมจีน', 'cat', 'วิเชียรมาศ', '2 ปี', 24, 'female', 'small', true, true, 3.60,
          'ขนมจีนเป็นแมวไทยนิสัยเรียบร้อย ใช้กระบะทรายเป็น ไม่ข่วนเฟอร์นิเจอร์ '
          'ชอบนอนตักเวลาดูทีวี',
          'กรุงเทพมหานคร', now() - interval '1 day')
  RETURNING id INTO p01b;

  -- demo02 — เชียงใหม่ (2 ตัว)
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u02, 'ลำไย', 'dog', 'หลังอานผสม', '1 ปี 6 เดือน', 18, 'female', 'medium',
          true, true, 16.40,
          'ลำไยเป็นหมาหลังอานผสม ฉลาดมาก สอนคำสั่งพื้นฐานได้แล้ว '
          'ต้องการบ้านที่มีรั้วรอบขอบชิดเพราะชอบวิ่งสำรวจ',
          'เชียงใหม่', now() - interval '6 hours')
  RETURNING id INTO p02a;

  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u02, 'หมอก', 'cat', 'พันทางขนยาว', '10 เดือน', 10, 'male', 'small',
          true, false, 4.10,
          'หมอกขนปุยสีเทา ขี้อ้อนสุด ๆ ตามติดเจ้าของตลอดเวลา '
          'เข้ากับแมวตัวอื่นได้ดีถ้าค่อย ๆ แนะนำให้รู้จักกัน',
          'เชียงใหม่', now() - interval '2 days')
  RETURNING id INTO p02b;

  -- demo03 — ภูเก็ต
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u03, 'ส้มโอ', 'cat', 'อะบิสซิเนียนผสม', '1 ปี', 12, 'male', 'medium',
          true, true, 4.80,
          'ส้มโอเป็นแมวส้มตัวใหญ่ใจดี ไม่กลัวคนแปลกหน้า เหมาะกับบ้านที่มีคนเข้าออกบ่อย '
          'กินเก่งมากต้องคุมอาหารนิดหน่อย',
          'ภูเก็ต', now() - interval '10 hours')
  RETURNING id INTO p03;

  -- demo04 — ขอนแก่น
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u04, 'ทองคำ', 'dog', 'โกลเด้นผสม', '3 ปี', 36, 'male', 'large',
          true, true, 28.50,
          'ทองคำตัวใหญ่แต่ใจดีมาก อยู่กับเด็กเล็กได้สบาย เดินสายจูงเก่ง '
          'ต้องการบ้านที่มีพื้นที่ให้วิ่งและพาออกกำลังได้ทุกวัน',
          'ขอนแก่น', now() - interval '18 hours')
  RETURNING id INTO p04;

  -- demo05 — ชลบุรี
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u05, 'ลาเต้', 'cat', 'พันทาง', '7 เดือน', 7, 'female', 'small',
          true, false, 2.80,
          'ลาเต้เป็นลูกแมวที่มาอยู่หน้าร้านกาแฟจนคุ้นคน ร่าเริงและชอบเล่นของเล่น '
          'กำลังหาบ้านที่มีเวลาเล่นด้วยเยอะ ๆ',
          'ชลบุรี', now() - interval '1 day 4 hours')
  RETURNING id INTO p05;

  -- demo06 — นนทบุรี
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u06, 'มันฝรั่ง', 'rabbit', 'ฮอลแลนด์ลอป', '6 เดือน', 6, 'female', 'small',
          false, false, 1.60,
          'มันฝรั่งเป็นกระต่ายหูตก เงียบมากเหมาะกับคอนโด กินผักเก่ง '
          'ขับถ่ายเป็นที่แล้ว ต้องการคนที่พอมีประสบการณ์เลี้ยงกระต่าย',
          'นนทบุรี', now() - interval '2 days 6 hours')
  RETURNING id INTO p06;

  -- demo07 — สงขลา
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u07, 'ขนุน', 'dog', 'พันทาง', '2 ปี 3 เดือน', 27, 'male', 'medium',
          true, true, 18.90,
          'ขนุนเคยเป็นหมาจรแถวตลาด ทำหมันและฉีดวัคซีนครบแล้ว นิสัยสงบมาก '
          'ไม่เห่าโดยไม่มีเหตุ เหมาะกับบ้านที่ต้องการเพื่อนเงียบ ๆ',
          'สงขลา', now() - interval '3 days')
  RETURNING id INTO p07;

  -- demo08 — เชียงราย
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u08, 'นุ่น', 'cat', 'พันทาง', '4 ปี', 48, 'female', 'small',
          true, true, 3.90,
          'นุ่นเป็นแม่แมวใจเย็นมาก ผ่านการเลี้ยงลูกมาแล้วจึงนิ่งและไม่ซน '
          'เหมาะกับคนที่อยากได้แมวโตที่ไม่ต้องดูแลมาก',
          'เชียงราย', now() - interval '4 days')
  RETURNING id INTO p08;

  -- demo09 — นครราชสีมา (1 เปิดรับ + 1 ได้บ้านแล้ว)
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u09, 'ข้าวปุ้น', 'dog', 'บีเกิ้ลผสม', '1 ปี 2 เดือน', 14, 'female', 'medium',
          true, false, 12.30,
          'ข้าวปุ้นเสียงดังนิดหน่อยแต่เป็นมิตรกับทุกคน ชอบเล่นกับหมาตัวอื่น '
          'เหมาะกับบ้านที่มีหมาอยู่แล้วหรือมีคนอยู่บ้านเป็นเพื่อน',
          'นครราชสีมา', now() - interval '5 days')
  RETURNING id INTO p09a;

  -- ประกาศที่ปิดจบแล้ว — ต้องหลุดจาก deck แต่ยังอยู่บนโปรไฟล์ของ demo09 พร้อมป้าย
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location,
                    status, adopted_at, created_at)
  VALUES (u09, 'ไข่เจียว', 'cat', 'พันทาง', '9 เดือน', 9, 'male', 'small',
          true, true, 3.20,
          'ไข่เจียวได้บ้านใหม่เรียบร้อยแล้ว ขอบคุณทุกคนที่ทักมาสอบถามนะคะ',
          'นครราชสีมา', 'adopted', now() - interval '2 days', now() - interval '25 days')
  RETURNING id INTO p09b;

  -- demo10 — สุราษฎร์ธานี
  INSERT INTO pets (owner_id, name, species, breed, age_label, age_months, sex, size,
                    vaccinated, neutered, weight_kg, description, location, created_at)
  VALUES (u10, 'มะพร้าว', 'dog', 'พันทาง', '4 เดือน', 4, 'male', 'small',
          false, false, 4.50,
          'มะพร้าวเป็นลูกหมาจากแม่ที่เฝ้าสวน ยังไม่ได้ฉีดวัคซีนเพราะอายุยังน้อย '
          'กำลังหาบ้านที่พร้อมดูแลตั้งแต่เด็ก',
          'สุราษฎร์ธานี', now() - interval '7 hours')
  RETURNING id INTO p10;

  -- ---------- รูปประกาศ ----------
  -- ใช้ URL ตายตัวจากแหล่งสาธารณะที่ "ตรงชนิด/สายพันธุ์" กับที่ลงประกาศไว้จริง
  -- (ไม่ใช่ endpoint สุ่มอย่าง picsum ที่เคยใช้ตอนแรก ซึ่งให้รูปอะไรก็ได้ไม่เกี่ยวกับสัตว์)
  --   หมา     : images.dog.ceo          — แยกโฟลเดอร์ตามสายพันธุ์
  --   แมว     : cdn2.thecatapi.com      — ดึงตาม breed_ids (siam/norw/abys) แล้ว fix URL ไว้
  --   กระต่าย  : upload.wikimedia.org    — Holland Lop ตรงกับที่ประกาศไว้
  -- ทุก URL ตรวจแล้วว่าคืน 200 + image/jpeg จริง (ดูตารางสรุปใน README ของ db/)
  --
  -- เลือกใช้ URL ภายนอกแทนการอัปไฟล์ขึ้น MinIO เพื่อให้ pull แล้วรัน seed ได้เลย
  -- โดยไม่ต้องเตรียมไฟล์รูปก่อน — แลกกับที่ต้องต่อเน็ตตอนเปิดแอป
  INSERT INTO pet_media (pet_id, storage_key, url, sort_order) VALUES
    -- หมา: dog.ceo แยกตามสายพันธุ์จริง (mix = พันทาง)
    (p01a, 'pets/demo/p01a.jpg', 'https://images.dog.ceo/breeds/mix/chiquinho.jpg', 0),
    (p02a, 'pets/demo/p02a.jpg', 'https://images.dog.ceo/breeds/ridgeback-rhodesian/n02087394_3015.jpg', 0),
    (p04,  'pets/demo/p04.jpg',  'https://images.dog.ceo/breeds/retriever-golden/20200731_180910_200731.jpg', 0),
    (p07,  'pets/demo/p07.jpg',  'https://images.dog.ceo/breeds/mix/tropik.jpg', 0),
    (p09a, 'pets/demo/p09a.jpg', 'https://images.dog.ceo/breeds/beagle/n02088364_16588.jpg', 0),
    (p10,  'pets/demo/p10.jpg',  'https://images.dog.ceo/breeds/mix/cherry.jpg', 0),

    -- แมว: TheCatAPI (siam = วิเชียรมาศ, norw = ขนยาว, abys = ขนสีน้ำตาลส้ม)
    (p01b, 'pets/demo/p01b.jpg', 'https://s3.us-west-2.amazonaws.com/cdn2.thecatapi.com/images/MTU2Mjk2NA.jpg', 0),
    (p02b, 'pets/demo/p02b.jpg', 'https://s3.us-west-2.amazonaws.com/cdn2.thecatapi.com/images/d19.jpg', 0),
    (p03,  'pets/demo/p03.jpg',  'https://s3.us-west-2.amazonaws.com/cdn2.thecatapi.com/images/MTY1MzU3OA.jpg', 0),
    (p05,  'pets/demo/p05.jpg',  'https://s3.us-west-2.amazonaws.com/cdn2.thecatapi.com/images/a4d.jpg', 0),
    (p08,  'pets/demo/p08.jpg',  'https://s3.us-west-2.amazonaws.com/cdn2.thecatapi.com/images/cmb.jpg', 0),
    (p09b, 'pets/demo/p09b.jpg', 'https://s3.us-west-2.amazonaws.com/cdn2.thecatapi.com/images/ba4.jpg', 0),

    -- กระต่าย: Wikimedia Commons — Holland Lop ตรงสายพันธุ์ที่ลงประกาศพอดี
    (p06,  'pets/demo/p06.jpg',  'https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Grey_Holland_Lop_rabbit.jpg/960px-Grey_Holland_Lop_rabbit.jpg', 0);

  -- ---------- แท็กนิสัยของสัตว์ ----------
  INSERT INTO pet_traits (pet_id, trait_id) VALUES
    (p01a, t_energetic),    (p01a, t_kid_friendly), (p01a, t_social),
    (p01b, t_quiet),        (p01b, t_affectionate), (p01b, t_tidy),
    (p02a, t_energetic),    (p02a, t_independent),
    (p02b, t_affectionate), (p02b, t_chill),
    (p03,  t_foodie),       (p03,  t_social),
    (p04,  t_kid_friendly), (p04,  t_energetic),    (p04, t_social),
    (p05,  t_energetic),    (p05,  t_talkative),
    (p06,  t_quiet),        (p06,  t_tidy),
    (p07,  t_quiet),        (p07,  t_chill),
    (p08,  t_chill),        (p08,  t_affectionate), (p08, t_quiet),
    (p09a, t_talkative),    (p09a, t_social),
    (p09b, t_chill),
    (p10,  t_energetic),    (p10,  t_kid_friendly);

  -- ==========================================================================
  -- การปัด — ให้ฟีดกับหน้า "ถูกใจ" มีของอยู่แล้วตั้งแต่เปิดแอปครั้งแรก
  -- (ปัดสัตว์ตัวเองไม่ได้ DB มี trigger กันไว้ จึงจับคู่ข้ามเจ้าของเสมอ)
  -- ==========================================================================
  INSERT INTO likes (user_id, pet_id) VALUES
    (u01, p02a), (u01, p04), (u01, p08),
    (u02, p01a), (u02, p05),
    (u03, p01b), (u03, p07),
    (u05, p03),  (u05, p10),
    (u09, p01a);

  INSERT INTO passes (user_id, pet_id) VALUES
    (u01, p06), (u02, p03), (u03, p04), (u05, p07);

  -- ==========================================================================
  -- แชท 3 ห้อง — ห้องแชทต้องเกิดพร้อมข้อความแรกเสมอ (deferred constraint trigger
  -- conversations_require_first_message) จึง insert ข้อความในธุรกรรมเดียวกันนี้
  -- ==========================================================================

  -- ห้อง 1: demo02 ทักหา demo01 เรื่องต้นหอม — ยังไม่มีใครกดอ่าน (มี badge unread)
  INSERT INTO conversations (pet_id, initiator_id, owner_id)
  VALUES (p01a, u02, u01)
  RETURNING id INTO conv;
  INSERT INTO messages (conversation_id, sender_id, body, created_at) VALUES
    (conv, u02, 'สวัสดีครับ สนใจน้องต้นหอมครับ ตอนนี้ยังหาบ้านอยู่ไหมครับ',
     now() - interval '2 hours'),
    (conv, u01, 'ยังอยู่ค่ะ น้องฉีดวัคซีนครบแล้ว สะดวกให้ดูตัวจริงวันไหนดีคะ',
     now() - interval '1 hour 30 minutes'),
    (conv, u02, 'เสาร์นี้ได้ไหมครับ ผมขับรถเข้ากรุงเทพฯ พอดี',
     now() - interval '50 minutes');

  -- ห้อง 2: demo03 ทักหา demo01 เรื่องขนมจีน — อ่านครบแล้วทั้งสองฝั่ง
  INSERT INTO conversations (pet_id, initiator_id, owner_id)
  VALUES (p01b, u03, u01)
  RETURNING id INTO conv;
  INSERT INTO messages (conversation_id, sender_id, body, created_at) VALUES
    (conv, u03, 'น้องขนมจีนเข้ากับแมวตัวอื่นได้ไหมคะ ที่บ้านมีอยู่แล้วหนึ่งตัวค่ะ',
     now() - interval '1 day 3 hours'),
    (conv, u01, 'ได้ค่ะ แต่ต้องค่อย ๆ แนะนำให้รู้จักกันประมาณหนึ่งอาทิตย์นะคะ',
     now() - interval '1 day 2 hours');
  PERFORM mark_conversation_read(conv, u03);
  PERFORM mark_conversation_read(conv, u01);

  -- ห้อง 3: demo05 ทักหา demo04 เรื่องทองคำ — ฝั่งเจ้าของยังไม่อ่าน
  INSERT INTO conversations (pet_id, initiator_id, owner_id)
  VALUES (p04, u05, u04)
  RETURNING id INTO conv;
  INSERT INTO messages (conversation_id, sender_id, body, created_at) VALUES
    (conv, u05, 'น้องทองคำตัวใหญ่มากเลยครับ อยู่คอนโดได้ไหมครับ',
     now() - interval '5 hours');

  -- ==========================================================================
  -- รายงาน — demo10 โดนรายงานจาก 10 คนไม่ซ้ำ (ถึงเกณฑ์ค่าเริ่มต้นของ
  -- GET /admin/reported-users พอดี) ผสมรายงานตัวผู้ใช้ 7 + ประกาศ 3
  --
  -- รายงานประกาศต้องไม่ถึง 5 เพราะ deck_feed ซ่อนประกาศที่ report_count >= 5
  -- อัตโนมัติ ไม่งั้นทดสอบ "ปลดแบนแล้วประกาศกลับมาใน deck" ไม่ได้
  -- ==========================================================================
  INSERT INTO reports (reporter_id, reported_user_id, reason, detail, created_at) VALUES
    (u01,    u10, 'scam',          'ขอค่ามัดจำก่อนให้ดูตัวน้อง',        now() - interval '3 days'),
    (u02,    u10, 'scam',          'ให้โอนเงินค่าวัคซีนก่อน',            now() - interval '2 days 20 hours'),
    (u03,    u10, 'inappropriate', 'พูดจาไม่สุภาพในแชท',               now() - interval '2 days 6 hours'),
    (u04,    u10, 'spam',          'ทักมาซ้ำหลายรอบ',                  now() - interval '2 days'),
    (u05,    u10, 'fake_info',     'ข้อมูลโปรไฟล์ไม่ตรงกับที่คุย',        now() - interval '1 day 12 hours'),
    (u06,    u10, 'scam',          'ขอเงินค่าเดินทางส่งน้อง',             now() - interval '1 day'),
    (u07,    u10, 'other',         'พฤติกรรมน่าสงสัย',                 now() - interval '20 hours');
  INSERT INTO reports (reporter_id, reported_pet_id, reason, detail, created_at) VALUES
    (u08,    p10, 'fake_info',     'รูปไม่ตรงกับตัวจริง',                now() - interval '10 hours'),
    (u09,    p10, 'fake_info',     'อายุน้องไม่ตรงกับที่ลงไว้',            now() - interval '6 hours'),
    (uadmin, p10, 'animal_abuse',  'สภาพน้องในรูปดูไม่ได้รับการดูแล',      now() - interval '2 hours');

  RAISE NOTICE '';
  RAISE NOTICE '==============================================================';
  RAISE NOTICE '  สร้างบัญชีสาธิต 10 บัญชีเรียบร้อย (โดเมน @petpaws.demo)';
  RAISE NOTICE '';
  RAISE NOTICE '  ล็อกอินได้ทันที:';
  RAISE NOTICE '    ชื่อผู้ใช้ : demo01 ... demo10, admin (แอดมิน)';
  RAISE NOTICE '    รหัสผ่าน  : Petpaws1!';
  RAISE NOTICE '';
  RAISE NOTICE '  ประกาศ 13 รายการ (12 เปิดรับ + 1 ได้บ้านแล้ว)';
  RAISE NOTICE '  ถูกใจ 10 / ปัดผ่าน 4 / ห้องแชท 3 ห้อง';
  RAISE NOTICE '  demo10 โดนรายงาน 10 คน (ถึงเกณฑ์แอดมิน)';
  RAISE NOTICE '==============================================================';
END
$seed$;

COMMIT;

-- ---------- สรุปผล ----------
SELECT 'users (demo)'   AS ตาราง, count(*) AS จำนวน FROM users WHERE email LIKE '%@petpaws.demo'
UNION ALL SELECT 'pets',          count(*) FROM pets p JOIN users u ON u.id=p.owner_id WHERE u.email LIKE '%@petpaws.demo'
UNION ALL SELECT 'pet_media',     count(*) FROM pet_media pm JOIN pets p ON p.id=pm.pet_id JOIN users u ON u.id=p.owner_id WHERE u.email LIKE '%@petpaws.demo'
UNION ALL SELECT 'pet_traits',    count(*) FROM pet_traits pt JOIN pets p ON p.id=pt.pet_id JOIN users u ON u.id=p.owner_id WHERE u.email LIKE '%@petpaws.demo'
UNION ALL SELECT 'user_contacts', count(*) FROM user_contacts uc JOIN users u ON u.id=uc.user_id WHERE u.email LIKE '%@petpaws.demo'
UNION ALL SELECT 'user_traits',   count(*) FROM user_traits ut JOIN users u ON u.id=ut.user_id WHERE u.email LIKE '%@petpaws.demo'
UNION ALL SELECT 'likes',         count(*) FROM likes l JOIN users u ON u.id=l.user_id WHERE u.email LIKE '%@petpaws.demo'
UNION ALL SELECT 'passes',        count(*) FROM passes pa JOIN users u ON u.id=pa.user_id WHERE u.email LIKE '%@petpaws.demo'
UNION ALL SELECT 'conversations', count(*) FROM conversations c JOIN users u ON u.id=c.initiator_id WHERE u.email LIKE '%@petpaws.demo'
UNION ALL SELECT 'messages',      count(*) FROM messages m JOIN conversations c ON c.id=m.conversation_id JOIN users u ON u.id=c.initiator_id WHERE u.email LIKE '%@petpaws.demo'
UNION ALL SELECT 'reports',       count(*) FROM reports r JOIN users u ON u.id=r.reporter_id WHERE u.email LIKE '%@petpaws.demo';
