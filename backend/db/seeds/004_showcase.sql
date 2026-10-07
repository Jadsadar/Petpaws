-- =============================================================================
-- 004_showcase.sql — ชุดข้อมูลสาธิต "สมจริง ครอบคลุมทุกเคส" 20 บัญชี / 45 ประกาศ
--
-- ข้อมูลแต่ละตารางเขียนเป็น VALUES ก้อนเดียว อ้างกันด้วย username / ชื่อสัตว์ (ไม่ซ้ำในชุดนี้) แก้ตรงนี้ได้เลย
-- รันซ้ำได้ไม่พัง: ลบเฉพาะบัญชี @petpaws.showcase (และทุกอย่างที่ผูกกับบัญชีพวกนี้) ก่อนใส่ใหม่เสมอ
--
-- รันบนเครื่อง (จากโฟลเดอร์ backend/):
--   docker exec -i petpaws-postgres psql -U petpaws -d petpaws -v ON_ERROR_STOP=1 < db/seeds/004_showcase.sql
--
-- รันบน production (คนที่มีกุญแจ .pem — สำรองฐานข้อมูลก่อนเสมอ):
--   docker exec -i petpaws-postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1' < 004_showcase.sql
--
-- ล็อกอิน: ชื่อผู้ใช้ตามรายการด้านล่าง (หรืออีเมล <ชื่อผู้ใช้>@petpaws.showcase)
--   รหัสผ่านเหมือนกันทุกบัญชี — ในไฟล์นี้เก็บแค่ argon2 hash ส่วนรหัสจริงแจกในทีมทางอื่น
--   (ต่างจาก 003 ที่ใช้รหัสสาธารณะ Petpaws1! — ไฟล์นี้ตั้งใจให้ขึ้น production ได้)
--
-- ลบชุดนี้ทิ้งทั้งหมด (ไม่แตะข้อมูลผู้ใช้จริง):
--   BEGIN;
--   DELETE FROM conversations WHERE initiator_id IN (SELECT id FROM users WHERE email LIKE '%@petpaws.showcase')
--                                OR owner_id     IN (SELECT id FROM users WHERE email LIKE '%@petpaws.showcase');
--   DELETE FROM pets  WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@petpaws.showcase');
--   DELETE FROM users WHERE email LIKE '%@petpaws.showcase';
--   COMMIT;
--
-- เคสที่ครอบคลุม:
--   ชนิด     : หมา 15, แมว 13, กระต่าย 5, นก 4, ปลา 3, อื่น ๆ 5 (แฮมสเตอร์ เต่า ชูการ์ไกลเดอร์ เม่นแคระ แกสบี้)
--   เพศ      : ผู้ / เมีย / ไม่ทราบ (เต่าเด็ก ปลาทอง ปลาหมอสี)
--   ขนาด     : เล็ก / กลาง / ใหญ่ / ไม่ระบุ
--   อายุ     : ลูกสัตว์ 2 เดือน → สูงวัย 12 ปี และ "ไม่ทราบอายุ"
--   วัคซีน/หมัน: ครบทั้ง 4 แบบ (ครบ / วัคซีนอย่างเดียว / หมันอย่างเดียว / ไม่มีทั้งคู่)
--   สถานะ    : ว่าง / pending (กำลังคุย ไม่อยู่ใน deck) / ได้บ้านแล้ว / ยกเลิกประกาศ
--   รูป      : 1 รูป ถึง 5 รูป · ผู้ใช้ทุกคนมีรูปโปรไฟล์ · นิสัยครบ 10 แท็ก · ครบ 6 ภาค · ครบ 4 ประเภทที่พัก
--   แชท 8 ห้อง: อ่านแล้ว / ยังไม่อ่าน / มีรูปในแชท / ห้องที่ปิดเพราะได้บ้านแล้ว / ปิดเพราะยกเลิกประกาศ
--   ถูกใจ/ปัดผ่าน กระจายให้บางตัวยอดถูกใจเยอะ บางตัวไม่มีเลย · รายงาน 2 รายการ (ยังไม่ถึงเกณฑ์ซ่อน)
--
-- รูปทั้งหมดเป็น URL สาธารณะที่เลือกด้วยตาแล้วว่าตรงชนิด/สายพันธุ์ (เหมือน 003):
--   หมา dog.ceo · แมว TheCatAPI / Wikimedia Commons · สัตว์อื่น Wikimedia Commons · คน randomuser.me
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---------- ล้างชุดเดิม ----------
-- conversations อ้าง users/pets แบบ RESTRICT จึงต้องลบก่อน (messages ลบตามแบบ CASCADE)
-- รวมห้องที่ผู้ใช้จริงทักมาหาสัตว์ในชุดนี้ด้วย — ตอนลบชุด ห้องพวกนั้นต้องหายไปพร้อมกัน
DELETE FROM conversations WHERE initiator_id IN (SELECT id FROM users WHERE email LIKE '%@petpaws.showcase')
                             OR owner_id     IN (SELECT id FROM users WHERE email LIKE '%@petpaws.showcase');
DELETE FROM pets  WHERE owner_id IN (SELECT id FROM users WHERE email LIKE '%@petpaws.showcase');
DELETE FROM users WHERE email LIKE '%@petpaws.showcase';

-- ---------- ผู้ใช้ 20 คน (14 คนลงประกาศ / 6 คนมองหาสัตว์เลี้ยง) ----------
-- ยืนยันอีเมลและกรอกโปรไฟล์ครบแล้ว = ล็อกอินแล้วเข้าหน้าหลักทันที
INSERT INTO users (username, email, password_hash, display_name, avatar_url, location, home_type, bio,
                   email_verified_at, profile_completed_at, created_at)
SELECT v.username, v.username || '@petpaws.showcase', pw.hash, v.display_name, v.avatar_url, v.location,
       v.home_type::home_type, v.bio, now() - make_interval(days => v.days), now() - make_interval(days => v.days),
       now() - make_interval(days => v.days)
FROM (VALUES
  ('baanaunrak', 'บ้านอุ่นไอรัก (กลุ่มช่วยหมาแมวจร)', 'https://images.dog.ceo/breeds/mix/louisa.jpg', 'กรุงเทพมหานคร', 'detached_house',
   'กลุ่มอาสาเล็ก ๆ ย่านลาดพร้าว เก็บหมาแมวจรมาทำหมัน ฉีดวัคซีน แล้วหาบ้านให้ ทุกตัวมีประวัติการรักษาส่งต่อให้ผู้รับเลี้ยง', 120),
  ('nun.cm', 'นุ่น ศรีวงศ์', 'https://randomuser.me/api/portraits/women/2.jpg', 'เชียงใหม่', 'townhouse',
   'ครูประถมที่เชียงใหม่ เลี้ยงแมวมาตั้งแต่เด็ก ตอนนี้มีแมวเยอะเกินกว่าจะดูแลได้ดี เลยอยากหาบ้านดี ๆ ให้บางตัว', 95),
  ('kitti.kk', 'กิตติ ทองมา', 'https://randomuser.me/api/portraits/men/4.jpg', 'ขอนแก่น', 'detached_house',
   'ทำสวนยางอยู่ขอนแก่น บ้านมีลานกว้าง เลี้ยงหมาไทยมาหลายรุ่น', 210),
  ('ploy.nb', 'พลอย อินทร์แก้ว', 'https://randomuser.me/api/portraits/women/17.jpg', 'นนทบุรี', 'condo',
   'กำลังจะย้ายไปเรียนต่อต่างประเทศปลายปีนี้ ต้องหาบ้านใหม่ให้เด็ก ๆ ที่เลี้ยงไว้ในคอนโด ขอคนที่รักจริงเท่านั้นนะคะ', 60),
  ('aun.chon', 'อรรถพล แสงทอง', 'https://randomuser.me/api/portraits/men/26.jpg', 'ชลบุรี', 'townhouse',
   'วิศวกรโรงงานที่ชลบุรี บริษัทย้ายผมไปประจำต่างจังหวัดที่ต้องอยู่หอพัก เลี้ยงหมาตัวใหญ่ต่อไม่ได้แล้วครับ', 45),
  ('jane.phuket', 'เจน สุขใจ', 'https://randomuser.me/api/portraits/women/27.jpg', 'ภูเก็ต', 'condo',
   'ทำงานโรงแรมที่ภูเก็ต ให้อาหารแมวแถวที่ทำงานจนมีแมวมาฝากท้องประจำ ช่วยหาบ้านให้ทีละตัว', 80),
  ('hatyai.rescue', 'ใจดีช่วยสัตว์หาดใหญ่', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/3/35/Orange_tabby_cat-932269.jpg/960px-Orange_tabby_cat-932269.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 'สงขลา', 'detached_house',
   'อาสาช่วยสัตว์จรในหาดใหญ่ รับแจ้งสัตว์ถูกทิ้ง รักษา ทำหมัน แล้วหาบ้านถาวรให้ ไม่มีค่าใช้จ่ายในการรับเลี้ยง', 300),
  ('mint.bunny', 'มิ้นท์ วงศ์ไทย', 'https://randomuser.me/api/portraits/women/42.jpg', 'ราชบุรี', 'detached_house',
   'เลี้ยงกระต่ายมา 8 ปี ตอนนี้มีหลายตัวจนดูแลไม่ทั่วถึง ยินดีสอนวิธีเลี้ยงให้มือใหม่ก่อนรับไปค่ะ', 150),
  ('ton.bird', 'ต้น นกน้อย', 'https://randomuser.me/api/portraits/men/90.jpg', 'นครราชสีมา', 'detached_house',
   'เลี้ยงนกแก้วและนกเล็กมานาน ต้องย้ายไปดูแลพ่อแม่ที่กรุงเทพฯ เลยหาบ้านให้นกบางตัว ยินดีแถมกรงและอุปกรณ์', 70),
  ('beam.aqua', 'บีม อควา', 'https://randomuser.me/api/portraits/men/92.jpg', 'สุพรรณบุรี', 'apartment',
   'นักศึกษาที่ชอบเลี้ยงปลาสวยงาม ห้องเช่าเล็กลงเลยต้องลดจำนวนตู้ ปลาทุกตัวแข็งแรงดี', 30),
  ('may.exotic', 'เมย์ ชอบสัตว์แปลก', 'https://randomuser.me/api/portraits/women/48.jpg', 'เชียงราย', 'townhouse',
   'สัตวแพทย์ฝึกหัดที่ชอบสัตว์เลี้ยงแปลก ๆ หาบ้านให้สัตว์ที่คนเลี้ยงแล้วไม่ไหว ก่อนรับไปจะคุยเรื่องการดูแลละเอียดนะคะ', 110),
  ('ple.surat', 'เปิ้ล แม่หมา', 'https://randomuser.me/api/portraits/women/51.jpg', 'สุราษฎร์ธานี', 'detached_house',
   'ช่วยคุณแม่ดูแลหมาที่บ้าน ตอนนี้คุณแม่อายุมากแล้วเลี้ยงไม่ไหวทุกตัว เลยต้องหาบ้านที่อบอุ่นให้บางตัวค่ะ', 65),
  ('nat.buriram', 'ณัฐ เทาเงิน', 'https://randomuser.me/api/portraits/women/60.jpg', 'บุรีรัมย์', 'detached_house',
   'รักแมวไทยเป็นพิเศษ เคยช่วยหาบ้านให้แมวไปแล้วกว่า 30 ตัว ส่งรูปอัปเดตให้กันตลอด', 400),
  ('golf.rayong', 'กอล์ฟ ใส่ใจ', 'https://randomuser.me/api/portraits/men/37.jpg', 'ระยอง', 'condo',
   'อยู่คอนโดที่ระยอง ทำงานกะดึกบ่อยจนไม่ค่อยมีเวลาให้น้อง ๆ อยากได้บ้านที่มีคนอยู่ด้วยทั้งวัน', 55),
  ('fah.bkk', 'ฟ้า อยากมีน้อง', 'https://randomuser.me/api/portraits/women/70.jpg', 'กรุงเทพมหานคร', 'condo',
   'ทำงานที่บ้านเป็นหลัก อยากได้แมวสักตัวมาเป็นเพื่อน คอนโดอนุญาตให้เลี้ยงสัตว์แล้วค่ะ', 20),
  ('prae.family', 'แพร ครอบครัวสุขสันต์', 'https://randomuser.me/api/portraits/women/78.jpg', 'นนทบุรี', 'detached_house',
   'บ้านมีลูกสองคน (7 ขวบกับ 10 ขวบ) และสนามหญ้าหลังบ้าน กำลังมองหาหมาที่เข้ากับเด็กได้ดี', 25),
  ('tee.runner', 'ตี๋ วิ่งเช้า', 'https://randomuser.me/api/portraits/men/45.jpg', 'ชลบุรี', 'townhouse',
   'ชอบวิ่งตอนเช้าและเดินป่า อยากได้หมาพลังเยอะที่ไปวิ่งด้วยกันได้ทุกวัน', 15),
  ('nok.retired', 'คุณนก วัยเกษียณ', 'https://randomuser.me/api/portraits/women/85.jpg', 'เชียงใหม่', 'detached_house',
   'เพิ่งเกษียณจากราชการ อยู่บ้านทั้งวัน อยากรับเลี้ยงสัตว์สูงวัยที่ไม่ค่อยมีใครรับ ให้เขาได้มีบ้านช่วงบั้นปลาย', 40),
  ('puk.kk', 'ปุ๊ก นักศึกษา', 'https://randomuser.me/api/portraits/women/80.jpg', 'ขอนแก่น', 'apartment',
   'นักศึกษาปี 3 อยู่หอที่อนุญาตสัตว์เล็ก อยากเลี้ยงกระต่ายหรือแฮมสเตอร์ เคยเลี้ยงแฮมสเตอร์มาก่อน', 10),
  ('kai.phuket', 'ไข่มุก มือใหม่หัดเลี้ยง', 'https://randomuser.me/api/portraits/women/12.jpg', 'ภูเก็ต', 'condo',
   'ไม่เคยเลี้ยงสัตว์มาก่อนแต่ศึกษาข้อมูลมาเยอะแล้ว อยากเริ่มจากแมวโตที่นิสัยเรียบร้อย', 35)
) AS v(username, display_name, avatar_url, location, home_type, bio, days)
CROSS JOIN (SELECT '$argon2id$v=19$m=65536,p=4,t=3$pM4E77GtPOqntcdi/K431Q$TBuE4XXqMowd1wDhyJ5wFiSF9XgnSUeWg0+gUrH4vuU'::text AS hash) pw;

-- ข้อมูลติดต่อ: ไม่ใส่เบอร์โทร (กันเบอร์ปลอมไปตรงกับเบอร์คนจริง) ใส่แค่ LINE/Facebook ที่ขึ้นต้นด้วย sc.
INSERT INTO user_contacts (user_id, line_id, fb_name)
SELECT u.id, 'sc.' || v.line_id, u.display_name FROM (VALUES
  ('baanaunrak', 'baanaunrak.rescue'),
  ('nun.cm', 'nun.sriwong'),
  ('kitti.kk', 'kitti.tm'),
  ('ploy.nb', 'ploy.ink'),
  ('aun.chon', 'aun.st'),
  ('jane.phuket', 'jane.sj'),
  ('hatyai.rescue', 'hatyai.rescue'),
  ('mint.bunny', 'mint.bunnyhouse'),
  ('ton.bird', 'ton.birdhouse'),
  ('beam.aqua', 'beam.aqua'),
  ('may.exotic', 'may.exoticpets'),
  ('ple.surat', 'ple.dogmom'),
  ('nat.buriram', 'nat.cats'),
  ('golf.rayong', 'golf.ss'),
  ('fah.bkk', 'fah.wfh'),
  ('prae.family', 'prae.family'),
  ('tee.runner', 'tee.run'),
  ('nok.retired', 'nok.retired'),
  ('puk.kk', 'puk.std'),
  ('kai.phuket', 'kai.mook')
) AS v(username, line_id) JOIN users u ON u.username = v.username;

INSERT INTO user_traits (user_id, trait_id)
SELECT u.id, t.id FROM (VALUES
  ('baanaunrak', 'social'),
  ('baanaunrak', 'kid_friendly'),
  ('nun.cm', 'quiet'),
  ('nun.cm', 'affectionate'),
  ('kitti.kk', 'energetic'),
  ('kitti.kk', 'independent'),
  ('ploy.nb', 'tidy'),
  ('ploy.nb', 'quiet'),
  ('aun.chon', 'energetic'),
  ('aun.chon', 'social'),
  ('jane.phuket', 'foodie'),
  ('jane.phuket', 'chill'),
  ('hatyai.rescue', 'kid_friendly'),
  ('hatyai.rescue', 'affectionate'),
  ('mint.bunny', 'tidy'),
  ('mint.bunny', 'chill'),
  ('ton.bird', 'talkative'),
  ('ton.bird', 'social'),
  ('beam.aqua', 'quiet'),
  ('beam.aqua', 'independent'),
  ('may.exotic', 'independent'),
  ('may.exotic', 'talkative'),
  ('ple.surat', 'kid_friendly'),
  ('ple.surat', 'energetic'),
  ('nat.buriram', 'affectionate'),
  ('nat.buriram', 'tidy'),
  ('golf.rayong', 'chill'),
  ('golf.rayong', 'foodie'),
  ('fah.bkk', 'quiet'),
  ('fah.bkk', 'affectionate'),
  ('prae.family', 'kid_friendly'),
  ('prae.family', 'social'),
  ('tee.runner', 'energetic'),
  ('tee.runner', 'independent'),
  ('nok.retired', 'chill'),
  ('nok.retired', 'quiet'),
  ('puk.kk', 'tidy'),
  ('puk.kk', 'foodie'),
  ('kai.phuket', 'tidy'),
  ('kai.phuket', 'chill')
) AS v(username, slug) JOIN users u ON u.username = v.username JOIN traits t ON t.slug = v.slug;

-- ---------- ประกาศ 45 ตัว ----------
-- จังหวัดของสัตว์ = จังหวัดของเจ้าของเสมอ (ดึงจาก users ไม่พิมพ์ซ้ำ)
-- ใส่ทุกตัวเป็น available ก่อน แล้วค่อยเปลี่ยนสถานะทีหลัง ให้ trigger ปิดห้องแชทและใส่ข้อความระบบเองเหมือนของจริง
INSERT INTO pets (owner_id, name, species, species_other, breed, age_label, age_months, sex, size,
                  vaccinated, neutered, weight_kg, description, location, created_at)
SELECT u.id, v.name, v.species::pet_species, v.species_other, v.breed, v.age_label, v.age_months,
       v.sex::pet_sex, v.size::pet_size, v.vaccinated, v.neutered, v.weight_kg, v.description, u.location,
       now() - make_interval(hours => v.hours)
FROM (VALUES
  ('ข้าวตัง', 'baanaunrak', 'dog', NULL, 'พันทาง', '2 ปี', 24, 'female', 'medium', true, true, 14.5,
   'ข้าวตังถูกทิ้งไว้หน้าวัดตอนอายุไม่กี่เดือน ตอนนี้โตเป็นสาวร่าเริง ทำหมันและฉีดวัคซีนครบแล้ว เดินสายจูงเก่ง เล่นกับเด็กได้ดีมาก เหมาะกับบ้านที่มีพื้นที่ให้วิ่งเล่นและมีเวลาพาเดินเล่นทุกวัน', 20),
  ('ลุงหนวด', 'baanaunrak', 'dog', NULL, 'พันทาง', '10 ปี', 120, 'male', 'medium', true, true, 18.0,
   'ลุงหนวดเป็นหมาสูงวัยที่เจ้าของเดิมเสียชีวิต นิสัยใจดีมาก ชอบนอนเฝ้าหน้าบ้านเงียบ ๆ ไม่เห่าเสียงดัง ตรวจเลือดแล้วสุขภาพดีตามวัย มีข้อเข่าเสื่อมนิดหน่อย กินอาหารเม็ดสำหรับหมาสูงวัย อยากให้ลุงได้มีบ้านอบอุ่นในช่วงบั้นปลายครับ', 216),
  ('ลูกชิ้น', 'baanaunrak', 'dog', NULL, 'พันทาง', 'ไม่ทราบอายุ (คาดว่าโตเต็มวัย)', NULL, 'male', 'medium', false, true, 16.0,
   'ลูกชิ้นเป็นหมาจรที่อยู่แถวตลาดมานาน ทำหมันในโครงการจับทำหมันแล้วปล่อย (มีรอยตัดปลายหู) ไม่ทราบอายุแน่ชัด หมอดูฟันแล้วคาดว่าโตเต็มวัย ยังไม่มีประวัติวัคซีน จะพาไปฉีดก่อนส่งมอบ ช่วงแรกจะขี้ระแวงคนแปลกหน้า แต่พอคุ้นแล้วติดคนมาก', 96),
  ('ถั่วดำ', 'baanaunrak', 'dog', NULL, 'พันทาง', '5 เดือน', 5, 'male', 'small', true, false, 6.2,
   'ถั่วดำเป็นลูกหมาตัวสุดท้ายจากครอกที่เก็บมาจากไซต์ก่อสร้าง ได้วัคซีนเข็มแรกกับเข็มสองแล้ว ซนมาก ชอบกัดรองเท้า ต้องการคนที่มีเวลาฝึกเรื่องขับถ่ายและคำสั่งพื้นฐาน ยังไม่ทำหมันเพราะอายุยังน้อย', 6),
  ('ถ่าน', 'baanaunrak', 'cat', NULL, 'พันทาง', '3 ปี', 36, 'male', 'medium', true, true, 4.8,
   'ถ่านเป็นแมวดำตาเหลืองที่รออยู่ในศูนย์นานที่สุด เพราะหลายคนไม่อยากได้แมวดำ ทั้งที่จริงเป็นแมวขี้อ้อนที่สุดในบ้าน ชอบนอนตักและคลอเคลียขาเวลาหิว ใช้กระบะทรายเป็น เข้ากับแมวตัวอื่นได้', 288),
  ('สามสี', 'nun.cm', 'cat', NULL, 'พันทาง (ลายสามสี)', '3 ปี', 36, 'female', 'small', true, true, 3.7,
   'สามสีเป็นแมวลายสามสีที่ชอบสำรวจสวนหลังบ้าน นิสัยค่อนข้างรักอิสระ ไม่ชอบถูกอุ้มนาน ๆ แต่จะมานอนข้าง ๆ เวลาเราทำงาน ทำหมันแล้ว เหมาะกับบ้านที่ไม่มีเด็กเล็ก', 30),
  ('ยายจ๋า', 'nun.cm', 'cat', NULL, 'พันทางขนยาว', '12 ปี', 144, 'female', 'small', true, true, 3.2,
   'ยายจ๋าอยู่กับครอบครัวมา 12 ปี ตอนนี้ไตเริ่มทำงานช้าลงตามวัย ต้องกินอาหารสูตรโรคไต และตรวจเลือดทุก 6 เดือน (มีประวัติการรักษาให้ทั้งหมด) นิสัยนิ่ง ชอบนอนอาบแดด อยากได้บ้านที่ใจเย็นและมีคนอยู่บ้านเป็นหลัก', 360),
  ('ขุนแผน', 'kitti.kk', 'dog', NULL, 'ไทยหลังอาน', '3 ปี', 36, 'male', 'large', true, true, 26.0,
   'ขุนแผนเป็นหมาไทยหลังอานสีแดงแท้ แข็งแรง ฉลาด และหวงบ้านมาก เหมาะกับบ้านที่มีรั้วรอบขอบชิด ต้องการเจ้าของที่เคยเลี้ยงหมาใหญ่มาก่อนและพาออกกำลังกายวันละอย่างน้อยหนึ่งชั่วโมง ไม่เหมาะกับบ้านที่มีแมวหรือสัตว์เล็ก', 40),
  ('บราวนี่', 'kitti.kk', 'dog', NULL, 'ลาบราดอร์ รีทรีฟเวอร์ (สีช็อกโกแลต)', '1 ปี 8 เดือน', 20, 'male', 'large', true, true, 30.5,
   'บราวนี่ได้บ้านใหม่ที่อุดรฯ เรียบร้อยแล้ว เจ้าของใหม่ส่งรูปมาให้ดูทุกอาทิตย์ ขอบคุณทุกคนที่สนใจครับ', 840),
  ('มะลิ', 'ploy.nb', 'cat', NULL, 'ขาวมณี', '2 ปี', 24, 'female', 'small', true, true, 3.4,
   'มะลิเป็นแมวขาวมณีตาสองสี (ฟ้ากับเหลือง) ช่างคุยมาก เรียกชื่อแล้วจะร้องตอบทุกครั้ง อยู่คอนโดมาตั้งแต่เด็กจึงไม่ต้องการพื้นที่กว้าง ทำหมันและฉีดวัคซีนครบ มีสมุดวัคซีนให้', 10),
  ('ถั่วเขียว', 'ploy.nb', 'rabbit', NULL, 'เนเธอร์แลนด์ดวาร์ฟ', '1 ปี', 12, 'male', 'small', false, false, 1.1,
   'ถั่วเขียวเป็นกระต่ายแคระสีเทา ตัวเล็กมาก เงียบ เหมาะกับคอนโด ขับถ่ายในกระบะเป็นที่ กินหญ้าทิโมธีเป็นหลักกับผักสดวันละนิด แถมกรงและขวดน้ำให้ด้วย', 26),
  ('ข้าวโพด', 'ploy.nb', 'other', 'แฮมสเตอร์', 'ซีเรียน (สีทอง)', '8 เดือน', 8, 'female', 'small', false, false, 0.15,
   'ข้าวโพดเป็นแฮมสเตอร์ซีเรียนสีทอง ตื่นตอนกลางคืนเป็นหลัก ไม่ชอบอยู่รวมกับแฮมสเตอร์ตัวอื่น ต้องเลี้ยงเดี่ยว ชอบวิ่งจักร ยกกรงใหญ่พร้อมจักรและบ้านไม้ให้ทั้งชุดค่ะ', 26),
  ('หิมะ', 'aun.chon', 'dog', NULL, 'ไซบีเรียน ฮัสกี้', '5 ปี', 60, 'female', 'large', true, true, 22.0,
   'หิมะเป็นฮัสกี้ช่างคุย ชอบหอนเวลาได้ยินเสียงเพลง เป็นมิตรกับคนและหมาตัวอื่น ต้องอยู่ห้องแอร์ช่วงกลางวันเพราะขนหนา และต้องพาวิ่งออกกำลังทุกวัน ตอนนี้มีผู้สนใจคุยรายละเอียดอยู่ครับ', 144),
  ('ปั๊กกี้', 'aun.chon', 'dog', NULL, 'ปั๊ก', '8 ปี', 96, 'male', 'small', true, true, 8.5,
   'ปั๊กกี้เป็นปั๊กสูงวัยนิสัยดี ชอบนอนกรนเสียงดัง ไม่ทนร้อน ต้องอยู่ในห้องแอร์ คุมน้ำหนักอยู่เพราะกินเก่งมาก เหมาะกับคนที่อยู่บ้านเป็นหลักและไม่ต้องพาออกกำลังหนัก', 480),
  ('ส้มซ่า', 'jane.phuket', 'cat', NULL, 'พันทาง (แมวส้ม)', '1 ปี', 12, 'male', 'medium', true, true, 4.6,
   'ส้มซ่าเป็นแมวส้มที่มาขออาหารหน้าโรงแรมทุกเย็นจนคุ้นคน ไม่กลัวคนแปลกหน้าเลย ทำหมันและฉีดวัคซีนครบแล้ว กินเก่งตามสไตล์แมวส้ม ต้องคุมอาหารนิดหน่อย', 8),
  ('ทองแท่ง', 'jane.phuket', 'cat', NULL, 'พันทาง (ส้มขาว)', '3 ปี', 36, 'male', 'medium', true, true, 5.0,
   'ทองแท่งได้บ้านใหม่ที่ภูเก็ตแล้วค่ะ เจ้าของใหม่เป็นมือใหม่ที่ตั้งใจมาก ขอบคุณทุกคนที่ทักมานะคะ', 432),
  ('ข้าวปั้น', 'hatyai.rescue', 'cat', NULL, 'พันทาง', '2 เดือน', 2, 'female', 'small', true, false, 0.9,
   'ข้าวปั้นถูกทิ้งไว้ในกล่องหน้าร้านสะดวกซื้อพร้อมพี่น้อง ตอนนี้กินอาหารเม็ดเองได้แล้ว ได้วัคซีนเข็มแรก นัดเข็มสองอีก 3 อาทิตย์ (ผู้รับเลี้ยงต้องพาไปฉีดต่อ) ซนมาก วิ่งเล่นทั้งวัน ยังไม่ทำหมันเพราะอายุยังน้อย ทางกลุ่มมีคูปองทำหมันฟรีให้เมื่อครบ 6 เดือน', 4),
  ('เสือน้อย', 'hatyai.rescue', 'cat', NULL, 'พันทาง (ลายเสือ)', '4 ปี', 48, 'male', 'medium', true, true, 5.3,
   'เสือน้อยเป็นแมวลายเสืออกขาวที่ถูกรถเฉี่ยวจนขาหลังหัก ตอนนี้รักษาหายดีแล้ว เดินได้ปกติ นิสัยสุภาพ ไม่ชอบเสียงดัง เหมาะกับบ้านที่เงียบ ๆ', 72),
  ('จิ๋ว', 'hatyai.rescue', 'dog', NULL, 'ชิวาวา', '3 ปี', 36, 'male', 'small', true, true, 2.1,
   'จิ๋วถูกทิ้งไว้ที่ปั๊มน้ำมันพร้อมกรง ตัวเล็กแต่ใจใหญ่ ชอบเห่าทักทายคนแปลกหน้า พอคุ้นแล้วจะขี้อ้อนมาก ติดเจ้าของ ไม่เหมาะกับบ้านที่มีเด็กเล็กเพราะตัวเปราะบาง', 48),
  ('ข้าวเหนียว', 'hatyai.rescue', 'dog', NULL, 'พันทาง (เชพเพิร์ดผสม)', '6 ปี', 72, 'female', 'large', true, true, 24.0,
   'ข้าวเหนียวเคยเป็นหมาเฝ้าโกดังที่ถูกปล่อยทิ้งตอนโกดังปิด นิสัยใจเย็นและฉลาดมาก ใส่สายจูงเดินเรียบร้อย อยู่กับเด็กได้ อยู่ในศูนย์มาเกือบเดือนแล้ว อยากให้มีคนเห็นเธอบ้าง', 600),
  ('ขนมครก', 'mint.bunny', 'rabbit', NULL, 'ฮอลแลนด์ลอป', '8 เดือน', 8, 'female', 'small', false, false, 1.6,
   'ขนมครกเป็นกระต่ายหูตกสีน้ำตาลส้ม ชอบให้ลูบหัว ไม่กัด เหมาะกับมือใหม่ ขับถ่ายเป็นที่แล้ว ขอคนที่ปล่อยให้วิ่งนอกกรงได้วันละอย่างน้อย 2 ชั่วโมง', 15),
  ('สำลี', 'mint.bunny', 'rabbit', NULL, 'ไลอ้อนเฮด', '2 ปี', 24, 'female', 'small', false, true, 1.5,
   'สำลีเป็นกระต่ายไลอ้อนเฮดขนฟูสีขาว ทำหมันแล้ว (ลดความเสี่ยงมะเร็งมดลูก) ต้องแปรงขนสัปดาห์ละ 2-3 ครั้งเพราะขนยาว เงียบและขี้อายนิดหน่อยในช่วงแรก', 120),
  ('โกโก้', 'mint.bunny', 'rabbit', NULL, 'เร็กซ์', '1 ปี 6 เดือน', 18, 'male', 'medium', false, false, 2.8,
   'โกโก้เป็นกระต่ายเร็กซ์ขนนุ่มเหมือนกำมะหยี่ สีช็อกโกแลต ตัวโตกว่ากระต่ายแคระ ชอบกินผักชีกับใบโหระพามาก เข้ากับกระต่ายตัวอื่นได้ถ้าค่อย ๆ แนะนำ', 192),
  ('ด่างดำ', 'mint.bunny', 'rabbit', NULL, 'พันทาง', '5 ปี', 60, 'male', 'medium', false, true, 2.4,
   'ด่างดำเป็นกระต่ายสูงวัย ลายจุดดำบนขนขาว ทำหมันแล้ว นิสัยนิ่ง ชอบนอนเหยียดยาว ฟันต้องตรวจทุก 3 เดือนเพราะเคยมีปัญหาฟันยาว อยากได้บ้านที่ดูแลกระต่ายสูงวัยเป็น', 528),
  ('ฟ้าใส', 'ton.bird', 'bird', NULL, 'หงส์หยก', '1 ปี', 12, 'male', 'small', false, false, 0.04,
   'ฟ้าใสเป็นนกหงส์หยกสีฟ้า ตัวผู้ (จมูกสีฟ้า) เชื่องมือ ขึ้นนิ้วได้ ร้องเพลงเก่ง เลียนเสียงคำง่าย ๆ ได้สองสามคำ แถมกรงพร้อมคอนให้', 12),
  ('ลูกพีช', 'ton.bird', 'bird', NULL, 'ค็อกคาเทล (ลูทิโน)', '2 ปี', 24, 'female', 'small', false, false, 0.09,
   'ลูกพีชเป็นค็อกคาเทลสีเหลืองแก้มส้ม ขี้อ้อน ชอบให้เกาหัว ผิวปากเป็นเพลงได้หนึ่งเพลง ต้องการเวลาออกมานอกกรงทุกวัน ไม่เหมาะกับบ้านที่ไม่ค่อยมีคนอยู่', 168),
  ('กีวี่', 'ton.bird', 'bird', NULL, 'เลิฟเบิร์ด (หน้ากุหลาบ)', '1 ปี 6 เดือน', 18, 'female', 'small', false, false, 0.05,
   'กีวี่ได้บ้านใหม่แล้วครับ ไปอยู่กับคู่ใหม่ที่บ้านผู้รับเลี้ยง ขอบคุณที่ช่วยแชร์ครับ', 720),
  ('มะม่วง', 'ton.bird', 'bird', NULL, 'ซันคอนัวร์', '4 ปี', 48, 'male', 'small', false, false, 0.11,
   'มะม่วงเป็นนกซันคอนัวร์สีเหลืองส้ม เสียงดังมากตอนเช้าและเย็น ไม่เหมาะกับคอนโดหรือหอพัก เชื่องมาก ชอบเกาะไหล่ ต้องการเจ้าของที่มีประสบการณ์เลี้ยงนกแก้ว', 240),
  ('บลูเบอร์รี่', 'beam.aqua', 'fish', NULL, 'ปลากัด (ฮาล์ฟมูน)', '6 เดือน', 6, 'male', 'small', false, false, NULL,
   'บลูเบอร์รี่เป็นปลากัดฮาล์ฟมูนสีน้ำเงินเข้ม หางแผ่สวยมาก ต้องเลี้ยงเดี่ยว เปลี่ยนน้ำสัปดาห์ละครั้ง ให้อาหารเม็ดวันละ 2 มื้อ แถมโหลและใบหูกวางแห้งให้', 18),
  ('หมวกแดง', 'beam.aqua', 'fish', NULL, 'ปลาทองออรันดา (หัวแดง)', '1 ปี', 12, 'unknown', 'small', false, false, NULL,
   'ขอยกเลิกประกาศก่อนนะครับ ช่วงนี้หมวกแดงมีอาการว่ายตะแคง กำลังรักษาอยู่ ไม่อยากส่งต่อตอนป่วย', 336),
  ('เฮงเฮง', 'beam.aqua', 'fish', NULL, 'ปลาหมอสี (ฟลาวเวอร์ฮอร์น)', '2 ปี', 24, 'unknown', 'medium', false, false, 0.6,
   'เฮงเฮงเป็นปลาหมอสีโหนกสวย สีแดงเข้ม จำหน้าเจ้าของได้และว่ายมาหาเวลาเข้าใกล้ตู้ ต้องเลี้ยงเดี่ยวในตู้อย่างน้อย 36 นิ้ว เพราะหวงถิ่นมาก รับเองที่สุพรรณบุรีเท่านั้น (ขนส่งปลาใหญ่เสี่ยง)', 144),
  ('ทองดี', 'may.exotic', 'other', 'เต่าบก', 'ซูคาต้า', '2 ปี', 24, 'unknown', NULL, false, false, 1.8,
   'ทองดีเป็นเต่าซูคาต้าวัยรุ่น ตอนนี้ยาวประมาณ 20 ซม. แต่โตเต็มที่จะใหญ่มาก (หนักได้หลายสิบกิโล) ต้องการบ้านที่มีสนามหญ้าและพื้นที่กว้างในระยะยาว กินหญ้าและผักเป็นหลัก อายุยืนหลายสิบปี กรุณาคิดให้ดีก่อนรับนะคะ ยังแยกเพศไม่ได้เพราะยังเล็ก', 96),
  ('ซูก้า', 'may.exotic', 'other', 'ชูการ์ไกลเดอร์', 'สีเทาธรรมชาติ (คลาสสิก)', '1 ปี', 12, 'female', NULL, false, false, 0.12,
   'ซูก้าเป็นชูการ์ไกลเดอร์ที่เจ้าของเดิมซื้อมาแล้วเลี้ยงไม่ไหว ตื่นกลางคืน ต้องการกรงสูงและเวลาเล่นด้วยทุกคืน ติดกลิ่นเจ้าของมาก ช่วงแรกจะส่งเสียงร้องเวลาตกใจ ขอคนที่ศึกษาเรื่องอาหารของชูการ์มาแล้ว', 72),
  ('หนามเตย', 'may.exotic', 'other', 'เม่นแคระ', 'แอฟริกันพิกมี่', '1 ปี', 12, 'male', 'small', false, false, 0.35,
   'หนามเตยเป็นเม่นแคระที่คุ้นมือแล้ว จับได้ไม่ม้วนตัว ต้องเลี้ยงในห้องที่อุณหภูมิไม่ต่ำกว่า 24 องศา กินอาหารแมวเกรดดีผสมหนอนนก เลี้ยงเดี่ยว', 216),
  ('หมูหยอง', 'may.exotic', 'other', 'หนูแกสบี้', 'อเมริกัน (สีทอง)', '1 ปี 3 เดือน', 15, 'male', 'small', false, false, 0.95,
   'หมูหยองเป็นแกสบี้สีทองช่างคุย ส่งเสียงวี๊ด ๆ ทุกครั้งที่ได้ยินเสียงถุงผัก ต้องการวิตามินซีจากผักสดทุกวัน เป็นสัตว์สังคม ถ้ามีเพื่อนแกสบี้ด้วยจะดีมาก', 264),
  ('ทองหยิบ', 'ple.surat', 'dog', NULL, 'โกลเด้น รีทรีฟเวอร์', '4 ปี', 48, 'female', 'large', true, true, 27.0,
   'ทองหยิบเป็นโกลเด้นที่อ่อนโยนที่สุดในบ้าน เด็ก ๆ ข้างบ้านมาเล่นด้วยทุกวัน ชอบว่ายน้ำ ขนร่วงเยอะต้องแปรงขนบ่อย ทำหมันและฉีดวัคซีนครบ มีประวัติตรวจสะโพกปกติ', 24),
  ('ขนมปัง', 'ple.surat', 'dog', NULL, 'เวลช์ คอร์กี้ เพมโบรก', '2 ปี', 24, 'male', 'medium', true, true, 12.0,
   'ขนมปังเป็นคอร์กี้ขาสั้นก้นเด้ง ร่าเริง ชอบไล่บอล ฉลาดสอนง่าย ห้ามให้ขึ้นลงบันไดบ่อยเพราะหลังยาว ตอนนี้มีครอบครัวที่สนใจนัดดูตัวแล้ว', 120),
  ('ส้มจี๊ด', 'ple.surat', 'dog', NULL, 'ปอมเมอเรเนียน', '7 ปี', 84, 'female', 'small', true, true, 2.8,
   'ส้มจี๊ดเป็นปอมสีส้มที่อยู่กับคุณแม่มาตั้งแต่เด็ก ติดคนมาก เห่าเก่งเวลามีคนมาหน้าบ้าน ฟันเริ่มไม่ค่อยดีตามวัย ขูดหินปูนไปเมื่อเดือนที่แล้ว ต้องการคนที่อยู่บ้านเป็นเพื่อนได้เยอะ', 384),
  ('เทาเทา', 'nat.buriram', 'cat', NULL, 'โคราช (สีสวาด)', '3 ปี', 36, 'male', 'medium', true, true, 4.2,
   'เทาเทาเป็นแมวสีสวาด (โคราช) ขนสีเทาเงินตาเขียว แมวมงคลของไทย นิสัยสุภาพ ผูกพันกับเจ้าของคนเดียว ไม่ชอบเสียงดัง เหมาะกับบ้านที่ไม่วุ่นวาย', 48),
  ('วุ้นเส้น', 'nat.buriram', 'cat', NULL, 'วิเชียรมาศ', '5 ปี', 60, 'female', 'small', true, true, 3.5,
   'วุ้นเส้นเป็นแมววิเชียรมาศตาสีฟ้า ช่างคุยและติดคนมาก จะเดินตามไปทุกห้อง ไม่ชอบอยู่คนเดียวนาน ๆ เหมาะกับคนทำงานที่บ้าน', 96),
  ('โมจิ', 'nat.buriram', 'cat', NULL, 'สก็อตติช โฟลด์', '1 ปี 6 เดือน', 18, 'female', 'small', true, true, 3.3,
   'โมจิเป็นสก็อตติชโฟลด์หูพับ ได้รับมาจากเจ้าของเดิมที่แพ้ขนแมว สายพันธุ์นี้มีโอกาสข้อต่อเสื่อม ตรวจเอกซเรย์ข้อแล้วยังปกติ แต่ต้องพาตรวจปีละครั้ง และไม่ควรให้กระโดดที่สูงบ่อย ๆ', 168),
  ('บัวลอย', 'nat.buriram', 'cat', NULL, 'เปอร์เซีย', '6 ปี', 72, 'male', 'medium', true, true, 4.9,
   'บัวลอยเป็นแมวเปอร์เซียขนยาวสีขาว นิ่งมาก ชอบนอนบนโซฟาทั้งวัน ต้องหวีขนทุกวันและอาบน้ำเดือนละครั้ง ต้องเช็ดคราบน้ำตาทุกวันตามสายพันธุ์ เหมาะกับคนที่มีเวลาดูแลขน', 312),
  ('ไส้กรอก', 'golf.rayong', 'dog', NULL, 'ดัชชุนด์', '4 ปี', 48, 'male', 'small', true, true, 7.0,
   'ไส้กรอกเป็นดัชชุนด์ขนสั้นสีดำแทน ชอบขุดผ้าห่มมุดนอน ห้ามอ้วนเพราะจะมีปัญหากระดูกสันหลัง ใช้แผ่นรองฉี่เป็น อยู่คอนโดได้ แต่ต้องมีคนอยู่ด้วยเพราะถ้าอยู่คนเดียวนานจะเห่า', 72),
  ('ปุยฝ้าย', 'golf.rayong', 'dog', NULL, 'ชิห์สุ', '6 ปี', 72, 'female', 'small', true, true, 5.5,
   'ขอยกเลิกประกาศครับ น้องสาวผมรับปุยฝ้ายไปเลี้ยงที่บ้านต่างจังหวัดแล้ว ขอบคุณที่ทักมาครับ', 504),
  ('เมฆ', 'golf.rayong', 'cat', NULL, 'เบอร์แมนผสม', '4 ปี', 48, 'male', 'large', true, true, 5.8,
   'เมฆเป็นแมวขนยาวแต้มสีหน้าดำ เท้าขาว ตาสีฟ้า ตัวใหญ่แต่ใจดี ไม่ข่วน ไม่กัด เข้ากับหมาได้เพราะโตมากับไส้กรอก ต้องหวีขนสัปดาห์ละหลายครั้ง', 192)
) AS v(name, owner, species, species_other, breed, age_label, age_months, sex, size,
       vaccinated, neutered, weight_kg, description, hours)
JOIN users u ON u.username = v.owner;

-- ตารางช่วยอ้างสัตว์ด้วยชื่อ (ชื่อไม่ซ้ำกันในชุดนี้) — หายไปเองตอน COMMIT
CREATE TEMP TABLE sc_pet ON COMMIT DROP AS
SELECT p.name, p.id, p.owner_id FROM pets p JOIN users u ON u.id = p.owner_id
WHERE u.email LIKE '%@petpaws.showcase';

-- รูปประกาศ: sort_order 0 = รูปปก · มี width/height จริงให้แอปจองพื้นที่ก่อนรูปโหลดเสร็จ
INSERT INTO pet_media (pet_id, storage_key, url, width, height, sort_order)
SELECT s.id, v.storage_key, v.url, v.width, v.height, v.sort_order FROM (VALUES
  ('ข้าวตัง', 'pets/showcase/p01_0.jpg', 'https://images.dog.ceo/breeds/mix/xeshabelka_(1).jpg', 623, 656, 0),
  ('ข้าวตัง', 'pets/showcase/p01_1.jpg', 'https://images.dog.ceo/breeds/mix/xeshabelka_(18).jpg', 960, 1280, 1),
  ('ข้าวตัง', 'pets/showcase/p01_2.jpg', 'https://images.dog.ceo/breeds/mix/xeshabelka_(3).jpg', 643, 526, 2),
  ('ข้าวตัง', 'pets/showcase/p01_3.jpg', 'https://images.dog.ceo/breeds/mix/xeshabelka_(16).jpg', 960, 1280, 3),
  ('ลุงหนวด', 'pets/showcase/p02_0.jpg', 'https://images.dog.ceo/breeds/mix/otis.jpg', 800, 1213, 0),
  ('ลูกชิ้น', 'pets/showcase/p03_0.jpg', 'https://images.dog.ceo/breeds/mix/brina_2014_italy.jpg', 1536, 2048, 0),
  ('ถั่วดำ', 'pets/showcase/p04_0.jpg', 'https://images.dog.ceo/breeds/mix/photo_2025-11-17_02-02-19.jpg', 972, 1280, 0),
  ('ถ่าน', 'pets/showcase/p05_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/69/Black_kitten_July_August_2009-1.jpg/960px-Black_kitten_July_August_2009-1.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 663, 0),
  ('สามสี', 'pets/showcase/p06_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b6/Calico_cat%2C_Lebanon_7.jpg/960px-Calico_cat%2C_Lebanon_7.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 0),
  ('สามสี', 'pets/showcase/p06_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/4f/Calico_cat%2C_Lebanon_6.jpg/960px-Calico_cat%2C_Lebanon_6.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 1),
  ('สามสี', 'pets/showcase/p06_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/cd/Calico_cat%2C_Lebanon_8.jpg/960px-Calico_cat%2C_Lebanon_8.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 2),
  ('สามสี', 'pets/showcase/p06_3.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/6b/Calico_cat%2C_Lebanon_4.jpg/960px-Calico_cat%2C_Lebanon_4.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 3),
  ('ยายจ๋า', 'pets/showcase/p07_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c9/Vecchio_gatto_su_sedia_2014_%28cropped%29.JPG/960px-Vecchio_gatto_su_sedia_2014_%28cropped%29.JPG?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1053, 0),
  ('ยายจ๋า', 'pets/showcase/p07_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/7/72/Vecchio_gatto_su_sedia.JPG/960px-Vecchio_gatto_su_sedia.JPG?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 1),
  ('ขุนแผน', 'pets/showcase/p08_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/44/Thai_ridgeback_t444.jpg/960px-Thai_ridgeback_t444.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 846, 0),
  ('ขุนแผน', 'pets/showcase/p08_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b8/Thai_ridgeback_ter444.jpg/960px-Thai_ridgeback_ter444.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 953, 1),
  ('ขุนแผน', 'pets/showcase/p08_2.jpg', 'https://upload.wikimedia.org/wikipedia/commons/f/f5/Thajsky-ridgeback-moonbarks1.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail_unscaled', 664, 1000, 2),
  ('ขุนแผน', 'pets/showcase/p08_3.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1b/Thai_ridgeback_terzz444.jpg/960px-Thai_ridgeback_terzz444.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1516, 3),
  ('บราวนี่', 'pets/showcase/p09_0.jpg', 'https://images.dog.ceo/breeds/labrador/n02099712_5689.jpg', 500, 334, 0),
  ('บราวนี่', 'pets/showcase/p09_1.jpg', 'https://images.dog.ceo/breeds/labrador/toblerone_2.jpg', 1280, 960, 1),
  ('มะลิ', 'pets/showcase/p10_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/18/Khao_Manee_deux_h%C3%A9t%C3%A9rochromies.jpg/960px-Khao_Manee_deux_h%C3%A9t%C3%A9rochromies.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1093, 0),
  ('มะลิ', 'pets/showcase/p10_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a1/Khao_Manee_Lily.jpg/960px-Khao_Manee_Lily.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 640, 1),
  ('มะลิ', 'pets/showcase/p10_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/47/Khao_Manee_2_%22Gally%22.jpg/960px-Khao_Manee_2_%22Gally%22.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1057, 2),
  ('ถั่วเขียว', 'pets/showcase/p11_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/9d/HI3A0028.jpg/960px-HI3A0028.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 0),
  ('ถั่วเขียว', 'pets/showcase/p11_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/44/GreyNetherlandsDwarf.jpg/960px-GreyNetherlandsDwarf.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 1),
  ('ถั่วเขียว', 'pets/showcase/p11_2.jpg', 'https://upload.wikimedia.org/wikipedia/commons/7/75/%D0%9D%D0%B8%D0%B4%D0%B5%D1%80%D0%BB%D0%B0%D0%BD%D0%B4%D1%81%D0%BA%D0%B8%D0%B9_%D0%BA%D0%B0%D1%80%D0%BB%D0%B8%D0%BA%D0%BE%D0%B2%D1%8B%D0%B9_%D0%BA%D1%80%D0%BE%D0%BB%D0%B8%D0%BA_%D0%B3%D0%BE%D0%BB%D1%83%D0%B1%D0%BE%D0%B3%D0%BE_%D0%BE%D0%BA%D1%80%D0%B0%D1%81%D0%B0.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail_unscaled', 687, 630, 2),
  ('ข้าวโพด', 'pets/showcase/p12_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/f/f5/Syrian_hamster_on_blanket.jpg/960px-Syrian_hamster_on_blanket.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1214, 0),
  ('ข้าวโพด', 'pets/showcase/p12_1.jpg', 'https://upload.wikimedia.org/wikipedia/commons/5/5a/A_pet_hamster_named_Peach.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail_unscaled', 882, 581, 1),
  ('ข้าวโพด', 'pets/showcase/p12_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/db/Mesocricetus_auratus_-pet_hamster-8a.jpg/960px-Mesocricetus_auratus_-pet_hamster-8a.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 638, 2),
  ('หิมะ', 'pets/showcase/p13_0.jpg', 'https://images.dog.ceo/breeds/husky/n02110185_248.jpg', 500, 375, 0),
  ('หิมะ', 'pets/showcase/p13_1.jpg', 'https://images.dog.ceo/breeds/husky/n02110185_9855.jpg', 360, 331, 1),
  ('หิมะ', 'pets/showcase/p13_2.jpg', 'https://images.dog.ceo/breeds/husky/n02110185_2941.jpg', 500, 358, 2),
  ('หิมะ', 'pets/showcase/p13_3.jpg', 'https://images.dog.ceo/breeds/husky/n02110185_3406.jpg', 438, 500, 3),
  ('ปั๊กกี้', 'pets/showcase/p14_0.jpg', 'https://images.dog.ceo/breeds/pug/n02110958_11958.jpg', 500, 399, 0),
  ('ปั๊กกี้', 'pets/showcase/p14_1.jpg', 'https://images.dog.ceo/breeds/pug/n02110958_353.jpg', 375, 500, 1),
  ('ปั๊กกี้', 'pets/showcase/p14_2.jpg', 'https://images.dog.ceo/breeds/pug/n02110958_13439.jpg', 500, 375, 2),
  ('ปั๊กกี้', 'pets/showcase/p14_3.jpg', 'https://images.dog.ceo/breeds/pug/n02110958_14017.jpg', 405, 500, 3),
  ('ส้มซ่า', 'pets/showcase/p15_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/aa/Orange_tabby_cat_seated.jpg/960px-Orange_tabby_cat_seated.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 718, 0),
  ('ส้มซ่า', 'pets/showcase/p15_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/03/Orange_tabby_cat_licc.jpg/960px-Orange_tabby_cat_licc.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 719, 1),
  ('ส้มซ่า', 'pets/showcase/p15_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/49/Orange_tabby_cat_%281%29.jpg/960px-Orange_tabby_cat_%281%29.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 719, 2),
  ('ทองแท่ง', 'pets/showcase/p16_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/68/Orange_tabby_cat_sitting_on_fallen_leaves-Hisashi-01A.jpg/960px-Orange_tabby_cat_sitting_on_fallen_leaves-Hisashi-01A.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 0),
  ('ทองแท่ง', 'pets/showcase/p16_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/8/85/Orange_tabby_cat_sitting_on_fallen_leaves-Hisashi-01.jpg/960px-Orange_tabby_cat_sitting_on_fallen_leaves-Hisashi-01.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1445, 1),
  ('ข้าวปั้น', 'pets/showcase/p17_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/3/3b/Black_and_white_kitten_portraits_in_the_Philippines_02.jpg/960px-Black_and_white_kitten_portraits_in_the_Philippines_02.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 0),
  ('ข้าวปั้น', 'pets/showcase/p17_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/7/75/Black_and_white_kitten_portraits_in_the_Philippines_01.jpg/960px-Black_and_white_kitten_portraits_in_the_Philippines_01.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 1),
  ('ข้าวปั้น', 'pets/showcase/p17_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c1/Six_weeks_old_cat_%28aka%29.jpg/960px-Six_weeks_old_cat_%28aka%29.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 640, 2),
  ('เสือน้อย', 'pets/showcase/p18_0.jpg', 'https://s3.us-west-2.amazonaws.com/cdn2.thecatapi.com/images/buk.jpg', 640, 591, 0),
  ('จิ๋ว', 'pets/showcase/p19_0.jpg', 'https://images.dog.ceo/breeds/chihuahua/n02085620_4441.jpg', 375, 500, 0),
  ('จิ๋ว', 'pets/showcase/p19_1.jpg', 'https://images.dog.ceo/breeds/chihuahua/n02085620_11140.jpg', 500, 375, 1),
  ('จิ๋ว', 'pets/showcase/p19_2.jpg', 'https://images.dog.ceo/breeds/chihuahua/n02085620_3677.jpg', 500, 375, 2),
  ('ข้าวเหนียว', 'pets/showcase/p20_0.jpg', 'https://images.dog.ceo/breeds/mix/lilypad2.jpg', 768, 1024, 0),
  ('ขนมครก', 'pets/showcase/p21_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e1/Holland_lop_rabbit.jpg/960px-Holland_lop_rabbit.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 638, 0),
  ('ขนมครก', 'pets/showcase/p21_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/17/Holland_lop.JPG/960px-Holland_lop.JPG?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 642, 1),
  ('ขนมครก', 'pets/showcase/p21_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/61/Holland_lop_bunny.JPG/960px-Holland_lop_bunny.JPG?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 2),
  ('สำลี', 'pets/showcase/p22_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/5/53/Lionhead_Rabbit_with_black_nose.jpg/960px-Lionhead_Rabbit_with_black_nose.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 0),
  ('สำลี', 'pets/showcase/p22_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/3/3d/Brown_%26_White_Lion_Head_Rabbit.JPG/960px-Brown_%26_White_Lion_Head_Rabbit.JPG?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 1),
  ('สำลี', 'pets/showcase/p22_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/3/3b/White_Lion_Head_Female_Rabbit.JPG/960px-White_Lion_Head_Female_Rabbit.JPG?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 2),
  ('โกโก้', 'pets/showcase/p23_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/bd/Coconut_the_rabbit_07.jpg/960px-Coconut_the_rabbit_07.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 0),
  ('โกโก้', 'pets/showcase/p23_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1e/Coconut_the_rabbit_23.jpg/960px-Coconut_the_rabbit_23.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 1),
  ('โกโก้', 'pets/showcase/p23_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d6/Coconut_the_rabbit_09.jpg/960px-Coconut_the_rabbit_09.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 2),
  ('ด่างดำ', 'pets/showcase/p24_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/17/2017-08-19_AT_Wien_13_Hietzing%2C_Tiergarten_Sch%C3%B6nbrunn%2C_Oryctolagus_cuniculus_f._domesticus_%2848250983416%29.jpg/960px-2017-08-19_AT_Wien_13_Hietzing%2C_Tiergarten_Sch%C3%B6nbrunn%2C_Oryctolagus_cuniculus_f._domesticus_%2848250983416%29.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 0),
  ('ด่างดำ', 'pets/showcase/p24_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/6d/2018-01-28_AT_Wien_13_Hietzing%2C_Tiergarten_Sch%C3%B6nbrunn%2C_Oryctolagus_cuniculus_f._domesticus_%2830266922838%29.jpg/960px-2018-01-28_AT_Wien_13_Hietzing%2C_Tiergarten_Sch%C3%B6nbrunn%2C_Oryctolagus_cuniculus_f._domesticus_%2830266922838%29.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 640, 1),
  ('ฟ้าใส', 'pets/showcase/p25_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a0/Melopsittacus_undulatus_-pet_in_cage_-male-8a.jpg/960px-Melopsittacus_undulatus_-pet_in_cage_-male-8a.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1440, 0),
  ('ฟ้าใส', 'pets/showcase/p25_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/7/78/Budgerigar_Cute_Birds.jpg/960px-Budgerigar_Cute_Birds.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1527, 1),
  ('ลูกพีช', 'pets/showcase/p26_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/0f/Nymphicus_hollandicus_Bronzefallow.jpg/960px-Nymphicus_hollandicus_Bronzefallow.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 0),
  ('ลูกพีช', 'pets/showcase/p26_1.jpg', 'https://upload.wikimedia.org/wikipedia/commons/c/c1/Nymphicus_hollandicus_DT_-Z_C%C3%B3ndor-_0803_%282%29_%2820859406125%29.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail_unscaled', 800, 600, 1),
  ('กีวี่', 'pets/showcase/p27_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/f/f6/Agapornis_roseicollis_bird.jpg/960px-Agapornis_roseicollis_bird.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 640, 0),
  ('กีวี่', 'pets/showcase/p27_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/4f/Rosy-faced_lovebird_%28Agapornis_roseicollis_roseicollis%29.jpg/960px-Rosy-faced_lovebird_%28Agapornis_roseicollis_roseicollis%29.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 960, 1),
  ('มะม่วง', 'pets/showcase/p28_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/6/62/Sun_Conure_%28Aratinga_solstitialis%29_-pet_on_perch.jpg/960px-Sun_Conure_%28Aratinga_solstitialis%29_-pet_on_perch.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 0),
  ('มะม่วง', 'pets/showcase/p28_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/2f/Sun_Conure_%28Aratinga_solstitialis%29_-pet_on_finger.jpg/960px-Sun_Conure_%28Aratinga_solstitialis%29_-pet_on_finger.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 1),
  ('บลูเบอร์รี่', 'pets/showcase/p29_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/9/95/Siamese-fighting-fish-bettas-1378308-hero-f459084da1414308accde7e21001906c.jpg/960px-Siamese-fighting-fish-bettas-1378308-hero-f459084da1414308accde7e21001906c.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 960, 0),
  ('บลูเบอร์รี่', 'pets/showcase/p29_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b8/Kampffisch_betta_splendenscele4.jpg/960px-Kampffisch_betta_splendenscele4.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 683, 1),
  ('หมวกแดง', 'pets/showcase/p30_0.jpg', 'https://upload.wikimedia.org/wikipedia/commons/a/a6/WenYu_Pair.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail_unscaled', 912, 684, 0),
  ('หมวกแดง', 'pets/showcase/p30_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/7/75/Dazed_again_%284972630499%29.jpg/960px-Dazed_again_%284972630499%29.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 640, 1),
  ('เฮงเฮง', 'pets/showcase/p31_0.jpg', 'https://upload.wikimedia.org/wikipedia/commons/9/95/Post-137-1207905651.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail_unscaled', 640, 457, 0),
  ('เฮงเฮง', 'pets/showcase/p31_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e1/Flowerhorn.jpg/960px-Flowerhorn.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 590, 1),
  ('ทองดี', 'pets/showcase/p32_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/47/African_Spurred_Tortoise_in_Toronto.jpg/960px-African_Spurred_Tortoise_in_Toronto.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 626, 0),
  ('ทองดี', 'pets/showcase/p32_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d0/Geochelone_sulcata_-Oakland_Zoo_-feeding-8a.jpg/960px-Geochelone_sulcata_-Oakland_Zoo_-feeding-8a.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 587, 1),
  ('ทองดี', 'pets/showcase/p32_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/7/76/African_Spurred_Tortoise_in_Shoushan_Zoo.jpg/960px-African_Spurred_Tortoise_in_Shoushan_Zoo.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 538, 2),
  ('ซูก้า', 'pets/showcase/p33_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a8/Petaurus_breviceps_Petauro_dello_zucchero.jpg/960px-Petaurus_breviceps_Petauro_dello_zucchero.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 682, 0),
  ('ซูก้า', 'pets/showcase/p33_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/5/5b/Petaurus_Breviceps_Petauro_dello_Zucchero_2.jpg/960px-Petaurus_Breviceps_Petauro_dello_Zucchero_2.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 681, 1),
  ('ซูก้า', 'pets/showcase/p33_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/5/56/Petaurus_breviceps_07_-_by_Wm_Jas.jpg/960px-Petaurus_breviceps_07_-_by_Wm_Jas.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 640, 2),
  ('หนามเตย', 'pets/showcase/p34_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1b/Atelerix_albiventris_in_Spain.jpg/960px-Atelerix_albiventris_in_Spain.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 706, 0),
  ('หนามเตย', 'pets/showcase/p34_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b4/Afrikanski_mini_taralej.jpg/960px-Afrikanski_mini_taralej.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 540, 1),
  ('หมูหยอง', 'pets/showcase/p35_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/bc/Caviidae_Cavia_porcellus_1.jpg/960px-Caviidae_Cavia_porcellus_1.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 0),
  ('หมูหยอง', 'pets/showcase/p35_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/2d/Cochon_d%27Inde_%28Cavia_porcellus%29_%282%29.jpg/960px-Cochon_d%27Inde_%28Cavia_porcellus%29_%282%29.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 640, 1),
  ('หมูหยอง', 'pets/showcase/p35_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/3/3c/Cochon_d%27Inde_%28Cavia_porcellus%29_%281%29.jpg/960px-Cochon_d%27Inde_%28Cavia_porcellus%29_%281%29.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 640, 2),
  ('ทองหยิบ', 'pets/showcase/p36_0.jpg', 'https://images.dog.ceo/breeds/retriever-golden/mori_4.jpg', 960, 1280, 0),
  ('ทองหยิบ', 'pets/showcase/p36_1.jpg', 'https://images.dog.ceo/breeds/retriever-golden/n02099601_2422.jpg', 282, 424, 1),
  ('ทองหยิบ', 'pets/showcase/p36_2.jpg', 'https://images.dog.ceo/breeds/retriever-golden/n02099601_7803.jpg', 500, 332, 2),
  ('ขนมปัง', 'pets/showcase/p37_0.jpg', 'https://images.dog.ceo/breeds/pembroke/n02113023_1571.jpg', 333, 500, 0),
  ('ขนมปัง', 'pets/showcase/p37_1.jpg', 'https://images.dog.ceo/breeds/pembroke/n02113023_631.jpg', 500, 333, 1),
  ('ขนมปัง', 'pets/showcase/p37_2.jpg', 'https://images.dog.ceo/breeds/pembroke/n02113023_6567.jpg', 500, 376, 2),
  ('ขนมปัง', 'pets/showcase/p37_3.jpg', 'https://images.dog.ceo/breeds/pembroke/n02113023_12785.jpg', 500, 333, 3),
  ('ขนมปัง', 'pets/showcase/p37_4.jpg', 'https://images.dog.ceo/breeds/pembroke/n02113023_7038.jpg', 375, 500, 4),
  ('ส้มจี๊ด', 'pets/showcase/p38_0.jpg', 'https://images.dog.ceo/breeds/pomeranian/n02112018_12586.jpg', 400, 301, 0),
  ('ส้มจี๊ด', 'pets/showcase/p38_1.jpg', 'https://images.dog.ceo/breeds/pomeranian/n02112018_6098.jpg', 375, 500, 1),
  ('ส้มจี๊ด', 'pets/showcase/p38_2.jpg', 'https://images.dog.ceo/breeds/pomeranian/n02112018_1621.jpg', 500, 375, 2),
  ('เทาเทา', 'pets/showcase/p39_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/3/3d/Korat_cat_wikipedia.jpg/960px-Korat_cat_wikipedia.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 640, 0),
  ('เทาเทา', 'pets/showcase/p39_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/8/8f/KOR_1149.jpg/960px-KOR_1149.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 776, 1),
  ('เทาเทา', 'pets/showcase/p39_2.jpg', 'https://upload.wikimedia.org/wikipedia/commons/c/c9/Korat_in_cat_show_1.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail_unscaled', 696, 522, 2),
  ('วุ้นเส้น', 'pets/showcase/p40_0.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/13/Seal_point_Blue_Eyed_Cat.jpg/960px-Seal_point_Blue_Eyed_Cat.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 640, 0),
  ('วุ้นเส้น', 'pets/showcase/p40_1.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/af/Seal_Old_Style_Siamese_Thai.jpg/960px-Seal_Old_Style_Siamese_Thai.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 637, 1),
  ('วุ้นเส้น', 'pets/showcase/p40_2.jpg', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/bb/Young_Siamese_Seal_Point.jpg/960px-Young_Siamese_Seal_Point.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 720, 2),
  ('โมจิ', 'pets/showcase/p41_0.jpg', 'https://s3.us-west-2.amazonaws.com/cdn2.thecatapi.com/images/q7izjTTa4.jpg', 960, 960, 0),
  ('บัวลอย', 'pets/showcase/p42_0.jpg', 'https://s3.us-west-2.amazonaws.com/cdn2.thecatapi.com/images/cSzaNCgq2.jpg', 1024, 768, 0),
  ('ไส้กรอก', 'pets/showcase/p43_0.jpg', 'https://images.dog.ceo/breeds/dachshund/dachshund-5.jpg', 500, 336, 0),
  ('ไส้กรอก', 'pets/showcase/p43_1.jpg', 'https://images.dog.ceo/breeds/dachshund/foxhound-53951_640.jpg', 600, 399, 1),
  ('ไส้กรอก', 'pets/showcase/p43_2.jpg', 'https://images.dog.ceo/breeds/dachshund/dog-55140_640.jpg', 600, 450, 2),
  ('ไส้กรอก', 'pets/showcase/p43_3.jpg', 'https://images.dog.ceo/breeds/dachshund/dachshund-123503_640.jpg', 600, 450, 3),
  ('ปุยฝ้าย', 'pets/showcase/p44_0.jpg', 'https://images.dog.ceo/breeds/shihtzu/n02086240_4127.jpg', 425, 480, 0),
  ('ปุยฝ้าย', 'pets/showcase/p44_1.jpg', 'https://images.dog.ceo/breeds/shihtzu/n02086240_6323.jpg', 500, 475, 1),
  ('ปุยฝ้าย', 'pets/showcase/p44_2.jpg', 'https://images.dog.ceo/breeds/shihtzu/n02086240_2211.jpg', 360, 272, 2),
  ('เมฆ', 'pets/showcase/p45_0.jpg', 'https://s3.us-west-2.amazonaws.com/cdn2.thecatapi.com/images/me56sI74P.jpg', 736, 1104, 0)
) AS v(pet, storage_key, url, width, height, sort_order) JOIN sc_pet s ON s.name = v.pet;

INSERT INTO pet_traits (pet_id, trait_id)
SELECT s.id, t.id FROM (VALUES
  ('ข้าวตัง', 'energetic'),
  ('ข้าวตัง', 'social'),
  ('ข้าวตัง', 'kid_friendly'),
  ('ลุงหนวด', 'chill'),
  ('ลุงหนวด', 'quiet'),
  ('ลุงหนวด', 'affectionate'),
  ('ลูกชิ้น', 'independent'),
  ('ลูกชิ้น', 'chill'),
  ('ถั่วดำ', 'energetic'),
  ('ถั่วดำ', 'talkative'),
  ('ถั่วดำ', 'foodie'),
  ('ถ่าน', 'affectionate'),
  ('ถ่าน', 'chill'),
  ('สามสี', 'independent'),
  ('สามสี', 'quiet'),
  ('สามสี', 'tidy'),
  ('ยายจ๋า', 'chill'),
  ('ยายจ๋า', 'quiet'),
  ('ยายจ๋า', 'affectionate'),
  ('ขุนแผน', 'energetic'),
  ('ขุนแผน', 'independent'),
  ('บราวนี่', 'energetic'),
  ('บราวนี่', 'social'),
  ('บราวนี่', 'foodie'),
  ('มะลิ', 'affectionate'),
  ('มะลิ', 'talkative'),
  ('มะลิ', 'tidy'),
  ('ถั่วเขียว', 'quiet'),
  ('ถั่วเขียว', 'tidy'),
  ('ข้าวโพด', 'foodie'),
  ('ข้าวโพด', 'independent'),
  ('หิมะ', 'energetic'),
  ('หิมะ', 'talkative'),
  ('หิมะ', 'social'),
  ('ปั๊กกี้', 'chill'),
  ('ปั๊กกี้', 'foodie'),
  ('ปั๊กกี้', 'affectionate'),
  ('ส้มซ่า', 'foodie'),
  ('ส้มซ่า', 'social'),
  ('ส้มซ่า', 'energetic'),
  ('ทองแท่ง', 'chill'),
  ('ทองแท่ง', 'affectionate'),
  ('ข้าวปั้น', 'energetic'),
  ('ข้าวปั้น', 'talkative'),
  ('เสือน้อย', 'independent'),
  ('เสือน้อย', 'quiet'),
  ('จิ๋ว', 'talkative'),
  ('จิ๋ว', 'affectionate'),
  ('ข้าวเหนียว', 'kid_friendly'),
  ('ข้าวเหนียว', 'chill'),
  ('ข้าวเหนียว', 'social'),
  ('ขนมครก', 'affectionate'),
  ('ขนมครก', 'chill'),
  ('สำลี', 'quiet'),
  ('สำลี', 'tidy'),
  ('โกโก้', 'foodie'),
  ('โกโก้', 'social'),
  ('ด่างดำ', 'chill'),
  ('ด่างดำ', 'independent'),
  ('ฟ้าใส', 'talkative'),
  ('ฟ้าใส', 'social'),
  ('ลูกพีช', 'affectionate'),
  ('ลูกพีช', 'talkative'),
  ('กีวี่', 'energetic'),
  ('กีวี่', 'talkative'),
  ('มะม่วง', 'talkative'),
  ('มะม่วง', 'energetic'),
  ('มะม่วง', 'social'),
  ('บลูเบอร์รี่', 'independent'),
  ('บลูเบอร์รี่', 'quiet'),
  ('หมวกแดง', 'chill'),
  ('หมวกแดง', 'foodie'),
  ('เฮงเฮง', 'independent'),
  ('เฮงเฮง', 'foodie'),
  ('ทองดี', 'chill'),
  ('ทองดี', 'independent'),
  ('ซูก้า', 'energetic'),
  ('ซูก้า', 'affectionate'),
  ('หนามเตย', 'quiet'),
  ('หนามเตย', 'independent'),
  ('หมูหยอง', 'social'),
  ('หมูหยอง', 'talkative'),
  ('หมูหยอง', 'foodie'),
  ('ทองหยิบ', 'kid_friendly'),
  ('ทองหยิบ', 'affectionate'),
  ('ทองหยิบ', 'social'),
  ('ขนมปัง', 'energetic'),
  ('ขนมปัง', 'foodie'),
  ('ขนมปัง', 'kid_friendly'),
  ('ส้มจี๊ด', 'talkative'),
  ('ส้มจี๊ด', 'affectionate'),
  ('เทาเทา', 'quiet'),
  ('เทาเทา', 'affectionate'),
  ('เทาเทา', 'tidy'),
  ('วุ้นเส้น', 'talkative'),
  ('วุ้นเส้น', 'affectionate'),
  ('โมจิ', 'chill'),
  ('โมจิ', 'affectionate'),
  ('บัวลอย', 'chill'),
  ('บัวลอย', 'quiet'),
  ('ไส้กรอก', 'energetic'),
  ('ไส้กรอก', 'talkative'),
  ('ไส้กรอก', 'foodie'),
  ('ปุยฝ้าย', 'chill'),
  ('ปุยฝ้าย', 'affectionate'),
  ('เมฆ', 'chill'),
  ('เมฆ', 'social')
) AS v(pet, slug) JOIN sc_pet s ON s.name = v.pet JOIN traits t ON t.slug = v.slug;

-- ---------- ถูกใจ / ปัดผ่าน (like_count อัปเดตเองด้วย trigger) ----------
INSERT INTO likes (user_id, pet_id, created_at)
SELECT u.id, s.id, now() - make_interval(hours => v.hours) FROM (VALUES
  ('fah.bkk', 'มะลิ', 8),
  ('fah.bkk', 'วุ้นเส้น', 15),
  ('fah.bkk', 'ส้มซ่า', 22),
  ('fah.bkk', 'เทาเทา', 29),
  ('fah.bkk', 'ถ่าน', 36),
  ('fah.bkk', 'ปุยฝ้าย', 43),
  ('fah.bkk', 'บัวลอย', 50),
  ('prae.family', 'ขนมปัง', 57),
  ('prae.family', 'ทองหยิบ', 64),
  ('prae.family', 'ข้าวตัง', 71),
  ('prae.family', 'ข้าวเหนียว', 78),
  ('prae.family', 'ส้มซ่า', 85),
  ('tee.runner', 'หิมะ', 2),
  ('tee.runner', 'ขุนแผน', 9),
  ('tee.runner', 'ข้าวตัง', 16),
  ('tee.runner', 'ทองหยิบ', 23),
  ('nok.retired', 'ลุงหนวด', 30),
  ('nok.retired', 'ยายจ๋า', 37),
  ('nok.retired', 'ปั๊กกี้', 44),
  ('nok.retired', 'บัวลอย', 51),
  ('nok.retired', 'ส้มจี๊ด', 58),
  ('puk.kk', 'ถั่วเขียว', 65),
  ('puk.kk', 'ข้าวโพด', 72),
  ('puk.kk', 'ขนมครก', 79),
  ('puk.kk', 'สำลี', 86),
  ('puk.kk', 'หมูหยอง', 3),
  ('kai.phuket', 'ทองแท่ง', 10),
  ('kai.phuket', 'ส้มซ่า', 17),
  ('kai.phuket', 'มะลิ', 24),
  ('kai.phuket', 'โมจิ', 31),
  ('golf.rayong', 'มะม่วง', 38),
  ('golf.rayong', 'ทองหยิบ', 45),
  ('jane.phuket', 'ข้าวปั้น', 52),
  ('jane.phuket', 'มะลิ', 59),
  ('ploy.nb', 'ส้มซ่า', 66),
  ('ploy.nb', 'โมจิ', 73),
  ('nat.buriram', 'ส้มซ่า', 80),
  ('nat.buriram', 'ถ่าน', 87),
  ('aun.chon', 'ขนมปัง', 4),
  ('nun.cm', 'ข้าวปั้น', 11)
) AS v(username, pet, hours) JOIN users u ON u.username = v.username JOIN sc_pet s ON s.name = v.pet;

INSERT INTO passes (user_id, pet_id, created_at)
SELECT u.id, s.id, now() - make_interval(hours => v.hours) FROM (VALUES
  ('fah.bkk', 'ขุนแผน', 8),
  ('fah.bkk', 'หิมะ', 15),
  ('puk.kk', 'ขุนแผน', 22),
  ('puk.kk', 'ทองดี', 29),
  ('kai.phuket', 'มะม่วง', 36)
) AS v(username, pet, hours) JOIN users u ON u.username = v.username JOIN sc_pet s ON s.name = v.pet;

-- ---------- แชท 8 ห้อง ----------
-- ห้องต้องเกิดพร้อมข้อความแรกในธุรกรรมเดียวกัน (deferred trigger conversations_require_first_message)
-- trigger ของ messages ตั้ง last_message_at จากแถวที่ใส่ล่าสุด จึงต้องใส่เรียงตามเวลา (ORDER BY)

-- tee.runner ทักเรื่อง หิมะ (อ่านแล้ว: owner)
WITH c AS (
  INSERT INTO conversations (pet_id, initiator_id, owner_id, created_at)
  SELECT s.id, i.id, s.owner_id, now() - make_interval(mins => 1800)
  FROM sc_pet s, users i WHERE s.name = 'หิมะ' AND i.username = 'tee.runner'
  RETURNING id, initiator_id, owner_id)
INSERT INTO messages (conversation_id, sender_id, body, media_type, media_url, thumbnail_url,
                      media_width, media_height, created_at)
SELECT c.id, CASE m.who WHEN 'i' THEN c.initiator_id ELSE c.owner_id END, m.body,
       m.media_type::message_media_type, m.url, m.url, m.width, m.height, now() - make_interval(mins => m.mins)
FROM c, (VALUES
  ('i', 'สวัสดีครับ สนใจน้องหิมะครับ ผมวิ่งทุกเช้าวันละ 5 กิโล น้องวิ่งไหวไหมครับ', NULL, NULL, NULL::int, NULL::int, 1800),
  ('o', 'ไหวครับ หิมะชอบวิ่งมาก แต่ต้องวิ่งช่วงเช้ามืดนะครับ ถ้าแดดออกจะร้อนเกินไปสำหรับฮัสกี้', NULL, NULL, NULL::int, NULL::int, 1740),
  ('o', '', 'image', 'https://images.dog.ceo/breeds/husky/n02110185_9855.jpg', 360, 331, 1739),
  ('i', 'น่ารักมากครับ ที่บ้านเป็นทาวน์เฮ้าส์ มีห้องแอร์ให้น้องอยู่ตอนกลางวันได้', NULL, NULL, NULL::int, NULL::int, 1560),
  ('o', 'ดีเลยครับ เสาร์นี้สะดวกมาดูตัวที่ชลบุรีไหมครับ จะได้ลองพาเดินด้วยกัน', NULL, NULL, NULL::int, NULL::int, 180)
) AS m(who, body, media_type, url, width, height, mins)
ORDER BY m.mins DESC;
SELECT mark_conversation_read(c.id, c.owner_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'หิมะ' AND i.username = 'tee.runner';

-- prae.family ทักเรื่อง ขนมปัง (อ่านแล้ว: both)
WITH c AS (
  INSERT INTO conversations (pet_id, initiator_id, owner_id, created_at)
  SELECT s.id, i.id, s.owner_id, now() - make_interval(mins => 3000)
  FROM sc_pet s, users i WHERE s.name = 'ขนมปัง' AND i.username = 'prae.family'
  RETURNING id, initiator_id, owner_id)
INSERT INTO messages (conversation_id, sender_id, body, media_type, media_url, thumbnail_url,
                      media_width, media_height, created_at)
SELECT c.id, CASE m.who WHEN 'i' THEN c.initiator_id ELSE c.owner_id END, m.body,
       m.media_type::message_media_type, m.url, m.url, m.width, m.height, now() - make_interval(mins => m.mins)
FROM c, (VALUES
  ('i', 'สวัสดีค่ะ ที่บ้านมีลูกสองคน 7 ขวบกับ 10 ขวบ ขนมปังเข้ากับเด็กได้ไหมคะ', NULL, NULL, NULL::int, NULL::int, 3000),
  ('o', 'ได้ดีมากเลยค่ะ หลานข้างบ้านมาเล่นด้วยทุกวัน แต่อย่าให้เด็กอุ้มแล้วปล่อยลงพื้นแรง ๆ นะคะ หลังเขายาว', NULL, NULL, NULL::int, NULL::int, 2880),
  ('i', 'รับทราบค่ะ วันอาทิตย์นี้ขอนัดไปดูตัวได้ไหมคะ จะพาลูก ๆ ไปด้วย', NULL, NULL, NULL::int, NULL::int, 2820),
  ('o', 'ได้ค่ะ บ่ายสองโมงนะคะ เดี๋ยวส่งโลเคชันให้', NULL, NULL, NULL::int, NULL::int, 2760),
  ('o', '', 'image', 'https://images.dog.ceo/breeds/pembroke/n02113023_631.jpg', 500, 333, 2759),
  ('i', 'ขอบคุณมากค่ะ เด็ก ๆ ตื่นเต้นกันใหญ่แล้ว', NULL, NULL, NULL::int, NULL::int, 2700)
) AS m(who, body, media_type, url, width, height, mins)
ORDER BY m.mins DESC;
SELECT mark_conversation_read(c.id, c.initiator_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'ขนมปัง' AND i.username = 'prae.family';
SELECT mark_conversation_read(c.id, c.owner_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'ขนมปัง' AND i.username = 'prae.family';

-- kai.phuket ทักเรื่อง ทองแท่ง (อ่านแล้ว: both)
WITH c AS (
  INSERT INTO conversations (pet_id, initiator_id, owner_id, created_at)
  SELECT s.id, i.id, s.owner_id, now() - make_interval(mins => 24480)
  FROM sc_pet s, users i WHERE s.name = 'ทองแท่ง' AND i.username = 'kai.phuket'
  RETURNING id, initiator_id, owner_id)
INSERT INTO messages (conversation_id, sender_id, body, media_type, media_url, thumbnail_url,
                      media_width, media_height, created_at)
SELECT c.id, CASE m.who WHEN 'i' THEN c.initiator_id ELSE c.owner_id END, m.body,
       m.media_type::message_media_type, m.url, m.url, m.width, m.height, now() - make_interval(mins => m.mins)
FROM c, (VALUES
  ('i', 'สวัสดีค่ะ ไม่เคยเลี้ยงแมวมาก่อนเลย ทองแท่งเหมาะกับมือใหม่ไหมคะ', NULL, NULL, NULL::int, NULL::int, 24480),
  ('o', 'เหมาะมากค่ะ นิสัยนิ่ง ใช้กระบะทรายเป็น กินอาหารเม็ดไม่เลือก เดี๋ยวเจนแนะนำของที่ต้องเตรียมให้นะคะ', NULL, NULL, NULL::int, NULL::int, 24450),
  ('i', 'เตรียมกระบะทราย ที่ลับเล็บ กับอาหารเม็ดแล้วค่ะ พรุ่งนี้ไปรับน้องได้ไหมคะ', NULL, NULL, NULL::int, NULL::int, 21600),
  ('o', 'ได้ค่ะ เจอกันหน้าโรงแรมตอนเย็นนะคะ', NULL, NULL, NULL::int, NULL::int, 21580)
) AS m(who, body, media_type, url, width, height, mins)
ORDER BY m.mins DESC;
SELECT mark_conversation_read(c.id, c.initiator_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'ทองแท่ง' AND i.username = 'kai.phuket';
SELECT mark_conversation_read(c.id, c.owner_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'ทองแท่ง' AND i.username = 'kai.phuket';

-- fah.bkk ทักเรื่อง วุ้นเส้น (อ่านแล้ว: initiator)
WITH c AS (
  INSERT INTO conversations (pet_id, initiator_id, owner_id, created_at)
  SELECT s.id, i.id, s.owner_id, now() - make_interval(mins => 300)
  FROM sc_pet s, users i WHERE s.name = 'วุ้นเส้น' AND i.username = 'fah.bkk'
  RETURNING id, initiator_id, owner_id)
INSERT INTO messages (conversation_id, sender_id, body, media_type, media_url, thumbnail_url,
                      media_width, media_height, created_at)
SELECT c.id, CASE m.who WHEN 'i' THEN c.initiator_id ELSE c.owner_id END, m.body,
       m.media_type::message_media_type, m.url, m.url, m.width, m.height, now() - make_interval(mins => m.mins)
FROM c, (VALUES
  ('i', 'สวัสดีค่ะ สนใจน้องวุ้นเส้นค่ะ ฟ้าทำงานที่บ้านทั้งวัน อยู่คอนโดที่กรุงเทพฯ ค่ะ', NULL, NULL, NULL::int, NULL::int, 300),
  ('i', 'ถ้าต้องไปรับที่บุรีรัมย์ก็ยินดีขับรถไปค่ะ', NULL, NULL, NULL::int, NULL::int, 298)
) AS m(who, body, media_type, url, width, height, mins)
ORDER BY m.mins DESC;
SELECT mark_conversation_read(c.id, c.initiator_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'วุ้นเส้น' AND i.username = 'fah.bkk';

-- nok.retired ทักเรื่อง ลุงหนวด (อ่านแล้ว: both)
WITH c AS (
  INSERT INTO conversations (pet_id, initiator_id, owner_id, created_at)
  SELECT s.id, i.id, s.owner_id, now() - make_interval(mins => 2880)
  FROM sc_pet s, users i WHERE s.name = 'ลุงหนวด' AND i.username = 'nok.retired'
  RETURNING id, initiator_id, owner_id)
INSERT INTO messages (conversation_id, sender_id, body, media_type, media_url, thumbnail_url,
                      media_width, media_height, created_at)
SELECT c.id, CASE m.who WHEN 'i' THEN c.initiator_id ELSE c.owner_id END, m.body,
       m.media_type::message_media_type, m.url, m.url, m.width, m.height, now() - make_interval(mins => m.mins)
FROM c, (VALUES
  ('i', 'สวัสดีค่ะ ป้าเพิ่งเกษียณ อยู่บ้านทั้งวัน อยากรับลุงหนวดไปดูแลค่ะ', NULL, NULL, NULL::int, NULL::int, 2880),
  ('o', 'ขอบคุณมากครับคุณป้า ลุงหนวดต้องกินยาบำรุงข้อทุกเช้า ไม่ยุ่งยากครับ บ้านคุณป้ามีบันไดเยอะไหมครับ', NULL, NULL, NULL::int, NULL::int, 2840),
  ('i', 'บ้านชั้นเดียวค่ะ มีสนามหญ้าหน้าบ้านด้วย', NULL, NULL, NULL::int, NULL::int, 2820),
  ('o', 'เหมาะมากเลยครับ ทางกลุ่มขอนัดไปเยี่ยมบ้านก่อนส่งมอบนะครับ เป็นขั้นตอนปกติของเรา', NULL, NULL, NULL::int, NULL::int, 1440)
) AS m(who, body, media_type, url, width, height, mins)
ORDER BY m.mins DESC;
SELECT mark_conversation_read(c.id, c.initiator_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'ลุงหนวด' AND i.username = 'nok.retired';
SELECT mark_conversation_read(c.id, c.owner_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'ลุงหนวด' AND i.username = 'nok.retired';

-- puk.kk ทักเรื่อง ถั่วเขียว (อ่านแล้ว: owner)
WITH c AS (
  INSERT INTO conversations (pet_id, initiator_id, owner_id, created_at)
  SELECT s.id, i.id, s.owner_id, now() - make_interval(mins => 480)
  FROM sc_pet s, users i WHERE s.name = 'ถั่วเขียว' AND i.username = 'puk.kk'
  RETURNING id, initiator_id, owner_id)
INSERT INTO messages (conversation_id, sender_id, body, media_type, media_url, thumbnail_url,
                      media_width, media_height, created_at)
SELECT c.id, CASE m.who WHEN 'i' THEN c.initiator_id ELSE c.owner_id END, m.body,
       m.media_type::message_media_type, m.url, m.url, m.width, m.height, now() - make_interval(mins => m.mins)
FROM c, (VALUES
  ('i', 'สวัสดีค่ะ หอปุ๊กอนุญาตสัตว์เล็กค่ะ ถั่วเขียวกัดสายไฟไหมคะ', NULL, NULL, NULL::int, NULL::int, 480),
  ('o', 'มีบ้างค่ะ ต้องเก็บสายไฟหรือใส่ท่อกันกัดไว้นะคะ นี่รูปตอนเขากินหญ้าค่ะ', NULL, NULL, NULL::int, NULL::int, 420),
  ('o', '', 'image', 'https://thumb.wikimedia.org/wikipedia/commons/thumb/4/44/GreyNetherlandsDwarf.jpg/960px-GreyNetherlandsDwarf.jpg?utm_source=commons.wikimedia.org&utm_campaign=imageinfo&utm_content=thumbnail', 960, 1280, 419)
) AS m(who, body, media_type, url, width, height, mins)
ORDER BY m.mins DESC;
SELECT mark_conversation_read(c.id, c.owner_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'ถั่วเขียว' AND i.username = 'puk.kk';

-- golf.rayong ทักเรื่อง มะม่วง (อ่านแล้ว: both)
WITH c AS (
  INSERT INTO conversations (pet_id, initiator_id, owner_id, created_at)
  SELECT s.id, i.id, s.owner_id, now() - make_interval(mins => 1200)
  FROM sc_pet s, users i WHERE s.name = 'มะม่วง' AND i.username = 'golf.rayong'
  RETURNING id, initiator_id, owner_id)
INSERT INTO messages (conversation_id, sender_id, body, media_type, media_url, thumbnail_url,
                      media_width, media_height, created_at)
SELECT c.id, CASE m.who WHEN 'i' THEN c.initiator_id ELSE c.owner_id END, m.body,
       m.media_type::message_media_type, m.url, m.url, m.width, m.height, now() - make_interval(mins => m.mins)
FROM c, (VALUES
  ('i', 'สวัสดีครับ มะม่วงยังอยู่ไหมครับ ผมเคยเลี้ยงซันคอนัวร์มาก่อน', NULL, NULL, NULL::int, NULL::int, 1200),
  ('o', 'ยังอยู่ครับ แต่ต้องบอกก่อนว่าเสียงดังมาก คอนโดน่าจะไม่ไหวนะครับ', NULL, NULL, NULL::int, NULL::int, 1140),
  ('i', 'จริงด้วยครับ งั้นขอปรึกษาที่บ้านก่อนครับ ผมกำลังจะย้ายไปบ้านเดี่ยวเดือนหน้า', NULL, NULL, NULL::int, NULL::int, 1080)
) AS m(who, body, media_type, url, width, height, mins)
ORDER BY m.mins DESC;
SELECT mark_conversation_read(c.id, c.initiator_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'มะม่วง' AND i.username = 'golf.rayong';
SELECT mark_conversation_read(c.id, c.owner_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'มะม่วง' AND i.username = 'golf.rayong';

-- fah.bkk ทักเรื่อง ปุยฝ้าย (อ่านแล้ว: both)
WITH c AS (
  INSERT INTO conversations (pet_id, initiator_id, owner_id, created_at)
  SELECT s.id, i.id, s.owner_id, now() - make_interval(mins => 28800)
  FROM sc_pet s, users i WHERE s.name = 'ปุยฝ้าย' AND i.username = 'fah.bkk'
  RETURNING id, initiator_id, owner_id)
INSERT INTO messages (conversation_id, sender_id, body, media_type, media_url, thumbnail_url,
                      media_width, media_height, created_at)
SELECT c.id, CASE m.who WHEN 'i' THEN c.initiator_id ELSE c.owner_id END, m.body,
       m.media_type::message_media_type, m.url, m.url, m.width, m.height, now() - make_interval(mins => m.mins)
FROM c, (VALUES
  ('i', 'สวัสดีค่ะ ปุยฝ้ายอยู่คอนโดได้ไหมคะ', NULL, NULL, NULL::int, NULL::int, 28800),
  ('o', 'ได้ครับ เขาเงียบมาก แต่ตอนนี้ญาติผมอาจจะรับไปเลี้ยงเอง ขอแจ้งอีกทีนะครับ', NULL, NULL, NULL::int, NULL::int, 28710)
) AS m(who, body, media_type, url, width, height, mins)
ORDER BY m.mins DESC;
SELECT mark_conversation_read(c.id, c.initiator_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'ปุยฝ้าย' AND i.username = 'fah.bkk';
SELECT mark_conversation_read(c.id, c.owner_id) FROM conversations c JOIN sc_pet s ON s.id = c.pet_id JOIN users i ON i.id = c.initiator_id WHERE s.name = 'ปุยฝ้าย' AND i.username = 'fah.bkk';

-- ---------- เปลี่ยนสถานะ (pending / ได้บ้านแล้ว / ยกเลิกประกาศ) ----------
-- trigger close_conversations_for_pet ปิดห้องแชทของตัวที่ได้บ้าน/ยกเลิก พร้อมใส่ข้อความระบบให้เอง
UPDATE pets p SET status = v.status::pet_status,
       adopted_at = CASE WHEN v.status = 'adopted' THEN now() - make_interval(hours => v.hours) END
FROM (VALUES
  ('บราวนี่', 'adopted', 480),
  ('หิมะ', 'pending', 0),
  ('ทองแท่ง', 'adopted', 336),
  ('กีวี่', 'adopted', 216),
  ('หมวกแดง', 'cancelled', 120),
  ('ขนมปัง', 'pending', 0),
  ('ปุยฝ้าย', 'cancelled', 456)
) AS v(pet, status, hours) JOIN sc_pet s ON s.name = v.pet WHERE p.id = s.id;

-- trigger ใช้เวลา now() — ย้อนเวลาข้อความระบบ/การปิดห้องให้ตรงกับวันที่เปลี่ยนสถานะจริง
WITH t AS (
  SELECT c.id AS conv_id, now() - make_interval(hours => v.hours) AS at FROM (VALUES
    ('บราวนี่', 480),
    ('ทองแท่ง', 336),
    ('กีวี่', 216),
    ('ปุยฝ้าย', 456),
    ('หมวกแดง', 120)
  ) AS v(pet, hours) JOIN sc_pet s ON s.name = v.pet JOIN conversations c ON c.pet_id = s.id),
m AS (UPDATE messages SET created_at = t.at FROM t WHERE messages.conversation_id = t.conv_id AND messages.kind = 'system')
UPDATE conversations c SET closed_at = t.at, last_message_at = t.at FROM t WHERE c.id = t.conv_id;
-- ข้อความระบบนับเป็น unread ของผู้ทัก — ถือว่าเปิดอ่านแล้วทั้งคู่
SELECT mark_conversation_read(c.id, c.initiator_id), mark_conversation_read(c.id, c.owner_id)
FROM conversations c JOIN sc_pet s ON s.id = c.pet_id WHERE c.status = 'closed';

-- ---------- รายงาน (2 รายการ ไม่ถึงเกณฑ์ 5 ที่ deck จะซ่อนประกาศ) ----------
INSERT INTO reports (reporter_id, reported_pet_id, reason, detail, created_at)
SELECT u.id, s.id, v.reason::report_reason, v.detail, now() - make_interval(hours => v.hours) FROM (VALUES
  ('nok.retired', 'ซูก้า', 'other', 'ชูการ์ไกลเดอร์ต้องมีใบอนุญาตครอบครองหรือเปล่าคะ รบกวนแอดมินช่วยตรวจสอบ', 30),
  ('prae.family', 'ซูก้า', 'other', 'ไม่แน่ใจว่าสัตว์ชนิดนี้ลงประกาศได้ไหม', 6)
) AS v(username, pet, reason, detail, hours) JOIN users u ON u.username = v.username JOIN sc_pet s ON s.name = v.pet;

COMMIT;

-- ---------- สรุปผล ----------
SELECT 'users' AS ตาราง, count(*) AS จำนวน FROM users WHERE email LIKE '%@petpaws.showcase'
UNION ALL SELECT 'pets',       count(*) FROM pets p JOIN users u ON u.id = p.owner_id WHERE u.email LIKE '%@petpaws.showcase'
UNION ALL SELECT 'pet_media',  count(*) FROM pet_media m JOIN pets p ON p.id = m.pet_id JOIN users u ON u.id = p.owner_id WHERE u.email LIKE '%@petpaws.showcase'
UNION ALL SELECT 'likes',      count(*) FROM likes l JOIN pets p ON p.id = l.pet_id JOIN users u ON u.id = p.owner_id WHERE u.email LIKE '%@petpaws.showcase'
UNION ALL SELECT 'conversations', count(*) FROM conversations c JOIN pets p ON p.id = c.pet_id JOIN users u ON u.id = p.owner_id WHERE u.email LIKE '%@petpaws.showcase'
UNION ALL SELECT 'messages',   count(*) FROM messages m JOIN conversations c ON c.id = m.conversation_id JOIN pets p ON p.id = c.pet_id JOIN users u ON u.id = p.owner_id WHERE u.email LIKE '%@petpaws.showcase';
