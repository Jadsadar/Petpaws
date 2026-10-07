import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';
import { HOME_TYPE } from './enums.js';

@Entity({ name: 'users' })
export class User {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'email', type: 'citext' })
  email!: string;

  @Column({ name: 'password_hash', type: 'varchar' })
  passwordHash!: string;

  @Column({ name: 'display_name', type: 'varchar' })
  displayName!: string;

  @Column({ name: 'avatar_url', type: 'text', nullable: true })
  avatarUrl!: string | null;

  @Column({ name: 'bio', type: 'varchar', nullable: true })
  bio!: string | null;

  @Column({ name: 'location', type: 'varchar', nullable: true })
  location!: string | null;

  @Column({ name: 'is_suspended', type: 'boolean' })
  isSuspended!: boolean;

  @Column({ name: 'suspended_until', type: 'timestamptz', nullable: true })
  suspendedUntil!: Date | null;

  @Column({ name: 'is_admin', type: 'boolean' })
  isAdmin!: boolean;

  @Column({ name: 'email_verified_at', type: 'timestamptz', nullable: true })
  emailVerifiedAt!: Date | null;

  @Column({ name: 'last_login_at', type: 'timestamptz', nullable: true })
  lastLoginAt!: Date | null;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', insert: false, update: false })
  updatedAt!: Date;

  @Column({ name: 'deleted_at', type: 'timestamptz', nullable: true })
  deletedAt!: Date | null;

  @Column({ name: 'home_type', type: 'enum', enum: HOME_TYPE, enumName: 'home_type', nullable: true })
  homeType!: 'detached_house' | 'townhouse' | 'condo' | 'apartment' | null;

  @Column({ name: 'username', type: 'citext' })
  username!: string;

  @Column({ name: 'profile_completed_at', type: 'timestamptz', nullable: true })
  profileCompletedAt!: Date | null;
}
