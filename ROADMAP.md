# PetPaws — แผนงานจนแอปใช้งานได้จริง

เอกสารนี้ไล่ทีละขั้นว่าต้องสร้างอะไรบ้าง เรียงตามลำดับที่ทำได้จริง (ขั้นหลังต้องพึ่งขั้นก่อน)

อ้างอิงกฎจาก [`SKILL.md`](SKILL.md) และโครงฐานข้อมูลใน [`backend/db/README.md`](backend/db/README.md)

---

## สถานะปัจจุบัน

| ส่วน | สถานะ |
|---|---|
| ฐานข้อมูล PostgreSQL (16 ตาราง + 2 ฟังก์ชัน) | ✅ เสร็จ ทดสอบแล้ว รันอยู่ใน Docker |
| Redis | ✅ ใช้เป็นคิวงาน BullMQ แล้ว (ยังไม่ได้ทำ cache) |
| คิวงาน BullMQ | ✅ worker แยก process (`npm run start:worker`) — push แชท + ลบไฟล์ค้างทุกคืน |
| Object storage (S3/MinIO) | ✅ อยู่ใน docker-compose แล้ว |
| **NestJS backend** | ✅ มีครบเกือบทุก phase ดูรายละเอียดในแต่ละ phase ด้านล่าง |
| Flutter app (4,329 บรรทัด) | ⚠️ ยังเรียก Firebase อยู่ / โครงไฟล์ยังไม่ตรง SKILL.md |

**คำตอบสั้น ๆ ว่าตอนนี้ลงประกาศได้ไหม: ยังไม่ได้** — แอปยังวิ่งไป Firebase ไม่ได้แตะ Postgres เลย

---

## ⚠️ 5 เรื่องที่ขัดกันอยู่ ต้องตัดสินใจก่อนเริ่มเขียนโค้ด

ผมเจอระหว่างไล่อ่านโค้ดจริง ทุกข้อกระทบ schema หรือ API โดยตรง ถ้าไม่เคลียร์ก่อนจะต้องรื้อทีหลัง

### 1. มีชุดแท็กนิสัย 3 ชุดที่ไม่ตรงกัน

| ที่อยู่ | เนื้อหา | สถานะ |
|---|---|---|
| `lib/data/mock_data.dart` → `availableTraits` | 8 คำไทย: สายลุย, สายชิล, ชอบอยู่บ้าน, ชอบวิ่งเล่น, รักเด็ก, ติดคน, รักความสงบ, สายสปอร์ต | **ใช้งานจริงอยู่** — หน้าสร้างโปรไฟล์กับหน้าโปรไฟล์ใช้เป็น "นิสัยของผู้ใช้" |
| `lib/utils/pet_tags.dart` → `petTags` | 10 แท็ก slug+label: energetic, chill, affectionate, independent, talkative, quiet, social, kid_friendly, foodie, tidy | **dead code** — ไม่มีไฟล์ไหน import เลย |
| DB ตาราง `traits` (migration 007) | 8 slug ที่ผมแปลงมาจาก `availableTraits` | ผมเพิ่งสร้าง — ผูกกับ **สัตว์** เท่านั้น |

ตรงกันแค่ 3 ตัว (`chill`, `affectionate`, `kid_friendly`) นอกนั้นคนละคำหมด

**ต้องเลือก 1 ชุดแล้วใช้ให้ตรงกันทั้งระบบ** — ผมแนะนำชุดใน `pet_tags.dart` (10 แท็ก) เพราะมี slug ภาษาอังกฤษแยกจากคำแสดงผลอยู่แล้ว ตรงกับวิธีที่ DB เก็บ และครอบคลุมกว่า

---

### 2. DB เก็บข้อมูลโปรไฟล์ที่แอปกรอกอยู่ไม่ได้

หน้าโปรไฟล์ปัจจุบันให้กรอก: `phone`, `lineId`, `fbLink`, `homeType`, `traits` (ของผู้ใช้)

แต่ตาราง `users` ที่ผมสร้างมีแค่: `email, password_hash, display_name, avatar_url, bio, location` (ตาม entity ใน SKILL.md เป๊ะ ๆ)

**→ กดบันทึกโปรไฟล์แล้วข้อมูลติดต่อจะหายหมด** ต้องเพิ่ม migration `009`:
- ตาราง `user_contacts` (phone, line_id, fb_link) — แยกตารางเพราะเป็นข้อมูลส่วนตัว ไม่ควรหลุดไปกับ `GET /users/:id` ของคนอื่น
- คอลัมน์ `home_type` บน `users`
- ตาราง `user_traits` (ถ้าจะทำฟีเจอร์ "จับคู่แท็กผู้ใช้กับแท็กสัตว์" ตามข้อ 3)

---

### 3. เกณฑ์จัดลำดับฟีดขัดกันเอง

| ที่มา | ลำดับความสำคัญ |
|---|---|
| `lib/utils/pet_ranking.dart` (dead code) | 1. แท็กตรงกับผู้ใช้กี่อัน → 2. จังหวัดเดียวกัน → 3. ใหม่สุด |
| `deck_feed()` ใน DB (ผมเพิ่งทำ) | 1. จังหวัด → ภาค → ที่เหลือ → 2. ใหม่สุด |

คนละเกณฑ์กันเลย และ `deck_feed` ตอนนี้**ไม่มีคะแนนจับคู่แท็ก** มีแค่ "กรอง" แท็ก

จาก flow ที่คุณอธิบาย ("ใช้แท็กนิสัย**หรือ**จังหวัด... หาจากใกล้เคียงไปไกลขึ้น") ผมตีความว่าจังหวัดมาก่อน จึงทำแบบนั้นไว้ **ถ้าอยากให้แท็กมาก่อน ต้องแก้ `deck_feed`** (เพิ่ม `user_traits` แล้วคำนวณ match count เป็น sort key แรก)

---

### 4. `userRoles` ขัดกับ SKILL.md ตรง ๆ

`mock_data.dart` มี:
```dart
const List<String> userRoles = [
  'ฉันอยากหาหมาไปเลี้ยง (Adopter)',
  'ฉันมีน้องหมาอยากหาบ้านให้ (Owner/Shelter)'
];
```

แต่ SKILL.md เขียนว่า *"ไม่มีการแบ่งบทบาทเป็นผู้ลงประกาศกับผู้รับเลี้ยงแยกกัน ทุกคนคือ user คนเดียวกันที่ทำได้ทั้งสองอย่าง"*

DB จึงไม่มีคอลัมน์ `role` โดยตั้งใจ → **ต้องถอด `userRoles` ออกจากแอป** (ทั้ง dropdown ในหน้าโปรไฟล์และหน้าสร้างโปรไฟล์)

---

### 5. โค้ดตายที่ต้องลบ

| ไฟล์ | เหตุผล |
|---|---|
| `PetPaws.dart` (root) | โค้ดเก่า **มีร่องรอย reels** ซึ่ง SKILL.md สั่งให้ลบทิ้งทั้งหมด |
| `PetPaws 1.dart` (root) | โค้ดเก่าซ้ำซ้อน |
| `lib/utils/pet_tags.dart` + `lib/utils/pet_ranking.dart` | ไม่มีใคร import — ถ้าเลือกใช้ชุดแท็กนี้ตามข้อ 1 ให้ย้ายเนื้อหาไป `shared/` แทนการลบ |

---

## Phase 0 — เก็บกวาด + ปิดช่องว่าง schema ✅ เสร็จแล้ว

| # | งาน | ผลลัพธ์ที่ตรวจแล้ว |
|---|---|---|
| 0.1 | ลบ `PetPaws.dart`, `PetPaws 1.dart` | ✅ ไม่มี `.dart` เหลือที่ root |
| 0.2 | ถอด `userRoles` ออกจาก `mock_data.dart` + 2 หน้าจอที่ใช้ | ✅ `flutter analyze` ผ่าน ไม่มี error |
| 0.3 | เลือกชุดแท็กเดียว (`petTags` ใน `pet_tags.dart`, 10 แท็ก) แก้ migration `007` + seed ให้ตรง | ✅ `traits` ใน DB ตรงกับ Flutter เป๊ะ |
| 0.4 | เขียน migration `009_user_profile.sql`: `user_contacts`, `users.home_type`, `user_traits` | ✅ 18 ตาราง / verify.sql ผ่าน 23 ข้อ |
| 0.5 | เพิ่ม **MinIO** เข้า `docker-compose.yml` | ✅ รัน healthy — ต้องใช้ `quay.io/minio/minio` ไม่ใช่ Docker Hub (ถูกถอดแล้ว) |
| — | สร้าง seed 10 บัญชีทดสอบ (`002_test_accounts.sql`) | ✅ ครอบคลุม: บัญชีระงับ, adopted, บล็อกสองทาง, proximity ข้ามภาค, report count |

รายละเอียดเต็มอยู่ใน [`backend/db/README.md`](backend/db/README.md)

---

## Phase 1 — โครง NestJS + เชื่อมฐานข้อมูล

> ขนาดงาน: กลาง · **ทุก phase หลังจากนี้พึ่งขั้นนี้ทั้งหมด**

| # | งาน | รายละเอียด |
|---|---|---|
| 1.1 | `nest new backend/api` | โครงโปรเจกต์ + TypeScript |
| 1.2 | ติดตั้ง dependency | `pg`, `@nestjs/config`, `@nestjs/jwt`, `argon2`, `zod` หรือ `class-validator`, `ioredis`, `@nestjs/throttler` |
| 1.3 | **Config module** | อ่าน `.env` + **validate ตอน boot** ถ้าขาด `JWT_ACCESS_SECRET` ต้องพังทันที ไม่ใช่พังตอนมีคนล็อกอิน |
| 1.4 | **Database module** | connection pool ของ `pg` + helper `query<T>()` — ใช้ SQL ดิบตาม `db/README.md` (schema ใช้ partial index / composite FK / deferrable trigger ที่ ORM ประกาศไม่ได้) |
| 1.5 | **Migration runner** | เปลี่ยนจากกลไก `docker-entrypoint-initdb.d` (รันครั้งเดียวตอน volume ว่าง) มาเป็น `node-pg-migrate` ที่จำได้ว่ารันอะไรไปแล้ว — **จำเป็นก่อนขึ้น production** |
| 1.6 | **Error filter + response shape** | รูปแบบ error เดียวกันทั้งระบบตามที่ SKILL.md กำหนด |
| 1.7 | **Global ValidationPipe** | `whitelist: true` — field ที่ไม่ได้ประกาศใน DTO ถูกตัดทิ้ง ไม่หลุดไปถึง SQL |
| 1.8 | **Health check** `GET /health` | เช็ก Postgres + Redis ต่อติดจริง |

---

## Phase 2 — Auth (JWT)

> ขนาดงาน: กลาง-ใหญ่ · พึ่ง Phase 1 · **ทุก endpoint อื่นพึ่งขั้นนี้**

SKILL.md กำหนดไว้ละเอียดมาก ต้องทำให้ครบทุกข้อ

| # | งาน | จุดที่พลาดบ่อย |
|---|---|---|
| 2.1 | `POST /auth/register` | แฮชด้วย **argon2** เท่านั้น / ห้าม log รหัสผ่าน |
| 2.2 | `POST /auth/login` | ตอบ error เดียวกันไม่ว่าอีเมลผิดหรือรหัสผิด (กันเดาว่ามีอีเมลนี้ในระบบไหม) |
| 2.3 | `POST /auth/refresh` | **หมุน token ทุกครั้ง** + ตรวจการใช้ซ้ำ → ถ้าเจอ token เก่าถูกใช้อีก ให้เพิกถอนทั้ง `family_id` (ตาราง `refresh_tokens` รองรับไว้แล้ว) |
| 2.4 | `POST /auth/logout` | เพิกถอน refresh token ปัจจุบัน |
| 2.5 | `POST /auth/forgot-password` + `/reset-password` | ใช้ตาราง `password_reset_tokens` (หน้าจอกลุ่ม 1 ใน SKILL.md มี "ลืมรหัสผ่าน") |
| 2.6 | **Global JWT guard** | เปิดเป็นค่าเริ่มต้นทุก route แล้วใช้ `@Public()` ยกเว้นเฉพาะ register/login/refresh — *"ถ้าลืมใส่ก็ต้องปิดไว้ก่อน ไม่ใช่เปิดไว้ก่อน"* |
| 2.7 | **Rate limit** | login 5/นาที/IP, ส่งข้อความ 30/นาที/user, ปัด 100/นาที/user (ThrottlerGuard + Redis) |
| 2.8 | **Ownership guard** | helper ตรวจ `pet.owner_id === req.user.id` ใช้ซ้ำได้ทุกที่ |

---

## Phase 3 — Pets + Media (ลงประกาศ)

> ขนาดงาน: กลาง · พึ่ง Phase 2

| # | Endpoint | หมายเหตุ |
|---|---|---|
| 3.1 | `POST /media/upload-url` | ออก presigned URL + บันทึกลง `media_uploads` (กันไฟล์ orphan) |
| 3.2 | `POST /pets` | รับ `mediaKeys[]` ที่อัปเสร็จแล้ว → เขียน `pets` + `pet_media` + `pet_traits` **ใน transaction เดียว** แล้ว mark `media_uploads.claimed_at` |
| 3.3 | `GET /pets/:id` | ประกาศ + รูปทั้งหมด + แท็ก + ข้อมูลเจ้าของ **ใน query เดียว** (ห้าม N+1) |
| 3.4 | `PATCH /pets/:id` | ตรวจ ownership / เปลี่ยน `status` ได้ (`available`/`pending`/`adopted`) |
| 3.5 | `DELETE /pets/:id` | **soft delete** (`deleted_at`) เท่านั้น — DB ตั้ง `allow delete: if false` ไว้แล้ว |
| 3.6 | `GET /users/:id` | โปรไฟล์ + ประกาศทั้งหมดของเขา (รวมตัวที่ `adopted` พร้อมป้าย) — **ไม่ส่ง `user_contacts` ถ้าไม่ใช่เจ้าของ** |
| 3.7 | `PATCH /users/me` | แก้โปรไฟล์ + `user_contacts` + `user_traits` |
| 3.8 | `GET /traits` | ส่งลิสต์แท็กให้ฟอร์มใช้ (แทนการ hardcode ในแอป) |
| 3.9 | ✅ **BullMQ job** (#22): ทุกคืนตี 3 ลบไฟล์ใน `uploads/` ที่ค้างเกิน 24 ชม. และไม่มี `pet_media.url` / `users.avatar_url` อ้างถึง | เทียบจากของจริงใน DB แทน `media_uploads.claimed_at` เพราะ media module ยังไม่ได้เขียนตารางนั้น (ไม่ต้องแก้ schema) — ถ้าไฟล์เยอะจนช้าค่อยย้ายไปใช้ `media_uploads` |

---

## Phase 4 — Flutter เชื่อม API ครั้งแรก 🎯

> ขนาดงาน: กลาง · **จุดนี้คือจุดที่ "ลงประกาศได้จริง"**

| # | งาน | รายละเอียด |
|---|---|---|
| 4.1 | ถอด Firebase ออกจาก `pubspec.yaml` | ลบ `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage` + ลบ `lib/firebase_options.dart` |
| 4.2 | เพิ่ม `dio` + `flutter_secure_storage` | เก็บ JWT ใน secure storage ไม่ใช่ SharedPreferences |
| 4.3 | สร้าง `shared/api/api_client.dart` | interceptor แนบ access token + **auto refresh ตอนเจอ 401** แล้วยิงซ้ำ |
| 4.4 | เขียน `features/auth/api.dart` ใหม่ | แทนที่ `lib/services/auth_service.dart` ทั้งไฟล์ |
| 4.5 | เขียน `features/profile/api.dart` | โปรไฟล์ + ลงประกาศ + อัปรูปผ่าน presigned URL |
| 4.6 | รื้อ `upload_screen.dart` | เรียก `POST /media/upload-url` → อัปขึ้น S3 → `POST /pets` |
| 4.7 | **ย้ายปุ่ม "ลงประกาศ" เข้าไปในหน้าโปรไฟล์** | SKILL.md ระบุว่าหน้า Profile คือที่อยู่ของปุ่มลงประกาศ/แก้ไข/ลบ (ตอนนี้เป็น tab แยก = หน้าที่ 7 ที่ไม่ควรมี) |

**✅ จบ Phase 4 = สมัคร → ล็อกอิน → ลงประกาศ → เห็นประกาศบนโปรไฟล์ตัวเองและของคนอื่นได้**

---

## Phase 5 — Deck / หน้าค้นหา

> ขนาดงาน: กลาง · พึ่ง Phase 4

| # | งาน | หมายเหตุ |
|---|---|---|
| 5.1 | `GET /deck?cursor=&traits=&province=` | เรียก `deck_feed()` ที่ทำไว้แล้ว — logic กรองอยู่ใน DB หมดแล้ว |
| 5.2 | **Redis cache 30-60 วินาที** | SKILL.md กำหนดไว้เป็นข้อบังคับ + invalidate เมื่อมีการปัดหรือมีประกาศใหม่ |
| 5.3 | รื้อ `discover_screen.dart` | ดึงจาก API + **prefetch 3-5 ใบถัดไป** + preload รูปแรก |
| 5.4 | 3 สถานะครบทุกหน้า | loading (skeleton) / empty (ชวนทำอะไรต่อ) / error (ปุ่มลองใหม่) |
| 5.5 | UI ตัวกรองแท็ก + จังหวัด | |

---

## Phase 6 — Likes

> ขนาดงาน: เล็ก · พึ่ง Phase 5

| # | งาน | หมายเหตุ |
|---|---|---|
| 6.1 | `POST /pets/:id/like` และ `/pass` | DB มี trigger กัน "ปัดสัตว์ตัวเอง" ไว้แล้ว |
| 6.2 | `GET /likes?cursor=` | keyset pagination |
| 6.3 | รื้อ `favorites_screen.dart` | |
| 6.4 | **ปัดแบบ optimistic** | ตอบสนองทันที ยิง API เบื้องหลัง พังแล้วค่อยคืนการ์ด |
| 6.5 | 🔴 **แก้ปุ่ม "ถูกใจและแชท"** | ปุ่มนี้ในหน้า deck สร้างห้องแชททันทีที่กดถูกใจ → **ผิดกฎ SKILL.md ตรง ๆ** ("การกดถูกใจต้องไม่สร้างห้องแชทอัตโนมัติ") และ DB จะปฏิเสธด้วย constraint trigger |

---

## Phase 7 — Chat + WebSocket

> ขนาดงาน: ใหญ่ · พึ่ง Phase 4

| # | งาน | หมายเหตุ |
|---|---|---|
| 7.1 | `GET /conversations` | รายการห้อง + unread count — อ่านจากคอลัมน์ `*_unread_count` ที่ trigger ดูแลอยู่ (ไม่ใช่ `COUNT(*)` = N+1) |
| 7.2 | `POST /conversations` | **ต้องมีข้อความแรกเสมอ** — ส่งห้องเปล่าไป DB จะปฏิเสธตอน COMMIT |
| 7.3 | `GET /conversations/:id/messages?cursor=` | keyset pagination + ตรวจว่าเป็นคู่สนทนาจริง |
| 7.4 | `POST /conversations/:id/messages` | |
| 7.5 | `POST /conversations/:id/read` | เรียกฟังก์ชัน `mark_conversation_read()` |
| 7.6 | ✅ **WebSocket gateway** (#24) | namespace `/chat` · ตรวจ JWT เป็น middleware ตอน handshake (token ผิด → `connect_error: unauthorized` แอปใช้แยกจากเน็ตหลุดแล้ว refresh เอง) · ห้อง `user:{id}` (เข้าอัตโนมัติ) + `conversation:{id}` (ต้อง `join` ผ่านการตรวจคู่สนทนา) · event: `message`, `read`, `typing`, `notification` · การส่ง/อ่านยังผ่าน REST เดิมทั้งหมด รูปแบบ response ไม่เปลี่ยน |
| 7.7 | ⏳ **Redis adapter** | ยังไม่ทำ — ตอนนี้ถูกต้องเฉพาะ API instance เดียว ถ้ารันหลาย instance ต้องเพิ่ม `@socket.io/redis-adapter` ไม่งั้นข้อความข้ามเครื่องไม่ถึงกัน |
| 7.8 | ✅ รื้อ `chat_screen.dart` + `chat_inbox_screen.dart` (#25) | REST โหลดประวัติครั้งแรก + WS อัปเดตสด ไม่ poll แล้ว · reconnect อัตโนมัติ + ดึง REST ซ้ำหลังต่อใหม่ · โชว์ "กำลังพิมพ์..." / "อ่านแล้ว" (สถานะอ่านมาจาก event สดเท่านั้น ประวัติเก่าไม่มีเพราะ REST เดิมไม่ส่ง `read_at`) |

---

## Phase 8 — Moderation

> ขนาดงาน: เล็ก · พึ่ง Phase 7

| # | งาน |
|---|---|
| 8.1 | `POST /reports` (ประกาศ / ผู้ใช้ / ข้อความ) |
| 8.2 | `POST /blocks` + `DELETE /blocks/:userId` — DB ปิดห้องแชทให้อัตโนมัติผ่าน trigger |
| 8.3 | **ย้ายปุ่มรายงานไปหน้า pet detail และหน้าแชท** (ตอนนี้อยู่หน้า deck ซึ่งกดยาก) |
| 8.4 | เพิ่มปุ่มบล็อกในหน้าแชท |

---

## Phase 9 — Push notification

> ขนาดงาน: กลาง · พึ่ง Phase 7 · **เลื่อนไปทีหลังได้**

| # | งาน |
|---|---|
| 9.1 | ✅ `POST /devices` เก็บ FCM token ลง `device_tokens` |
| 9.2 | ✅ **BullMQ worker** (#23) ส่ง noti เมื่อมีข้อความใหม่ — API แค่ enqueue ไม่รอ FCM, retry 3 ครั้ง exponential, ลบ token ที่ FCM ตอบว่าตายแล้ว · ⚠️ ต้องใส่ `FCM_*` ใน `.env` ก่อน ไม่งั้น worker ข้ามการส่ง |
| 9.3 | ตั้งค่า FCM ฝั่ง Flutter (web ต้องมี service worker + VAPID key) |
| 9.4 | job กวาด token ที่ `last_seen_at` เก่าเกิน 60 วัน (token ที่ FCM ปฏิเสธถูกลบใน 9.2 แล้ว ข้อนี้เหลือแค่ token ที่เงียบหายไปเฉย ๆ) |

---

## Phase 10 — จัดโครงไฟล์ Flutter ตาม SKILL.md

> ขนาดงาน: กลาง · ทำคู่ขนานไปกับ Phase 4-8 ได้

ตอนนี้เป็น **type-based** (`screens/`, `services/`, `widgets/`) แต่ SKILL.md บังคับ **feature-based**:

```
lib/
├── features/
│   ├── auth/       (login, register, forgot password)
│   ├── swipe/      (deck, การ์ด, gesture)
│   ├── pet_detail/
│   ├── profile/    (โปรไฟล์ + โพสสัตว์ + ฟอร์มลงประกาศ)
│   ├── likes/
│   └── chat/
├── shared/         (api client, ui primitives, utils ที่ใช้ ≥2 ฟีเจอร์)
└── app/            (routing, providers, tab bar)
```

**กฎที่ต้องรักษา:** ห้าม import ข้าม feature ตรง ๆ — ถ้าต้องใช้ร่วมกันให้ย้ายขึ้น `shared/`

**เช็ก spaghetti ก่อนส่ง:** ไฟล์เกิน ~250 บรรทัด, logic ซ้ำ ≥2 ที่, fetch API ตรงใน component, ชื่อแปลก ๆ

---

## Phase 11 — Test

> ขนาดงาน: กลาง · ทำคู่ขนานไปเรื่อย ๆ

| # | งาน |
|---|---|
| 11.1 | Backend e2e: auth flow (register → login → refresh → reuse detection) |
| 11.2 | Backend e2e: ownership (คนอื่นแก้ประกาศเราไม่ได้ / อ่านแชทคนอื่นไม่ได้) |
| 11.3 | Backend: deck ไม่มีสัตว์ตัวเอง / ไม่มีตัวที่ปัดแล้ว |
| 11.4 | Flutter: unit test ของ service layer |
| 11.5 | รัน `db/verify.sql` ใน CI (23 ข้อ) |

---

## สรุป endpoint ทั้งหมดที่ต้องมี

```
POST   /auth/register            POST /auth/login       POST /auth/refresh    POST /auth/logout
POST   /auth/forgot-password     POST /auth/reset-password

GET    /deck?cursor=&traits=&province=
POST   /pets/:id/like            POST /pets/:id/pass
GET    /likes?cursor=

GET    /pets/:id                 POST /pets             PATCH /pets/:id       DELETE /pets/:id
POST   /media/upload-url
GET    /traits

GET    /users/:id                PATCH /users/me

GET    /conversations            POST /conversations
GET    /conversations/:id/messages?cursor=
POST   /conversations/:id/messages
POST   /conversations/:id/read
WS     /chat

POST   /reports                  POST /blocks           DELETE /blocks/:userId
POST   /devices
GET    /health
```

รวม **~24 endpoint + 1 WebSocket gateway**

---

## เส้นทางสั้นที่สุดถึง "ลงประกาศได้"

ถ้าเป้าหมายเฉพาะหน้าคือให้ลงประกาศได้เร็วที่สุด ข้ามได้หลายอย่าง:

```
Phase 0.4  เพิ่ม migration user_contacts / user_traits
   ↓
Phase 1    โครง NestJS + เชื่อม Postgres            ← ขาดไม่ได้
   ↓
Phase 2.1  POST /auth/register                      ← ขาดไม่ได้ (pets ต้องรู้ว่าใครโพสต์)
Phase 2.2  POST /auth/login
Phase 2.6  JWT guard
   ↓
Phase 3.2  POST /pets                               ← ยังไม่ต้องมีรูปก็ได้
Phase 3.6  GET /users/:id                           ← ไว้ดูว่าโพสต์ขึ้นจริง
   ↓
Phase 4.1-4.6  Flutter: ถอด Firebase + ต่อ API ใหม่
```

**เลื่อนไปทีหลังได้ทั้งหมด:** deck, likes, chat, WebSocket, รายงาน, บล็อก, push, MinIO (ลงประกาศโดยไม่ใส่รูปไปก่อน)

---

## สิ่งที่ต้องรู้ก่อนเริ่ม

**1. ข้อมูลใน Firebase จะไม่ถูกย้ายมา** — บัญชีและประกาศที่เคยสร้างไว้บน Firestore จะใช้ไม่ได้ ต้องสมัครใหม่หมด (ถ้ามีข้อมูลจริงที่ต้องเก็บ ต้องเขียนสคริปต์ย้ายเพิ่ม)

**2. `docker-entrypoint-initdb.d` ใช้บน production ไม่ได้** — ตอนนี้แก้ไฟล์ migration แล้วต้อง `docker compose down -v` (ล้างข้อมูลทิ้ง) ถึงจะมีผล ต้องเปลี่ยนเป็น migration runner จริงใน Phase 1.5

**3. ORM ยังไม่ได้เลือก** — schema ใช้ partial index, composite FK, deferrable trigger ที่ ORM ส่วนใหญ่ประกาศไม่ได้ ถ้าเลือก TypeORM/Prisma ให้ตั้ง `synchronize: false` แล้วใช้ SQL ดิบเป็นแหล่งความจริง อย่าให้ ORM สร้างตารางเอง

**4. Flutter เป็น web-only ตอนนี้** — ไม่มีโฟลเดอร์ `android/` `ios/` ถ้าจะลงมือถือต้อง `flutter create --platforms=android .` ก่อน
