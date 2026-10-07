import { Entity, PrimaryColumn } from 'typeorm';

@Entity({ name: 'user_traits' })
export class UserTrait {
  @PrimaryColumn({ name: 'user_id', type: 'uuid' })
  userId!: string;

  @PrimaryColumn({ name: 'trait_id', type: 'uuid' })
  traitId!: string;
}
