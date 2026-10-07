import { Column, Entity, PrimaryColumn } from 'typeorm';

@Entity({ name: 'user_contacts' })
export class UserContact {
  @PrimaryColumn({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'phone', type: 'varchar', nullable: true })
  phone!: string | null;

  @Column({ name: 'line_id', type: 'varchar', nullable: true })
  lineId!: string | null;

  @Column({ name: 'fb_name', type: 'varchar', nullable: true })
  fbName!: string | null;

  @Column({ name: 'updated_at', type: 'timestamptz', insert: false, update: false })
  updatedAt!: Date;
}
