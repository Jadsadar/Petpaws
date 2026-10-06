import { Entity, PrimaryColumn } from 'typeorm';

@Entity({ name: 'pet_traits' })
export class PetTrait {
  @PrimaryColumn({ name: 'pet_id', type: 'uuid' })
  petId!: string;

  @PrimaryColumn({ name: 'trait_id', type: 'uuid' })
  traitId!: string;
}
