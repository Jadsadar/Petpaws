import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';
import { DEVICE_PLATFORM } from './enums.js';

@Entity({ name: 'device_tokens' })
export class DeviceToken {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'token', type: 'varchar' })
  token!: string;

  @Column({ name: 'platform', type: 'enum', enum: DEVICE_PLATFORM, enumName: 'device_platform' })
  platform!: 'ios' | 'android' | 'web';

  @Column({ name: 'last_seen_at', type: 'timestamptz' })
  lastSeenAt!: Date;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;
}
