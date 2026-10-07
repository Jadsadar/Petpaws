import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'media_uploads' })
export class MediaUpload {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'storage_key', type: 'varchar' })
  storageKey!: string;

  @Column({ name: 'content_type', type: 'varchar' })
  contentType!: string;

  @Column({ name: 'bytes', type: 'bigint', nullable: true })
  bytes!: string | null;

  @Column({ name: 'expires_at', type: 'timestamptz' })
  expiresAt!: Date;

  @Column({ name: 'claimed_at', type: 'timestamptz', nullable: true })
  claimedAt!: Date | null;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;
}
