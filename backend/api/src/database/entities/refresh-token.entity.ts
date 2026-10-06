import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'refresh_tokens' })
export class RefreshToken {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'token_hash', type: 'character' })
  tokenHash!: string;

  @Column({ name: 'family_id', type: 'uuid' })
  familyId!: string;

  @Column({ name: 'replaced_by_id', type: 'uuid', nullable: true })
  replacedById!: string | null;

  @Column({ name: 'expires_at', type: 'timestamptz' })
  expiresAt!: Date;

  @Column({ name: 'used_at', type: 'timestamptz', nullable: true })
  usedAt!: Date | null;

  @Column({ name: 'revoked_at', type: 'timestamptz', nullable: true })
  revokedAt!: Date | null;

  @Column({ name: 'revoked_reason', type: 'varchar', nullable: true })
  revokedReason!: string | null;

  @Column({ name: 'user_agent', type: 'varchar', nullable: true })
  userAgent!: string | null;

  @Column({ name: 'ip_address', type: 'inet', nullable: true })
  ipAddress!: string | null;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;
}
