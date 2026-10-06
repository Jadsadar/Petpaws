#!/usr/bin/env python3
"""รายงานประจำวันของ Petpaws ส่งเข้า Discord — รันด้วย cron บน EC2 ทุกเช้า 08:00 เวลาไทย (01:00 UTC)

    sudo python3 /opt/petpaws/scripts/daily_report.py

ต้องมีไฟล์ /opt/petpaws/.discord-webhook (สิทธิ์ 0600 เฉพาะ root) ที่ข้างในเป็น Webhook URL ของ Discord บรรทัดเดียว
URL นี้เป็นความลับ ห้ามใส่ใน git (ansible ไม่ได้สร้างไฟล์นี้ให้ — สร้างมือครั้งเดียวบนเครื่อง)
ไม่มีไฟล์ = สคริปต์แค่แจ้งเตือนใน log แล้วจบ ไม่ทำให้อะไรพัง

ตัวแปรปรับได้: DEPLOY_DIR (/opt/petpaws), HEALTH_URL (http://127.0.0.1/health), DRY_RUN=1 (พิมพ์ข้อความ ไม่ส่งจริง)
"""
import datetime
import json
import os
import shutil
import subprocess
import sys
import urllib.request

DEPLOY_DIR = os.environ.get('DEPLOY_DIR', '/opt/petpaws')
HOOK_FILE = os.path.join(DEPLOY_DIR, '.discord-webhook')
BACKUP_DIR = os.path.join(DEPLOY_DIR, 'backups')
HEALTH_URL = os.environ.get('HEALTH_URL', 'http://127.0.0.1/health')
PG_CONTAINER = os.environ.get('PG_CONTAINER', 'petpaws-postgres')
EXPECTED_CONTAINERS = 8  # postgres, redis, redis-cache, minio, api, worker, caddy, uptime-kuma
DISK_WARN_PCT = 80
BACKUP_MAX_AGE_H = 26
TH = datetime.timezone(datetime.timedelta(hours=7))


def run(cmd, stdin=None):
    r = subprocess.run(cmd, shell=True, input=stdin, capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout.strip()


def psql(sql):
    code, out = run(
        f"docker exec -i {PG_CONTAINER} sh -c 'psql -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" -tA -F\"|\"'", stdin=sql)
    return out if code == 0 else None


def human(n):
    for unit in ('B', 'KB', 'MB', 'GB'):
        if n < 1024 or unit == 'GB':
            return f'{n:.0f} {unit}' if unit == 'B' else f'{n:.1f} {unit}'
        n /= 1024


def check_health():
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=10) as r:
            body = r.read().decode('utf-8', 'replace')
        return '"db":"connected"' in body.replace(' ', ''), body[:80]
    except Exception as e:  # noqa: BLE001
        return False, str(e)[:80]


def containers():
    code, out = run("docker ps -a --format '{{.Names}}|{{.Status}}'")
    bad, up = [], 0
    for line in out.splitlines():
        name, _, status = line.partition('|')
        if not name.startswith('petpaws-'):
            continue
        if status.startswith('Up') and 'unhealthy' not in status and 'starting' not in status:
            up += 1
        else:
            bad.append(f'{name} ({status})')
    return up, bad


def memory():
    info = {}
    with open('/proc/meminfo') as f:
        for line in f:
            k, v = line.split(':')
            info[k] = int(v.split()[0]) * 1024
    swap_used = info.get('SwapTotal', 0) - info.get('SwapFree', 0)
    return info['MemTotal'], info['MemAvailable'], swap_used, info.get('SwapTotal', 0)


def last_backup():
    out = {}
    for prefix, label in (('db-', 'ฐานข้อมูล'), ('media-', 'รูป')):
        files = []
        if os.path.isdir(BACKUP_DIR):
            files = [os.path.join(BACKUP_DIR, f) for f in os.listdir(BACKUP_DIR) if f.startswith(prefix)]
        if files:
            newest = max(files, key=os.path.getmtime)
            age_h = (datetime.datetime.now().timestamp() - os.path.getmtime(newest)) / 3600
            out[label] = (age_h, os.path.getsize(newest))
        else:
            out[label] = None
    return out


def main():
    now = datetime.datetime.now(TH)
    problems = []

    ok, health_msg = check_health()
    if not ok:
        problems.append(f'เว็บ/ฐานข้อมูลไม่ปกติ: {health_msg}')

    up, bad = containers()
    if bad or up < EXPECTED_CONTAINERS:
        problems.append(f'container ไม่ครบ ({up}/{EXPECTED_CONTAINERS}): ' + ', '.join(bad) if bad
                        else f'container รันอยู่ {up}/{EXPECTED_CONTAINERS}')

    total, free = shutil.disk_usage('/')[0], shutil.disk_usage('/')[2]
    disk_pct = 100 * (total - free) / total
    if disk_pct >= DISK_WARN_PCT:
        problems.append(f'ดิสก์ใช้ไป {disk_pct:.0f}% (เกิน {DISK_WARN_PCT}%)')

    mem_total, mem_avail, swap_used, swap_total = memory()

    stats = psql("""
select 'users|' || count(*) || '|' || count(*) filter (where created_at > now() - interval '24 hours') from users;
select 'pets|' || count(*) filter (where deleted_at is null) || '|' || count(*) filter (where created_at > now() - interval '24 hours' and deleted_at is null) from pets;
select 'messages|' || count(*) filter (where kind = 'user') || '|' || count(*) filter (where kind = 'user' and created_at > now() - interval '24 hours') from messages;
select 'reports|' || count(*) filter (where status = 'pending') || '|' || count(*) filter (where created_at > now() - interval '24 hours') from reports;
select 'banned|' || count(*) from users where is_suspended;
""")
    s = {}
    if stats:
        for line in stats.splitlines():
            parts = line.split('|')
            s[parts[0]] = parts[1:]
    else:
        problems.append('อ่านสถิติจากฐานข้อมูลไม่ได้')

    backups = last_backup()
    backup_lines = []
    for label, info in backups.items():
        if info is None:
            backup_lines.append(f'{label}: ไม่พบไฟล์สำรอง')
            problems.append(f'ไม่พบไฟล์สำรอง{label}')
        else:
            age_h, size = info
            mark = '⚠️ ' if age_h > BACKUP_MAX_AGE_H else ''
            backup_lines.append(f'{mark}{label}: {age_h:.0f} ชม. ที่แล้ว ({human(size)})')
            if age_h > BACKUP_MAX_AGE_H:
                problems.append(f'สำรอง{label}ล่าสุดเมื่อ {age_h:.0f} ชั่วโมงก่อน (เกิน {BACKUP_MAX_AGE_H})')

    def stat(key, idx, default='?'):
        return s.get(key, [default, default])[idx]

    fields = [
        {'name': 'ระบบ', 'inline': True, 'value':
            f"{'✅' if ok else '❌'} เว็บ + ฐานข้อมูล\n{'✅' if up >= EXPECTED_CONTAINERS and not bad else '❌'} container {up}/{EXPECTED_CONTAINERS}"},
        {'name': 'เครื่อง', 'inline': True, 'value':
            f"ดิสก์ {disk_pct:.0f}% ({human(free)} ว่าง)\nRAM ว่าง {human(mem_avail)}/{human(mem_total)}\nswap ใช้ {human(swap_used)}/{human(swap_total)}"},
        {'name': 'ข้อมูล (ใหม่ใน 24 ชม.)', 'inline': False, 'value':
            f"ผู้ใช้ {stat('users', 0)} (+{stat('users', 1)})  ·  ประกาศที่เปิดอยู่ {stat('pets', 0)} (+{stat('pets', 1)})\n"
            f"ข้อความ {stat('messages', 0)} (+{stat('messages', 1)})"},
        {'name': 'การดูแล', 'inline': False, 'value':
            f"รายงานรอตรวจ {stat('reports', 0)} (ใหม่ +{stat('reports', 1)})  ·  ถูกแบน {s.get('banned', ['?'])[0]}"},
        {'name': 'สำรองข้อมูลล่าสุด', 'inline': False, 'value': '\n'.join(backup_lines)},
    ]
    if problems:
        fields.insert(0, {'name': '⚠️ ต้องดู', 'inline': False, 'value': '\n'.join(f'• {p}' for p in problems)})

    payload = {
        'username': 'Petpaws Daily',
        'embeds': [{
            'title': f"{'☀️' if not problems else '⚠️'} รายงานเช้า Petpaws — {now:%d/%m/%Y}",
            'color': 0x2ECC71 if not problems else 0xE67E22,
            'fields': fields,
            'footer': {'text': f'สร้างเมื่อ {now:%H:%M} น. (เวลาไทย)'},
        }],
    }

    if os.environ.get('DRY_RUN') == '1':
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0
    if not os.path.isfile(HOOK_FILE):
        print(f'ไม่พบ {HOOK_FILE} — ยังไม่ได้ตั้ง Webhook ของ Discord จึงไม่ส่งรายงาน', file=sys.stderr)
        return 0
    with open(HOOK_FILE) as f:
        url = f.read().strip()
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode('utf-8'), method='POST',
        headers={'Content-Type': 'application/json', 'User-Agent': 'PetpawsDailyReport/1.0'})
    with urllib.request.urlopen(req, timeout=20) as r:
        print('ส่งรายงานแล้ว HTTP', r.status)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print('รายงานล้มเหลว:', type(e).__name__, e, file=sys.stderr)
        sys.exit(1)
