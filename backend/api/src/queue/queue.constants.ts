export const PUSH_QUEUE = 'push';
export const MEDIA_CLEANUP_QUEUE = 'media-cleanup';

export const SEND_MESSAGE_PUSH_JOB = 'send-message-push';
export const CLEANUP_ORPHAN_MEDIA_JOB = 'cleanup-orphan-media';

/**
 * หน่วง push ข้อความแชทไว้เท่านี้ก่อนส่ง ถ้าผู้ส่งคนเดิมส่งข้อความใหม่ในห้องเดิมตามมาภายในช่วงนี้
 * (เช่น ส่งรูปทีละหลายรูป) จะข้าม push ของข้อความก่อนหน้า เหลือเด้งครั้งเดียวที่ข้อความล่าสุด
 * ใช้ทั้งเป็น delay ตอน enqueue (chat.service) และเป็นช่วงที่ worker ตรวจ (push.processor)
 */
export const PUSH_COALESCE_MS = 3_000;

export interface MessagePushJobData {
  messageId: string;
}
