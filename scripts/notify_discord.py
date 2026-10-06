#!/usr/bin/env python3
"""ส่งข้อความสถานะ deploy เข้า Discord — ถูกเรียกจาก ansible/deploy.yml (เริ่ม / สำเร็จ / ล้มเหลว)

อ่านค่าจากตัวแปรสภาพแวดล้อม (ไม่รับ argument เพื่อไม่ต้องพะวงเรื่อง quote ข้อความ commit):
  NOTIFY_STATUS  start | ok | fail
  NOTIFY_COMMIT, NOTIFY_MESSAGE, NOTIFY_ACTOR, NOTIFY_URL   ข้อมูลของรอบ deploy
  NOTIFY_START   เวลาเริ่ม (epoch วินาที) ไว้คำนวณว่าใช้กี่นาที
  NOTIFY_FAILED_TASK  ชื่อขั้นที่ล้ม (เฉพาะ fail)
  DEPLOY_DIR     (/opt/petpaws) ที่เก็บไฟล์ .discord-webhook

ไม่มีไฟล์ Webhook หรือส่งไม่สำเร็จ = เงียบๆ จบด้วย exit 0 เสมอ การแจ้งเตือนห้ามทำให้ deploy ล้ม
"""
import json
import os
import sys
import time
import urllib.request

DEPLOY_DIR = os.environ.get('DEPLOY_DIR', '/opt/petpaws')
HOOK_FILE = os.path.join(DEPLOY_DIR, '.discord-webhook')


def env(name, default='-'):
    value = os.environ.get(name, '').strip()
    return value if value else default


def main():
    status = env('NOTIFY_STATUS', 'start')
    if not os.path.isfile(HOOK_FILE):
        print(f'ไม่พบ {HOOK_FILE} ข้ามการแจ้งเตือน', file=sys.stderr)
        return

    titles = {
        'start': ('🚀 เริ่ม deploy Petpaws', 0x3498DB),
        'ok': ('✅ deploy Petpaws สำเร็จ', 0x2ECC71),
        'fail': ('❌ deploy Petpaws ล้มเหลว', 0xE74C3C),
    }
    title, color = titles.get(status, titles['start'])

    fields = [
        {'name': 'commit', 'value': f"`{env('NOTIFY_COMMIT')}` {env('NOTIFY_MESSAGE')}"[:1000], 'inline': False},
        {'name': 'โดย', 'value': env('NOTIFY_ACTOR'), 'inline': True},
    ]
    start = env('NOTIFY_START', '')
    if status != 'start' and start.isdigit():
        minutes = (time.time() - int(start)) / 60
        fields.append({'name': 'ใช้เวลา', 'value': f'{minutes:.1f} นาที', 'inline': True})
    if status == 'start':
        fields.append({'name': 'หมายเหตุ', 'value': 'API/worker จะรีสตาร์ตช่วงสั้นๆ ระหว่างนี้', 'inline': False})
    if status == 'fail':
        fields.append({'name': 'ล้มที่ขั้น', 'value': env('NOTIFY_FAILED_TASK')[:500], 'inline': False})
        fields.append({'name': 'ต้องทำ', 'value': 'ดู log ที่ลิงก์ด้านล่าง ระบบเดิมยังทำงานอยู่ตามเดิมถ้า container ไม่ถูกแตะ', 'inline': False})
    url = env('NOTIFY_URL', '')
    if url.startswith('https://'):
        fields.append({'name': 'รายละเอียด', 'value': url, 'inline': False})

    payload = {'username': 'Petpaws Deploy', 'embeds': [{'title': title, 'color': color, 'fields': fields}]}
    with open(HOOK_FILE) as f:
        hook = f.read().strip()
    req = urllib.request.Request(
        hook, data=json.dumps(payload).encode('utf-8'), method='POST',
        headers={'Content-Type': 'application/json', 'User-Agent': 'PetpawsDeployNotify/1.0'})
    with urllib.request.urlopen(req, timeout=15) as r:
        print('แจ้ง Discord แล้ว HTTP', r.status)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:  # noqa: BLE001
        print('แจ้ง Discord ไม่สำเร็จ (ข้าม):', type(e).__name__, e, file=sys.stderr)
    sys.exit(0)
