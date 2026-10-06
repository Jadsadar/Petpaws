// ค่า enum ของ Postgres (CREATE TYPE ใน backend/db/migrations) — ต้องตรงกับ DB เสมอ
// เพิ่มค่าใหม่ต้องเพิ่มใน migration ก่อน แล้วค่อยเพิ่มที่นี่
export const PET_SPECIES = ['dog', 'cat', 'rabbit', 'bird', 'other', 'fish'] as const;
export const PET_SEX = ['male', 'female', 'unknown'] as const;
export const PET_SIZE = ['small', 'medium', 'large'] as const;
export const PET_STATUS = ['available', 'pending', 'adopted', 'cancelled'] as const;
export const PET_MEDIA_TYPE = ['photo', 'video'] as const;
export const CONVERSATION_STATUS = ['active', 'closed'] as const;
export const CONVERSATION_CLOSED_REASON = ['pet_adopted', 'pet_deleted', 'blocked', 'user_deleted', 'moderation'] as const;
export const DEVICE_PLATFORM = ['ios', 'android', 'web'] as const;
export const MESSAGE_MEDIA_TYPE = ['image', 'video'] as const;
export const REPORT_REASON = ['fake_info', 'spam', 'inappropriate', 'scam', 'animal_abuse', 'other'] as const;
export const REPORT_STATUS = ['pending', 'reviewing', 'actioned', 'dismissed'] as const;
export const HOME_TYPE = ['detached_house', 'townhouse', 'condo', 'apartment'] as const;
export const THAI_REGION = ['central', 'north', 'northeast', 'east', 'west', 'south'] as const;
