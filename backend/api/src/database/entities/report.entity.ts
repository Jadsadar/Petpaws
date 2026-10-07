import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';
import { REPORT_REASON, REPORT_STATUS } from './enums.js';

@Entity({ name: 'reports' })
export class Report {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'reporter_id', type: 'uuid' })
  reporterId!: string;

  @Column({ name: 'reported_pet_id', type: 'uuid', nullable: true })
  reportedPetId!: string | null;

  @Column({ name: 'reported_user_id', type: 'uuid', nullable: true })
  reportedUserId!: string | null;

  @Column({ name: 'reported_message_id', type: 'uuid', nullable: true })
  reportedMessageId!: string | null;

  @Column({ name: 'reason', type: 'enum', enum: REPORT_REASON, enumName: 'report_reason' })
  reason!: 'fake_info' | 'spam' | 'inappropriate' | 'scam' | 'animal_abuse' | 'other';

  @Column({ name: 'detail', type: 'varchar', nullable: true })
  detail!: string | null;

  @Column({ name: 'status', type: 'enum', enum: REPORT_STATUS, enumName: 'report_status' })
  status!: 'pending' | 'reviewing' | 'actioned' | 'dismissed';

  @Column({ name: 'reviewed_by', type: 'uuid', nullable: true })
  reviewedBy!: string | null;

  @Column({ name: 'reviewed_at', type: 'timestamptz', nullable: true })
  reviewedAt!: Date | null;

  @Column({ name: 'review_note', type: 'varchar', nullable: true })
  reviewNote!: string | null;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;
}
