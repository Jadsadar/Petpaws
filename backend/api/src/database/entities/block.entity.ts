import { Column, Entity, PrimaryColumn } from 'typeorm';

@Entity({ name: 'blocks' })
export class Block {
  @PrimaryColumn({ name: 'blocker_id', type: 'uuid' })
  blockerId!: string;

  @PrimaryColumn({ name: 'blocked_id', type: 'uuid' })
  blockedId!: string;

  @Column({ name: 'reason', type: 'varchar', nullable: true })
  reason!: string | null;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;
}
