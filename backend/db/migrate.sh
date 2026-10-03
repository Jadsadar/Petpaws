#!/bin/sh
# รัน migration ที่ยังไม่เคยรันบน Postgres ที่ทำงานอยู่ใน container (ใช้ตอน deploy)
#
#   POSTGRES_USER=petpaws POSTGRES_DB=petpaws sh backend/db/migrate.sh [โฟลเดอร์ migrations]
#
# ทำไมต้องมี: docker-entrypoint-initdb.d รันไฟล์ใน db/migrations/ "ครั้งเดียวตอน volume ว่าง"
# เท่านั้น — ไฟล์ migration ใหม่ที่เพิ่มทีหลังจะไม่ถูกรันบน DB production เดิมเลย
# ถ้าไม่มีสคริปต์นี้ โค้ดใหม่จะ deploy ไปเจอ schema เก่าแล้วพัง
#
# วิธีทำงาน: จำชื่อไฟล์ที่รันแล้วในตาราง schema_migrations รันเฉพาะไฟล์ที่ยังไม่มี เรียงตามชื่อ
# หยุดทันทีที่ไฟล์ใดล้ม (ON_ERROR_STOP) จะไม่รันไฟล์ถัดไปต่อ
#
# ครั้งแรกที่รันบน DB ที่มีอยู่แล้ว (ตารางจดบันทึกยังว่าง) สคริปต์จะ "ตรวจจริง" ว่าไฟล์ไหนถูกใช้ไปแล้ว
# (ดู applied_already ด้านล่าง) แล้วจดไว้เฉย ๆ ไม่รันซ้ำ — migration ไม่ได้เขียนให้รันซ้ำได้
set -eu

DIR="${1:-$(dirname "$0")/migrations}"
CONTAINER="${PG_CONTAINER:-petpaws-postgres}"
: "${POSTGRES_USER:?ต้องตั้ง POSTGRES_USER}"
: "${POSTGRES_DB:?ต้องตั้ง POSTGRES_DB}"

psql_q() { docker exec -i "$CONTAINER" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -qtA "$@"; }

psql_q -c "CREATE TABLE IF NOT EXISTS schema_migrations (
  filename   text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
)" >/dev/null

# ใช้เฉพาะรอบ bootstrap: ไฟล์นี้ถูกใช้กับ DB ก้อนนี้ไปแล้วหรือยัง (ดูจากผลลัพธ์ของมันเอง)
# 001–013 = DB ถูกสร้างแล้ว (มีตาราง users) ส่วน 014 ขึ้นไปตรวจจากสิ่งที่ไฟล์นั้นสร้าง
# เพิ่มบรรทัดที่นี่ไม่ต้อง — migration ใหม่กว่านี้จะถูกบันทึกอัตโนมัติหลัง bootstrap แล้ว
applied_already() {
  case "$1" in
    014_*) q="SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='messages' AND column_name='media_type')" ;;
    015_*) q="SELECT to_regclass('public.conversation_hides') IS NOT NULL" ;;
    016_*) q="SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='pets' AND column_name='species_other')" ;;
    *)     q="SELECT to_regclass('public.users') IS NOT NULL" ;;
  esac
  [ "$(psql_q -c "$q")" = "t" ]
}

bootstrap=false
if [ "$(psql_q -c "SELECT count(*) FROM schema_migrations")" = "0" ]; then
  bootstrap=true
fi

for file in "$DIR"/*.sql; do
  name="$(basename "$file")"
  if [ "$(psql_q -c "SELECT count(*) FROM schema_migrations WHERE filename = '$name'")" != "0" ]; then
    continue
  fi
  if [ "$bootstrap" = true ] && applied_already "$name"; then
    echo "บันทึกว่ารันแล้ว (มีอยู่ใน DB เดิม): $name"
  else
    echo "รัน migration: $name"
    psql_q < "$file" >/dev/null
  fi
  psql_q -c "INSERT INTO schema_migrations (filename) VALUES ('$name')" >/dev/null
done

echo "migration เรียบร้อย"
