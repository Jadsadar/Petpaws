<#
.SYNOPSIS
  เตรียมฐานข้อมูล dev + mock data ในคำสั่งเดียว (แทนหลายขั้นใน readme-mockdata.md)

.DESCRIPTION
  1. เปิด container (postgres, redis, minio) แล้วรอจน postgres พร้อมจริง
  2. รัน migration ที่ DB นี้ยังไม่เคยรัน (initdb รันให้แค่ตอน volume ว่าง)
  3. ใส่ mock data — รันซ้ำได้ ข้อมูลสาธิตกลับเป็นสภาพเริ่มต้นทุกครั้ง

  ประวัติ migration ที่รันแล้วเก็บใน dev_tools.applied_migrations (แยก schema จาก
  ตารางของแอปใน public) — ครั้งแรกที่ยังไม่มีตารางนี้ จะลองรันทุกไฟล์: ทุกไฟล์ครอบด้วย
  BEGIN/COMMIT ถ้าไฟล์ไหนรันไปแล้วจะชน "already exists" แล้วถูกย้อนกลับทั้งไฟล์ จึงปลอดภัย

.EXAMPLE
  .\backend\seed.cmd           # ใช้ข้อมูลเดิม เติม migration ที่ขาด แล้วรีเซ็ตบัญชีสาธิต
  .\backend\seed.cmd -Reset    # ล้าง DB ทั้งหมด (docker compose down -v) แล้วสร้างใหม่
  .\backend\seed.cmd -All      # ใส่ seed ทุกไฟล์ (001, 002, 003) ไม่ใช่แค่ 003
#>
param(
  [switch]$Reset,
  [switch]$All
)

$ErrorActionPreference = 'Stop'
$backend = $PSScriptRoot
$compose = Join-Path $backend 'docker-compose.yml'
$container = 'petpaws-postgres'
$seedDir = '/tmp/petpaws-seeds'
$trackTable = 'dev_tools.applied_migrations'

# ข้อความไทยจาก psql ต้องอ่านเป็น UTF-8 ไม่งั้นเพี้ยนบน Windows PowerShell 5.1
$prevEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Fail([string]$msg, [string]$detail = '') {
  Write-Host "`n[x] $msg" -ForegroundColor Red
  if ($detail) { Write-Host $detail -ForegroundColor DarkGray }
  [Console]::OutputEncoding = $prevEncoding
  exit 1
}

# รันโปรแกรมภายนอก คืน @{ Code; Output } — กลืน stderr มาเป็นข้อความ
# (PowerShell 5.1 ห่อ stderr ของ native เป็น error record ทำให้สคริปต์หยุดเองถ้าไม่จัดการ)
function Invoke-Native([string]$exe, [string[]]$arguments) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & $exe @arguments 2>&1 | ForEach-Object { "$_" }
  } finally {
    $ErrorActionPreference = $old
  }
  return @{ Code = $LASTEXITCODE; Output = ($out -join "`n") }
}

# psql ในคอนเทนเนอร์ — ส่ง argument ตรง ๆ ไม่ผ่าน sh -c เพราะ PowerShell 5.1
# ส่ง argument ที่มี " ข้างในให้โปรแกรมภายนอกผิด
function Invoke-Psql([string[]]$psqlArgs) {
  Invoke-Native 'docker' (@('exec', $container, 'psql', '-U', $script:dbUser, '-d', $script:dbName,
      '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose') + $psqlArgs)
}

function Invoke-Sql([string]$sql) {
  $r = Invoke-Psql @('-tA', '-c', $sql)
  if ($r.Code -ne 0) { Fail 'คำสั่ง SQL ล้มเหลว' $r.Output }
  return $r.Output.Trim()
}

# -----------------------------------------------------------------------------
Step 'ตรวจ Docker'
if ((Invoke-Native 'docker' @('info', '--format', '{{.ServerVersion}}')).Code -ne 0) {
  Fail 'ติดต่อ Docker ไม่ได้ — เปิด Docker Desktop ก่อนแล้วรันใหม่'
}

if ($Reset) {
  Step 'ล้างฐานข้อมูลทั้งหมด (docker compose down -v)'
  $r = Invoke-Native 'docker' @('compose', '-f', $compose, 'down', '-v')
  if ($r.Code -ne 0) { Fail 'docker compose down ไม่สำเร็จ' $r.Output }
}

Step 'เปิด container (postgres, redis, minio)'
$r = Invoke-Native 'docker' @('compose', '-f', $compose, 'up', '-d')
if ($r.Code -ne 0) { Fail 'docker compose up ไม่สำเร็จ' $r.Output }

# เช็คผ่าน TCP เท่านั้น: ตอน initdb รัน migration ครั้งแรก postgres เปิดแบบ socket อย่างเดียว
# ถ้าเช็คผ่าน socket จะนึกว่าพร้อมแล้วไปรันชนกับ initdb ที่ยังทำงานไม่เสร็จ
Write-Host '    รอ postgres พร้อม' -NoNewline
$deadline = (Get-Date).AddSeconds(120)
while ((Invoke-Native 'docker' @('exec', $container, 'pg_isready', '-h', '127.0.0.1', '-q')).Code -ne 0) {
  if ((Get-Date) -gt $deadline) {
    Fail 'postgres ไม่พร้อมภายใน 2 นาที' (Invoke-Native 'docker' @('logs', '--tail', '30', $container)).Output
  }
  Write-Host '.' -NoNewline
  Start-Sleep -Seconds 2
}
Write-Host ' พร้อม' -ForegroundColor Green

# user/db จริงจาก env ของคอนเทนเนอร์ (ตรงกับ .env เสมอ ไม่ต้องเดา)
$dbUser = (Invoke-Native 'docker' @('exec', $container, 'printenv', 'POSTGRES_USER')).Output.Trim()
$dbName = (Invoke-Native 'docker' @('exec', $container, 'printenv', 'POSTGRES_DB')).Output.Trim()

# -----------------------------------------------------------------------------
Step 'migration'
$tracked = (Invoke-Sql "SELECT to_regclass('$trackTable') IS NOT NULL") -eq 't'
Invoke-Sql "CREATE SCHEMA IF NOT EXISTS dev_tools; CREATE TABLE IF NOT EXISTS $trackTable (filename text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())" | Out-Null
$applied = @((Invoke-Sql "SELECT filename FROM $trackTable") -split "`n" | Where-Object { $_ })

# SQLSTATE กลุ่ม "มีอยู่แล้ว" = migration ไฟล์นั้นเคยรันแล้ว (ไฟล์ถูกย้อนกลับทั้งก้อน ไม่มีอะไรเปลี่ยน)
$alreadyExists = 'ERROR:\s+(42P07|42710|42701|42P06|42723):'
$migrations = Get-ChildItem (Join-Path $backend 'db\migrations') -Filter '*.sql' | Sort-Object Name
$ran = 0
foreach ($m in $migrations) {
  if ($applied -contains $m.Name) { continue }

  # โฟลเดอร์ migrations ถูก mount เข้าคอนเทนเนอร์อยู่แล้ว (ดู docker-compose.yml)
  $r = Invoke-Psql @('-f', "/docker-entrypoint-initdb.d/$($m.Name)")
  if ($r.Code -eq 0) {
    if ($tracked) {
      Write-Host "    + $($m.Name)" -ForegroundColor Green
      $ran++
    }
  } elseif (-not $tracked -and $r.Output -match $alreadyExists) {
    # ครั้งแรกที่เริ่มจดประวัติ: ไฟล์นี้อยู่ใน DB อยู่แล้ว แค่บันทึกไว้
  } else {
    Fail "migration $($m.Name) ล้มเหลว" $r.Output
  }
  Invoke-Sql "INSERT INTO $trackTable (filename) VALUES ('$($m.Name)')" | Out-Null
}
if ($ran -eq 0) { Write-Host '    ครบแล้ว ไม่มีไฟล์ใหม่' -ForegroundColor Green }

# -----------------------------------------------------------------------------
Step 'ใส่ mock data'
$seeds = Get-ChildItem (Join-Path $backend 'db\seeds') -Filter '*.sql' | Sort-Object Name
if (-not $All) { $seeds = $seeds | Where-Object { $_.Name -eq '003_demo_accounts.sql' } }

# คัดลอกไฟล์เข้าคอนเทนเนอร์แทนการ pipe ผ่าน PowerShell ซึ่งอาจทำภาษาไทยเพี้ยน
Invoke-Native 'docker' @('exec', $container, 'rm', '-rf', $seedDir) | Out-Null
$r = Invoke-Native 'docker' @('cp', (Join-Path $backend 'db\seeds'), "${container}:$seedDir")
if ($r.Code -ne 0) { Fail 'คัดลอกไฟล์ seed เข้าคอนเทนเนอร์ไม่สำเร็จ' $r.Output }

foreach ($s in $seeds) {
  $r = Invoke-Psql @('-f', "$seedDir/$($s.Name)")
  if ($r.Code -ne 0) { Fail "seed $($s.Name) ล้มเหลว" $r.Output }
  Write-Host "    + $($s.Name)" -ForegroundColor Green
}
Invoke-Native 'docker' @('exec', $container, 'rm', '-rf', $seedDir) | Out-Null

$counts = Invoke-Sql "SELECT (SELECT count(*) FROM users) || ' บัญชี, ' || (SELECT count(*) FROM pets) || ' ประกาศ, ' || (SELECT count(*) FROM conversations) || ' ห้องแชท'"

# -----------------------------------------------------------------------------
Write-Host "`nเสร็จแล้ว — ในฐานข้อมูลมี $counts" -ForegroundColor Green
Write-Host @'

  ล็อกอิน:  demo01 ... demo10  หรือ  admin  (แอดมิน)
  รหัสผ่าน: Petpaws1!

  เปิด backend:  cd backend\api ; npm run start:dev
  เปิด worker:   cd backend\api ; npm run start:worker:dev   (อีกหน้าต่าง)
'@

[Console]::OutputEncoding = $prevEncoding
