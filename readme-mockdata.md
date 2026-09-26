# วิธีรัน migration + mock data (PowerShell)

## 1. เปิดฐานข้อมูล

```powershell
cd backend
docker compose up -d
```

DB ใหม่ (สร้างครั้งแรก) จะรัน migration ทุกไฟล์ใน `db/migrations/` ให้อัตโนมัติ

## 2. รัน migration ที่เพิ่มมาใหม่ (เฉพาะ DB ที่มีอยู่แล้ว)

ถ้าเคย `docker compose up` มาก่อนแล้ว migration ใหม่จะไม่รันเอง ต้องรันมือครั้งเดียว:

```powershell
Get-Content db\migrations\013_suspension_expiry.sql -Raw -Encoding UTF8 | docker exec -i petpaws-postgres psql -U petpaws -d petpaws -v ON_ERROR_STOP=1
```

รันซ้ำได้ไม่พัง

## 3. ใส่ mock data

```powershell
Get-Content db\seeds\003_demo_accounts.sql -Raw -Encoding UTF8 | docker exec -i petpaws-postgres psql -U petpaws -d petpaws -v ON_ERROR_STOP=1
```

| บัญชี | รหัสผ่าน |
|---|---|
| `demo01` … `demo10` | `Petpaws1!` |
| `admin` (แอดมิน) | `Petpaws1!` |

รันซ้ำได้ ข้อมูลกลับเป็นสภาพเริ่มต้น

## 4. เปิด backend

```powershell
cd api
npm install
npm run start:dev
```

เช็ก: http://localhost:3000/health ต้องได้ `{"status":"ok","db":"connected"}`

## 5. เปิด worker (อีก terminal)

```powershell
cd backend\api
npm run start:worker:dev
```

ทำงานคิว: ส่ง push แชท + ลบไฟล์รูปค้างทุกคืนตี 3 — ขึ้น `PetPaws worker started` = พร้อม

## ถ้า DB พัง / อยากเริ่มใหม่หมด

```powershell
cd backend
docker compose down -v
docker compose up -d
```

`-v` ลบข้อมูลทั้งหมด แล้ว migration ทุกไฟล์ (รวม 013) จะรันใหม่อัตโนมัติ — จากนั้นรันขั้นที่ 3 ต่อ
