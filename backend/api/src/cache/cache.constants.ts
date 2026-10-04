export const CACHE_REDIS = Symbol('CACHE_REDIS');

/**
 * กลุ่มของ cache แต่ละชนิด — ใช้เป็นส่วนหนึ่งของ key และแยกนับ hit/miss ตามกลุ่ม
 * TTL ตั้งตามความถี่ที่ข้อมูลเปลี่ยน ทุกกลุ่มที่มีทางแก้ผ่าน API จะถูกลบ (DEL) ทันทีหลัง
 * เขียน DB สำเร็จอยู่แล้ว TTL จึงเป็นแค่ตาข่ายรองรับกรณีที่ลบพลาด/ข้อมูลเปลี่ยนจากที่อื่น
 */
export const CACHE_NAMESPACES = {
  // แก้ได้ทาง migration เท่านั้น ไม่มี API เขียน
  traits: { ttlSeconds: 3600 },
  // ล้างตอนแก้/ลบประกาศ, กดถูกใจ (like_count) และเจ้าของเปลี่ยนชื่อ/รูป
  pet: { ttlSeconds: 300 },
  // ล้างตอนเพิ่ม/แก้/ลบประกาศ — like_count ในรายการนี้ช้าได้ไม่เกิน TTL (หน้า /pets/mine ไม่ cache)
  petsByOwner: { ttlSeconds: 300 },
  userPublic: { ttlSeconds: 300 },
  // รายงานใหม่จากผู้ใช้/การแบนหมดอายุไม่ได้ล้าง cache จึงตั้ง TTL สั้น ส่วนการตัดสินของแอดมินล้างทันที
  adminSummary: { ttlSeconds: 30 },
} as const;

export type CacheNamespace = keyof typeof CACHE_NAMESPACES;

/** เปลี่ยนเลขเวอร์ชันเมื่อรูปทรง JSON ที่ cache ไว้เปลี่ยน — key เก่าจะถูกเมินแล้วหมดอายุไปเอง */
export const CACHE_KEY_PREFIX = 'petpaws:cache:v1';
export const CACHE_STATS_KEY = 'petpaws:cache-stats';
