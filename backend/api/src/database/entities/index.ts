// entity ทุกตัว — อธิบายตารางที่มีอยู่แล้วใน backend/db/migrations (แหล่งความจริงคือไฟล์ SQL)
// TypeORM ห้ามสร้าง/แก้ตารางเอง (synchronize: false) ดู database.module.ts
import { User } from './user.entity.js';
import { UserContact } from './user-contact.entity.js';
import { UserTrait } from './user-trait.entity.js';
import { RefreshToken } from './refresh-token.entity.js';
import { PasswordResetToken } from './password-reset-token.entity.js';
import { EmailVerificationToken } from './email-verification-token.entity.js';
import { DeviceToken } from './device-token.entity.js';
import { Province } from './province.entity.js';
import { Trait } from './trait.entity.js';
import { Pet } from './pet.entity.js';
import { PetMedia } from './pet-media.entity.js';
import { PetTrait } from './pet-trait.entity.js';
import { MediaUpload } from './media-upload.entity.js';
import { Like } from './like.entity.js';
import { Pass } from './pass.entity.js';
import { Conversation } from './conversation.entity.js';
import { ConversationHide } from './conversation-hide.entity.js';
import { Message } from './message.entity.js';
import { Block } from './block.entity.js';
import { Report } from './report.entity.js';

export { User };
export { UserContact };
export { UserTrait };
export { RefreshToken };
export { PasswordResetToken };
export { EmailVerificationToken };
export { DeviceToken };
export { Province };
export { Trait };
export { Pet };
export { PetMedia };
export { PetTrait };
export { MediaUpload };
export { Like };
export { Pass };
export { Conversation };
export { ConversationHide };
export { Message };
export { Block };
export { Report };

export const ENTITIES = [User, UserContact, UserTrait, RefreshToken, PasswordResetToken, EmailVerificationToken, DeviceToken, Province, Trait, Pet, PetMedia, PetTrait, MediaUpload, Like, Pass, Conversation, ConversationHide, Message, Block, Report];
