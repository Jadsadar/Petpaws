import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';
import { MESSAGE_MEDIA_TYPE } from './enums.js';

@Entity({ name: 'messages' })
export class Message {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'conversation_id', type: 'uuid' })
  conversationId!: string;

  @Column({ name: 'sender_id', type: 'uuid' })
  senderId!: string;

  @Column({ name: 'body', type: 'text' })
  body!: string;

  @Column({ name: 'read_at', type: 'timestamptz', nullable: true })
  readAt!: Date | null;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;

  @Column({ name: 'deleted_at', type: 'timestamptz', nullable: true })
  deletedAt!: Date | null;

  @Column({ name: 'media_type', type: 'enum', enum: MESSAGE_MEDIA_TYPE, enumName: 'message_media_type', nullable: true })
  mediaType!: 'image' | 'video' | null;

  @Column({ name: 'media_url', type: 'text', nullable: true })
  mediaUrl!: string | null;

  @Column({ name: 'thumbnail_url', type: 'text', nullable: true })
  thumbnailUrl!: string | null;

  @Column({ name: 'media_width', type: 'integer', nullable: true })
  mediaWidth!: number | null;

  @Column({ name: 'media_height', type: 'integer', nullable: true })
  mediaHeight!: number | null;

  @Column({ name: 'media_duration_ms', type: 'integer', nullable: true })
  mediaDurationMs!: number | null;

  @Column({ name: 'kind', type: 'text', insert: false, update: false })
  kind!: string;

  @Column({ name: 'client_id', type: 'uuid', nullable: true })
  clientId!: string | null;
}
