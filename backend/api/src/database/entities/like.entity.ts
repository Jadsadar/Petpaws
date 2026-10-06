import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';

@Entity({ name: 'likes' })
export class Like {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @Column({ name: 'pet_id', type: 'uuid' })
  petId!: string;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;
}
