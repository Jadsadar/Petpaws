#!/bin/bash
# สำรองฐานข้อมูล Postgres (+ รูปใน MinIO) ที่รันอยู่ใน Docker — ตั้งให้รันทุกวันด้วย cron (ดู ansible/deploy.yml)
#
#   bash backend/db/backup.sh
#
# ตัวแปรที่ปรับได้ (ไม่ตั้ง = ใช้ค่าบน EC2):
#   ENV_FILE      ไฟล์ .env ที่มี POSTGRES_USER / POSTGRES_DB   (/opt/petpaws/.env)
#   BACKUP_DIR    โฟลเดอร์เก็บไฟล์สำรอง                          (/opt/petpaws/backups)
#   KEEP_DAYS     เก็บย้อนหลังกี่วัน                              (14)
#   PG_CONTAINER  ชื่อ container postgres                        (petpaws-postgres)
#   MINIO_VOLUME  ชื่อ volume ของ MinIO (ไม่มี volume นี้ = ข้ามรูป) (petpaws-prod_minio_data)
#
# ไฟล์สำรองอยู่ดิสก์เดียวกับระบบ: กันได้เฉพาะข้อมูลถูกลบ/แก้ผิดพลาด ถ้าดิสก์พังต้องใช้
# EBS snapshot ของ AWS ควบคู่ (ดู README หัวข้อ "สำรองข้อมูล")
#
# กู้คืน:  gunzip -c db-YYYYmmdd-HHMMSS.sql.gz | docker exec -i petpaws-postgres sh -c \
#            'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1'
#          (ล้าง schema ก่อน: DROP SCHEMA public CASCADE; CREATE SCHEMA public;)
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/petpaws/.env}"
BACKUP_DIR="${BACKUP_DIR:-/opt/petpaws/backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"
PG_CONTAINER="${PG_CONTAINER:-petpaws-postgres}"
MINIO_VOLUME="${MINIO_VOLUME:-petpaws-prod_minio_data}"

# อ่านชื่อ user/db จาก .env ด้วย grep (ไม่ source ไฟล์ เพราะรหัสผ่านอาจมีอักขระพิเศษ)
if [ -z "${POSTGRES_USER:-}" ] && [ -f "$ENV_FILE" ]; then
  POSTGRES_USER="$(grep '^POSTGRES_USER=' "$ENV_FILE" | head -n1 | cut -d= -f2-)"
fi
if [ -z "${POSTGRES_DB:-}" ] && [ -f "$ENV_FILE" ]; then
  POSTGRES_DB="$(grep '^POSTGRES_DB=' "$ENV_FILE" | head -n1 | cut -d= -f2-)"
fi
: "${POSTGRES_USER:?ไม่พบ POSTGRES_USER (ตั้งตัวแปรหรือใส่ใน ENV_FILE)}"
: "${POSTGRES_DB:?ไม่พบ POSTGRES_DB (ตั้งตัวแปรหรือใส่ใน ENV_FILE)}"

# ไฟล์ชั่วคราวที่ค้างอยู่ (สำรองล้มกลางทาง) ถูกลบเสมอตอนสคริปต์จบ ไม่ว่าสำเร็จหรือล้ม
db_tmp=""
media_tmp=""
trap 'rm -f -- "$db_tmp" "$media_tmp"' EXIT

umask 077
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
stamp="$(date -u +%Y%m%d-%H%M%S)"

# เขียนลงไฟล์ชั่วคราวก่อน แล้วตรวจว่าไฟล์ gzip สมบูรณ์ค่อยเปลี่ยนชื่อ — กันไฟล์สำรองครึ่งๆ กลางๆ
# ไปทับของดีเวลา pg_dump ล้มกลางทาง
db_tmp="$BACKUP_DIR/.db-$stamp.tmp"
docker exec "$PG_CONTAINER" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-acl | gzip > "$db_tmp"
gzip -t "$db_tmp"
if [ "$(wc -c < "$db_tmp")" -lt 500 ]; then
  rm -f "$db_tmp"
  echo "สำรองฐานข้อมูลล้มเหลว: ไฟล์เล็กผิดปกติ" >&2
  exit 1
fi
mv "$db_tmp" "$BACKUP_DIR/db-$stamp.sql.gz"
echo "สำรองฐานข้อมูล: $BACKUP_DIR/db-$stamp.sql.gz ($(wc -c < "$BACKUP_DIR/db-$stamp.sql.gz") bytes)"

# รูป/วิดีโอใน MinIO (เฉพาะ bucket petpaws-media — ไม่เอาไฟล์ตั้งค่าภายในของ MinIO)
if docker volume inspect "$MINIO_VOLUME" >/dev/null 2>&1; then
  media_tmp="$BACKUP_DIR/.media-$stamp.tmp"
  docker run --rm -v "$MINIO_VOLUME":/d:ro alpine tar cz -C /d ./petpaws-media > "$media_tmp"
  gzip -t "$media_tmp"
  mv "$media_tmp" "$BACKUP_DIR/media-$stamp.tar.gz"
  echo "สำรองรูป: $BACKUP_DIR/media-$stamp.tar.gz ($(wc -c < "$BACKUP_DIR/media-$stamp.tar.gz") bytes)"
else
  echo "ข้ามการสำรองรูป: ไม่พบ volume $MINIO_VOLUME"
fi

# ลบไฟล์เก่ากว่า KEEP_DAYS วัน (ลบหลังสำรองใหม่สำเร็จแล้วเท่านั้น)
find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'db-*.sql.gz' -o -name 'media-*.tar.gz' \) -mtime +"$KEEP_DAYS" -delete
echo "เหลือไฟล์สำรอง: $(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'db-*.sql.gz' -o -name 'media-*.tar.gz' \) | wc -l) ไฟล์"
