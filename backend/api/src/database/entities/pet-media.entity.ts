import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';
import { PET_MEDIA_TYPE } from './enums.js';

@Entity({ name: 'pet_media' })
export class PetMedia {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'pet_id', type: 'uuid' })
  petId!: string;

  @Column({ name: 'media_type', type: 'enum', enum: PET_MEDIA_TYPE, enumName: 'pet_media_type' })
  mediaType!: 'photo' | 'video';

  @Column({ name: 'storage_key', type: 'varchar' })
  storageKey!: string;

  @Column({ name: 'url', type: 'text' })
  url!: string;

  @Column({ name: 'thumb_url', type: 'text', nullable: true })
  thumbUrl!: string | null;

  @Column({ name: 'width', type: 'integer', nullable: true })
  width!: number | null;

  @Column({ name: 'height', type: 'integer', nullable: true })
  height!: number | null;

  @Column({ name: 'bytes', type: 'bigint', nullable: true })
  bytes!: string | null;

  @Column({ name: 'duration_seconds', type: 'numeric', nullable: true })
  durationSeconds!: string | null;

  @Column({ name: 'sort_order', type: 'smallint' })
  sortOrder!: number;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;
}
