import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';
import { CONVERSATION_CLOSED_REASON, CONVERSATION_STATUS } from './enums.js';

@Entity({ name: 'conversations' })
export class Conversation {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'pet_id', type: 'uuid' })
  petId!: string;

  @Column({ name: 'initiator_id', type: 'uuid' })
  initiatorId!: string;

  @Column({ name: 'owner_id', type: 'uuid' })
  ownerId!: string;

  @Column({ name: 'status', type: 'enum', enum: CONVERSATION_STATUS, enumName: 'conversation_status' })
  status!: 'active' | 'closed';

  @Column({ name: 'closed_at', type: 'timestamptz', nullable: true })
  closedAt!: Date | null;

  @Column({ name: 'closed_reason', type: 'enum', enum: CONVERSATION_CLOSED_REASON, enumName: 'conversation_closed_reason', nullable: true })
  closedReason!: 'pet_adopted' | 'pet_deleted' | 'blocked' | 'user_deleted' | 'moderation' | null;

  @Column({ name: 'last_message_at', type: 'timestamptz', insert: false, update: false })
  lastMessageAt!: Date;

  @Column({ name: 'last_message_preview', type: 'varchar', nullable: true, insert: false, update: false })
  lastMessagePreview!: string | null;

  @Column({ name: 'last_message_sender_id', type: 'uuid', nullable: true, insert: false, update: false })
  lastMessageSenderId!: string | null;

  @Column({ name: 'initiator_unread_count', type: 'integer', insert: false, update: false })
  initiatorUnreadCount!: number;

  @Column({ name: 'owner_unread_count', type: 'integer', insert: false, update: false })
  ownerUnreadCount!: number;

  @Column({ name: 'initiator_last_read_at', type: 'timestamptz', nullable: true, insert: false, update: false })
  initiatorLastReadAt!: Date | null;

  @Column({ name: 'owner_last_read_at', type: 'timestamptz', nullable: true, insert: false, update: false })
  ownerLastReadAt!: Date | null;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', insert: false, update: false })
  updatedAt!: Date;
}
