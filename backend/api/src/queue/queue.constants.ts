export const PUSH_QUEUE = 'push';
export const MEDIA_CLEANUP_QUEUE = 'media-cleanup';

export const SEND_MESSAGE_PUSH_JOB = 'send-message-push';
export const CLEANUP_ORPHAN_MEDIA_JOB = 'cleanup-orphan-media';

export interface MessagePushJobData {
  messageId: string;
}
