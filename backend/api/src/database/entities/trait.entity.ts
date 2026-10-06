import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'traits' })
export class Trait {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'slug', type: 'varchar' })
  slug!: string;

  @Column({ name: 'label_th', type: 'varchar' })
  labelTh!: string;

  @Column({ name: 'sort_order', type: 'smallint' })
  sortOrder!: number;

  @Column({ name: 'is_active', type: 'boolean' })
  isActive!: boolean;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;
}
