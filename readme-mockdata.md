# วิธีรัน migration + mock data (PowerShell)

## 1. เปิดฐานข้อมูล + migration + mock data (คำสั่งเดียว)

จากโฟลเดอร์ `Project`:

```powershell
.\backend\seed.cmd
```

สคริปต์จะ:

1. เปิด container (postgres, redis, minio) แล้วรอจน postgres พร้อม
2. รัน migration ที่ DB นี้ยังไม่เคยรัน เช่นไฟล์ใหม่ที่เพิ่มหลังสร้าง DB (`initdb` ของ Docker ไม่รันให้)
3. ใส่ `003_demo_accounts.sql` แล้วโชว์จำนวนบัญชี/ประกาศ/ห้องแชท

| บัญชี | รหัสผ่าน |
|---|---|
| `demo01` … `demo10` | `Petpaws1!` |
| `admin` (แอดมิน) | `Petpaws1!` |

รันซ้ำได้ ข้อมูลสาธิตกลับเป็นสภาพเริ่มต้นทุกครั้ง

| ตัวเลือก | ทำอะไร |
|---|---|
| `.\backend\seed.cmd -Reset` | ล้าง DB ทั้งหมด (`docker compose down -v`) แล้วสร้างใหม่ |
| `.\backend\seed.cmd -All` | ใส่ seed ทุกไฟล์ (`001`, `002`, `003`) |

> ประวัติว่ารัน migration ไฟล์ไหนไปแล้วเก็บใน `dev_tools.applied_migrations` (คนละ schema กับตารางของแอป)
> ถ้า migration ไฟล์ไหนล้ม สคริปต์จะหยุดและโชว์ error ของ psql

## 2. เปิด backend

```powershell
cd backend\api
npm install
npm run start:dev
```

เช็ก: http://localhost:3000/health ต้องได้ `{"status":"ok","db":"connected"}`

## 3. เปิด worker (อีก terminal)

```powershell
cd backend\api
npm run start:worker:dev
```

ทำงานคิว: ส่ง push แชท + ลบไฟล์รูปค้างทุกคืนตี 3 — ขึ้น `PetPaws worker started` = พร้อม

## ถ้า DB พัง / อยากเริ่มใหม่หมด

```powershell
.\backend\seed.cmd -Reset
```

ลบข้อมูลทั้งหมด (รวมบัญชีที่สมัครเองตอนทดสอบ) แล้วสร้าง DB + mock data ใหม่
