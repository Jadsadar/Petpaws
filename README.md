# PetPaws

แอปหาบ้านให้สัตว์เลี้ยง — Flutter (web) + NestJS + PostgreSQL

## เริ่มใช้งานหลัง clone/pull

ต้องมี **Docker**, **Node.js 20+** และ **Flutter SDK** ติดตั้งไว้ก่อน

### 1. ตั้งค่า environment

```bash
cd backend
cp .env.example .env
```

ค่าเริ่มต้นใน `.env.example` ใช้ได้เลยสำหรับ dev ไม่ต้องแก้อะไร

### 2. เปิดฐานข้อมูลและ storage

```bash
# จากโฟลเดอร์ backend/
docker compose up -d
```

ครั้งแรกที่ container ถูกสร้าง ไฟล์ใน `db/migrations/` จะถูกรันให้อัตโนมัติ (18 ตาราง)

### 3. ใส่ข้อมูลตัวอย่าง ← ข้ามขั้นนี้ไม่ได้ถ้าอยากมีของให้เล่น

```bash
# จากโฟลเดอร์ backend/ (bash / WSL / macOS)
docker compose exec -T postgres psql -U petpaws -d petpaws -v ON_ERROR_STOP=1 < db/seeds/003_demo_accounts.sql
```

ถ้าใช้ **PowerShell** ต้องใช้แบบนี้แทน (PowerShell ไม่รองรับ `<` สำหรับ redirect เข้า stdin):

```powershell
# จากโฟลเดอร์ backend/
Get-Content db\seeds\003_demo_accounts.sql -Raw -Encoding UTF8 | docker exec -i petpaws-postgres psql -U petpaws -d petpaws -v ON_ERROR_STOP=1
```

จะได้ **10 บัญชีที่ลงประกาศไว้แล้ว** พร้อมรูป แท็ก ข้อมูลติดต่อ การกดถูกใจ และห้องแชท

| | |
|---|---|
| ชื่อผู้ใช้ | `demo01` … `demo10` (ใช้อีเมล `demo01@petpaws.demo` ก็ได้) |
| แอดมิน | `admin` — `demo10` ถูกรายงานไว้ 10 คนแล้ว เห็นในหน้าแอดมินทันที |
| รหัสผ่าน | `Petpaws1!` (เหมือนกันทุกบัญชี) |

ทุกบัญชีกรอกโปรไฟล์ไว้แล้ว ล็อกอินเสร็จเข้าหน้าหลักได้เลย · รันซ้ำได้ไม่พัง

> seed ชุดอื่นดูที่ [`backend/db/README.md`](backend/db/README.md) — `001`/`002` ล็อกอิน**ไม่ได้** (แฮชรหัสผ่านเป็นค่าสมมติ) ใช้ทดสอบ query เท่านั้น

> **DB ที่สร้างไว้ก่อนมี migration 013** (volume ไม่ว่าง) ต้องรันเพิ่มครั้งเดียว ไม่งั้นแบนที่หมดเวลาแล้วประกาศจะยังถูกซ่อน:
> ```powershell
> Get-Content db\migrations\013_suspension_expiry.sql -Raw -Encoding UTF8 | docker exec -i petpaws-postgres psql -U petpaws -d petpaws -v ON_ERROR_STOP=1
> ```

### 4. เปิด backend API

```bash
cd backend/api
npm install
npm run start:dev
```

เช็กว่าขึ้นแล้ว: เปิด http://localhost:3000/health ต้องได้ `{"status":"ok","db":"connected"}`

เปิด **worker** อีก terminal (ส่ง push แชท + ลบไฟล์รูปค้างทุกคืน — ไม่เปิดแอปก็ใช้ได้ แค่งานพวกนี้จะค้างในคิวรอ):

```bash
cd backend/api
npm run start:worker:dev
```

ขึ้น `PetPaws worker started` = พร้อม · ถ้ายังไม่ได้ใส่ `FCM_*` ใน `.env` จะขึ้นเตือนและข้ามการส่ง push (ปกติตอน dev)

### 5. เปิดแอป

```bash
# จากโฟลเดอร์โปรเจกต์หลัก
flutter pub get
flutter run -d chrome
```

## หมายเหตุ

- **แอปรันเป็น web เท่านั้นตอนนี้** (ยังไม่มีโฟลเดอร์ `android/` `ios/`) — `ApiClient.baseUrl` จึง hardcode เป็น `http://localhost:3000` ถ้าจะลงมือถือต้อง `flutter create --platforms=android .` ก่อนแล้วเปลี่ยน URL เป็น `10.0.2.2` (Android emulator) หรือ IP เครื่อง
- **backend ต้องรันอยู่เสมอ** ไม่งั้นหน้า login จะค้าง (ยังไม่มี timeout ฝั่ง client)
- **แก้ไฟล์ migration แล้วไม่มีผล** เพราะกลไก `docker-entrypoint-initdb.d` รันครั้งเดียวตอน volume ว่าง ต้อง `docker compose down -v` (ล้างข้อมูลทั้งหมด) แล้ว `up -d` ใหม่ จากนั้นรัน seed ซ้ำ

## Admin API

ทุก endpoint ต้องล็อกอินด้วยบัญชีที่ `is_admin = true` (คนอื่นได้ 403) — ไม่มี endpoint ให้ยกระดับตัวเอง ตั้งแอดมินผ่าน SQL เท่านั้น:

```sql
UPDATE users SET is_admin = true WHERE username = '...';
```

| Method | Path | ทำอะไร |
|---|---|---|
| GET | `/admin/reported-users?minReports=10` | ผู้ใช้ที่โดนรายงานค้าง ≥ เกณฑ์ (นับรวมรายงานตัวผู้ใช้ + ประกาศ + ข้อความ จากคนรายงานไม่ซ้ำ) |
| GET | `/admin/users/:id/reports` | รายละเอียดรายงานค้างของคนนั้น |
| POST | `/admin/users/:id/ban` | `{ "days": 7, "note": "..." }` — ไม่ส่ง `days` = แบนถาวร · เตะออกทุกเครื่อง · ปิดรายงานค้างเป็น `actioned` |
| POST | `/admin/users/:id/unban` | ปลดแบน |
| POST | `/admin/users/:id/dismiss-reports` | ยกรายงานค้าง (ตัดสินว่าไม่ผิด) |
| GET | `/admin/banned-users` | คนที่แบนอยู่ตอนนี้ |

แบนหมดเวลาแล้วปลดเองอัตโนมัติ (ล็อกอินได้ ประกาศกลับมาใน deck) · แบนแอดมินด้วยกัน/แบนตัวเองไม่ได้ · access token ที่ออกไปก่อนแบนยังใช้ได้อีกไม่เกิน 15 นาที

## เอกสารเพิ่มเติม

| ไฟล์ | เนื้อหา |
|---|---|
| [`SKILL.md`](SKILL.md) | กติกาและขอบเขตของโปรเจกต์ |
| [`ROADMAP.md`](ROADMAP.md) | แผนงานทีละเฟส |
| [`backend/db/README.md`](backend/db/README.md) | โครงฐานข้อมูล กฎที่ DB บังคับเอง และ seed ทั้ง 3 ชุด |
