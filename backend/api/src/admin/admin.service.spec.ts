import { describe, expect, it, vi } from 'vitest';
import type { DataSource } from 'typeorm';
import { AdminService } from './admin.service.js';
import { resolvePaging } from './dto/pagination.dto.js';
import { CacheService } from '../cache/cache.service.js';

// ไม่ต่อ Redis = อ่าน DB ตรงทุกครั้ง (พฤติกรรม cache ทดสอบแยกใน cache.service.spec.ts)
const noCache = new CacheService(null);

// DataSource ปลอมที่คืน rows ตามลำดับคำสั่ง query ที่ถูกเรียก (ไม่ต่อ DB จริง)
// ตัว SQL ของรายงานทดสอบกับ DB จริงใน test/modules-db.e2e-spec.ts
function poolWith(...results: { rows: unknown[] }[]) {
  const query = vi.fn();
  for (const r of results) query.mockResolvedValueOnce(r.rows);
  return { pool: { query } as unknown as DataSource, query };
}

const paging = (page: number, pageSize: number) => resolvePaging({ page, pageSize });

describe('resolvePaging', () => {
  it('ไม่ส่งอะไรมา = หน้า 1 ขนาด 20', () => {
    expect(resolvePaging({})).toEqual({ page: 1, pageSize: 20, offset: 0 });
  });

  it('offset คำนวณจาก (page-1)*pageSize', () => {
    expect(resolvePaging({ page: 3, pageSize: 10 })).toEqual({ page: 3, pageSize: 10, offset: 20 });
  });
});

describe('AdminService.reportedUsers', () => {
  const row = (id: string, n: string, total: string) => ({
    id,
    username: `u_${id}`,
    email: `${id}@x.dev`,
    display_name: `ผู้ใช้ ${id}`,
    avatar_url: null,
    is_suspended: false,
    suspended_until: null,
    report_count: n,
    last_reported_at: new Date('2026-10-01T00:00:00Z'),
    total_count: total,
  });

  it('แปลงแถวเป็นผู้ใช้ และ total มาจากจำนวนก่อนแบ่งหน้า (ไม่ใช่ขนาดหน้านี้)', async () => {
    const { pool, query } = poolWith({ rows: [row('a', '7', '45'), row('b', '4', '45')] });

    const res = await new AdminService(pool, noCache).reportedUsers(3, paging(2, 2));

    expect(res.total).toBe(45);
    expect(res.page).toBe(2);
    expect(res.pageSize).toBe(2);
    expect(res.items).toHaveLength(2);
    expect(res.items[0]).toMatchObject({ id: 'a', email: 'a@x.dev', reportCount: 7, avatarUrl: '' });
    // ส่ง minReports, limit, offset เข้า SQL ตามลำดับ
    expect(query.mock.calls[0][1]).toEqual([3, 2, 2]);
  });

  it('ไม่มีใครถึงเกณฑ์ ได้รายการว่างและ total = 0', async () => {
    const { pool } = poolWith({ rows: [] });
    const res = await new AdminService(pool, noCache).reportedUsers(10, paging(1, 20));
    expect(res).toEqual({ items: [], total: 0, page: 1, pageSize: 20 });
  });
});

describe('AdminService.userReports', () => {
  const base = {
    reason: 'scam',
    detail: null,
    created_at: new Date('2026-10-01T00:00:00Z'),
    reporter_id: 'r1',
    reporter_username: 'rep',
    reporter_name: 'ผู้รายงาน',
    reported_user_id: null,
    reported_pet_id: null,
    pet_name: null,
    pet_species: null,
    pet_status: null,
    pet_deleted: null,
    pet_description: null,
    pet_photos: null,
    reported_message_id: null,
    message_body: null,
    message_created_at: null,
    total_count: '3',
  };

  it('รายงานประกาศ: ส่งชื่อ รูปทุกใบ และสถานะลบ/รับเลี้ยง ให้แอดมินตรวจ', async () => {
    const photos = [
      { url: 'http://x/1.jpg', thumbUrl: null },
      { url: 'http://x/2.jpg', thumbUrl: 'http://x/2t.jpg' },
    ];
    const { pool } = poolWith({
      rows: [
        {
          ...base,
          id: 'p1',
          reported_pet_id: 'pet1',
          pet_name: 'มะม่วง',
          pet_species: 'dog',
          pet_status: 'available',
          pet_deleted: true,
          pet_description: 'น่ารัก',
          pet_photos: photos,
        },
      ],
    });

    const res = await new AdminService(pool, noCache).userReports('u1', paging(1, 20));
    const r = res.items[0];

    expect(r.targetType).toBe('pet');
    expect(r.petName).toBe('มะม่วง');
    expect(r.pet).toMatchObject({ id: 'pet1', deleted: true, description: 'น่ารัก', photos });
    expect(r.messageBody).toBeNull();
  });

  it('รายงานข้อความ: ส่งเฉพาะข้อความที่ถูกรายงานกับเวลาที่ส่ง ไม่มีข้อมูลแชทส่วนอื่น', async () => {
    const sentAt = new Date('2026-09-30T10:00:00Z');
    const { pool } = poolWith({
      rows: [{ ...base, id: 'm1', reported_message_id: 'msg1', message_body: 'โอนเงินมาก่อนนะ', message_created_at: sentAt }],
    });

    const res = await new AdminService(pool, noCache).userReports('u1', paging(1, 20));
    const r = res.items[0];

    expect(r.targetType).toBe('message');
    expect(r.messageBody).toBe('โอนเงินมาก่อนนะ');
    expect(r.messageCreatedAt).toBe(sentAt);
    expect(r.pet).toBeNull();
    // response ต้องไม่มีฟิลด์บทสนทนา/อีกฝั่งของแชทหลุดออกไป
    expect(Object.keys(r)).not.toContain('conversation');
  });

  it('รายงานตัวผู้ใช้ตรง ๆ และ detail ว่างเป็นสตริงว่าง ไม่ใช่ null', async () => {
    const { pool } = poolWith({ rows: [{ ...base, id: 'u1', reported_user_id: 'x' }] });
    const res = await new AdminService(pool, noCache).userReports('x', paging(1, 20));
    expect(res.items[0].targetType).toBe('user');
    expect(res.items[0].detail).toBe('');
    expect(res.total).toBe(3);
  });
});

describe('AdminService.bannedUsers', () => {
  it('แบนไม่มีวันหมดอายุ = permanent', async () => {
    const { pool, query } = poolWith({
      rows: [
        { id: 'a', username: 'a', email: 'a@x', display_name: 'A', avatar_url: null, suspended_until: null, total_count: '2' },
        { id: 'b', username: 'b', email: 'b@x', display_name: 'B', avatar_url: null, suspended_until: new Date('2026-12-01'), total_count: '2' },
      ],
    });

    const res = await new AdminService(pool, noCache).bannedUsers(paging(1, 20));

    expect(res.total).toBe(2);
    expect(res.items.map((u) => u.permanent)).toEqual([true, false]);
    expect(query.mock.calls[0][1]).toEqual([20, 0]);
  });
});

describe('AdminService.userProfile', () => {
  const userRow = {
    id: 'u1',
    username: 'somchai',
    email: 's@x.dev',
    display_name: 'สมชาย',
    avatar_url: null,
    bio: null,
    location: 'เชียงใหม่',
    home_type: 'house',
    is_admin: false,
    is_suspended: false,
    suspended_until: null,
    created_at: new Date('2026-01-01'),
    last_login_at: null,
  };

  it('ไม่พบผู้ใช้ → 404', async () => {
    const { pool } = poolWith({ rows: [] });
    await expect(new AdminService(pool, noCache).userProfile('nope')).rejects.toMatchObject({ code: 'NOT_FOUND' });
  });

  it('รวมโปรไฟล์ ประกาศพร้อมรูป (รวมที่ถูกลบ) และจำนวนรายงานค้าง', async () => {
    const { pool } = poolWith(
      { rows: [userRow] },
      {
        rows: [
          { id: 'p1', name: 'มะม่วง', species: 'dog', status: 'available', description: null, location: 'เชียงใหม่', created_at: new Date('2026-02-01'), deleted: false, photos: [{ url: 'http://x/a.jpg', thumbUrl: null }] },
          { id: 'p2', name: 'ถูกลบ', species: 'cat', status: 'available', description: 'x', location: 'เชียงใหม่', created_at: new Date('2026-01-01'), deleted: true, photos: [] },
        ],
      },
      { rows: [{ n: '6' }] },
    );

    const p = await new AdminService(pool, noCache).userProfile('u1');

    expect(p).toMatchObject({ id: 'u1', email: 's@x.dev', province: 'เชียงใหม่', bio: '', avatarUrl: '', pendingReportCount: 6 });
    expect(p.pets).toHaveLength(2);
    expect(p.pets[0].photos).toHaveLength(1);
    expect(p.pets[1].deleted).toBe(true);
    // ไม่ส่งช่องทางติดต่อส่วนตัวให้แอดมิน
    expect(Object.keys(p)).not.toContain('phone');
    expect(Object.keys(p)).not.toContain('lineId');
  });
});

describe('AdminService.summary', () => {
  it('แปลงตัวเลขจาก SQL เป็น number ทั้ง 3 ช่อง', async () => {
    const { pool } = poolWith({ rows: [{ reported: '12', temporary: '3', permanent: '1' }] });
    await expect(new AdminService(pool, noCache).summary()).resolves.toEqual({ reported: 12, temporary: 3, permanent: 1 });
  });
});

describe('AdminService.ban', () => {
  it('แบนตัวเองไม่ได้', async () => {
    const { pool } = poolWith();
    await expect(new AdminService(pool, noCache).ban('me', 'me', {})).rejects.toMatchObject({ code: 'FORBIDDEN' });
  });
});
