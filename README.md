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

> **ทุกเครื่องในทีมต้องใช้ Flutter 3.44.3** (รุ่นเดียวกับ CI — ดู `.fvmrc`, `.github/workflows/ci.yml`)
> รุ่นอื่นจะเขียน `pubspec.lock` ไม่ตรงกับที่ CI ต้องการ (`flutter pub get --enforce-lockfile`) ทำให้ job Mobile (Flutter) แดง
> ติดตั้ง: `git clone --depth 1 --branch 3.44.3 https://github.com/flutter/flutter.git flutter-3.44.3` แล้วใช้ `flutter-3.44.3/bin` ใน PATH
> ถ้า `pubspec.lock` ถูกแก้โดยไม่ตั้งใจ ให้ `git restore pubspec.lock` ก่อน commit

## หมายเหตุ

- **แอปชี้เซิร์ฟเวอร์จริงบน EC2 เป็นค่าเริ่มต้น** (`ApiClient.baseUrl`) — `git pull` แล้ว `flutter run -d chrome` ก็ใช้งานได้เลย ไม่ต้องรัน backend/DB เอง ถ้าพัฒนา backend ในเครื่อง ให้ชี้กลับด้วย `flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000` (Android emulator ใช้ `http://10.0.2.2:3000`)
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
| GET | `/admin/perf-stats` | จำนวนคำขอ/เวลาแต่ละ API (เรียงตามจำนวนครั้งมากสุด) + 15 SQL queries ที่ใช้เวลารวมมากสุดจาก `pg_stat_statements` |
| GET | `/admin/cache-stats` | hit/miss รวมและแยกกลุ่ม พร้อมสถานะ Redis |
| POST | `/admin/cache-stats/reset` | เริ่มนับ Cache hit/miss ใหม่ โดยไม่ลบข้อมูลที่ cache ไว้ |

แบนหมดเวลาแล้วปลดเองอัตโนมัติ (ล็อกอินได้ ประกาศกลับมาใน deck) · แบนแอดมินด้วยกัน/แบนตัวเองไม่ได้ · access token ที่ออกไปก่อนแบนยังใช้ได้อีกไม่เกิน 15 นาที

เปิด **Monitoring** จากไอคอนบนแดชบอร์ดแอดมินเพื่อดูแท็บ **API / SQL / Cache** (รีเฟรชทุก 15 วินาที): API แสดงจำนวนครั้ง เวลาเฉลี่ย/สูงสุด/รวม และคำขอที่ใช้เวลา ≥ 500 ms พร้อมเลือกเรียงตามจำนวนครั้งหรือเวลาได้ ส่วน Cache ย้ายมาครบทั้ง hit/miss, TTL, หน่วยความจำ Redis และปุ่มเริ่มนับใหม่

ตัวนับ API เป็นยอดสะสม รวมทุก API instance ผ่าน Redis และไม่นับ Health check/คำขออ่านสถิติ Monitoring ถ้า Redis ใช้ไม่ได้จะแจ้งว่าตัวเลขนับจาก instance เดียวหรือรวมตัวนับสำรองบางส่วน SQL นับแยกจากคำขอ API เพราะคำขอหนึ่งอาจเรียกหลาย queries หรืออ่านจาก Cache; หาก `pg_stat_statements` ยังไม่พร้อม แท็บ API และ Cache ยังใช้งานได้

## เอกสารเพิ่มเติม

| ไฟล์ | เนื้อหา |
|---|---|
| [`SKILL.md`](SKILL.md) | กติกาและขอบเขตของโปรเจกต์ |
| [`ROADMAP.md`](ROADMAP.md) | แผนงานทีละเฟส |
| [`backend/db/README.md`](backend/db/README.md) | โครงฐานข้อมูล กฎที่ DB บังคับเอง และ seed ทั้ง 3 ชุด |

## สำรองข้อมูล (production บน EC2)

- **อัตโนมัติ:** cron บน EC2 รัน `backend/db/backup.sh` ทุกวัน 03:00 UTC (10:00 น. เวลาไทย) และทุกครั้งก่อนรัน migration ตอน deploy ไฟล์อยู่ที่ `/opt/petpaws/backups/` (`db-*.sql.gz` = ฐานข้อมูล, `media-*.tar.gz` = รูปใน MinIO) เก็บ 14 วัน log อยู่ที่ `backups/backup.log`
- **สำรองมือ:** `ssh ubuntu@<IP>` แล้ว `sudo ENV_FILE=/opt/petpaws/.env BACKUP_DIR=/opt/petpaws/backups bash /opt/petpaws/backend/db/backup.sh`
- **กู้คืน** (ล้างข้อมูลปัจจุบันทั้งหมด — หยุด api/worker ก่อน): `docker stop petpaws-api petpaws-worker` → `docker exec -i petpaws-postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"'` → `gunzip -c db-<เวลา>.sql.gz | docker exec -i petpaws-postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1'` → `docker start petpaws-api petpaws-worker`
- ไฟล์สำรองอยู่ดิสก์เดียวกับระบบ กันได้เฉพาะข้อมูลถูกลบ/แก้ผิดพลาด **ดิสก์พังต้องมี EBS snapshot** (AWS Console > EC2 > Lifecycle Manager ตั้งรายวัน เก็บ 7 รอบ)

## แอป Android และการอัพเดต

- ทุกครั้งที่ merge เข้า `main` และ CI ผ่าน workflow **Release** สร้างไฟล์ APK แล้วออก GitHub Release (`v1.0.<เลขรอบ>`) ไฟล์ติดตั้งอยู่ในหน้า Releases ของ repo
- **อัพเดตในแอป:** ตอนเปิดแอปบน Android แอปตรวจ Release ล่าสุด ถ้ามีเลขสูงกว่าที่ติดตั้งอยู่ จะขึ้นกล่อง "Petpaws มีเวอร์ชั่นใหม่แล้ว ต้องการอัพเดตเวอร์ชั่นหรือไม่" กด "อัพเดต" แล้วระบบเปิดลิงก์ดาวน์โหลด APK ให้ติดตั้งทับ (ข้อมูลในแอปไม่หาย) ครั้งแรกที่ติดตั้งผ่านเบราว์เซอร์ Android จะขอสิทธิ์ "ติดตั้งแอปที่ไม่รู้จัก"
- **ต้องเซ็นด้วย keystore ตัวเดียวกันทุกเวอร์ชัน** ไม่งั้น Android ไม่ยอมติดตั้งทับ keystore ตัวจริงเก็บเป็น GitHub Secrets 4 ตัว: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` (Settings > Secrets and variables > Actions) ถ้ายังไม่ตั้ง workflow Release จะหยุดพร้อมข้อความบอก ไม่ปล่อย APK ที่เซ็นผิด
- **ห้ามทำ keystore หาย:** ถ้าหาย แอปที่ติดตั้งไปแล้วจะอัพเดตไม่ได้อีก (ผู้ใช้ต้องถอนแอปแล้วติดตั้งใหม่) เก็บสำรองไฟล์ `.jks` กับรหัสผ่านไว้ที่ปลอดภัยนอก repo ห้ามลง git
- APK ที่ออกก่อนมี keystore ตัวจริง (เซ็นด้วย debug key คนละดอก) ต้องถอนแล้วติดตั้งเวอร์ชันใหม่ครั้งเดียว หลังจากนั้นอัพเดตทับได้ตลอด
- ทุก merge เข้า `main` ออก Release ใหม่ (แม้แก้เฉพาะ backend) ผู้ใช้จะเห็นแจ้งอัพเดตทุกครั้ง

## ยืนยันอีเมลตอนสมัคร

- สมัครแล้วระบบส่งลิงก์ไปทางอีเมล (กดยืนยันได้เลย ไม่ใช่รหัส OTP) ต้องกดก่อนถึงล็อกอินได้ ลิงก์อยู่ได้ 24 ชั่วโมง ขอส่งซ้ำได้ทุก 60 วินาที
- บัญชีที่มีอยู่ก่อนเปิดระบบนี้ถือว่ายืนยันแล้ว (migration `017`) ไม่ถูกล็อกเอาท์
- **เปิดใช้งานจริง:** ใส่ `BREVO_API_KEY` และ `MAIL_FROM_EMAIL` ใน `.env` ของ production (เข้ารหัสด้วย SOPS) ดูขั้นตอนใน `.env.production.example` ยังไม่ใส่ = ระบบอีเมลปิด ไม่บังคับยืนยัน
- **dev/ทดสอบ:** ตั้ง `MAIL_PROVIDER=log` แล้วดูลิงก์ยืนยันใน log ของ API (ไม่ส่งอีเมลจริง)
- ลิงก์ในอีเมลชี้ไปที่ `APP_PUBLIC_URL` (ค่าเริ่มต้นใน `docker-compose.prod.yml`) ถ้าเปลี่ยนที่อยู่เซิร์ฟเวอร์ต้องแก้ค่านี้ด้วย

## ลืมรหัสผ่าน (ส่งลิงก์ทางอีเมล)

- แอปเรียก `POST /auth/forgot-password` `{email}` → ระบบส่งอีเมลลิงก์ `GET /auth/reset-password?token=...` (อายุ 30 นาที ใช้ได้ครั้งเดียว) ตอบข้อความเดียวกันเสมอไม่ว่ามีบัญชีหรือไม่ และ **ไม่คืน token ใน response** (ต้องได้จากกล่องอีเมลเท่านั้น) ขอซ้ำได้ทุก 60 วินาทีต่อบัญชี
- ผู้ใช้กดลิงก์ → เบราว์เซอร์เปิดหน้าฟอร์มตั้งรหัสใหม่ที่ API เสิร์ฟเอง (ฟอร์ม HTML ธรรมดา ไม่ต้องใช้แอป) → `POST /auth/reset-password/form` เปิดหน้าลิงก์เฉยๆ ไม่ใช้ลิงก์ทิ้ง (กันโปรแกรมสแกนอีเมลกดแทน) ลิงก์ถูกใช้ตอนกดบันทึกเท่านั้น
- ตั้งรหัสใหม่สำเร็จ: ทุกอุปกรณ์ที่ล็อกอินค้างถูกเตะออก, ลิงก์อื่นที่ค้างใช้ไม่ได้, บัญชีที่ยังไม่ยืนยันอีเมลถือว่ายืนยันแล้ว (กดลิงก์จากอีเมลได้ = เป็นเจ้าของอีเมล) และมีอีเมลแจ้งเตือนว่ารหัสถูกเปลี่ยน
- มี `POST /auth/reset-password` `{token, newPassword}` (JSON) ไว้ให้ client ที่ถือ token จากลิงก์ ใช้กฎรหัสผ่านเดียวกับตอนสมัคร
- ต้องเปิดระบบอีเมลก่อน (ตั้ง `BREVO_API_KEY` + `MAIL_FROM_EMAIL` เหมือนหัวข้อด้านบน) ถ้าปิดอยู่จะไม่ส่งอะไร (มี log เตือนที่ API)
- ข้อควรระวัง: ตอนนี้ลิงก์เป็น `http://` (ยังไม่มีโดเมน/HTTPS) รหัสผ่านใหม่จึงวิ่งผ่านเครือข่ายแบบไม่เข้ารหัส เหมือนการล็อกอินของแอปตอนนี้ ควรทำ HTTPS ก่อนเปิดให้คนทั่วไปใช้
