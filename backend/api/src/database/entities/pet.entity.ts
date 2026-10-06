import { Column, Entity, PrimaryGeneratedColumn } from 'typeorm';
import { PET_SEX, PET_SIZE, PET_SPECIES, PET_STATUS } from './enums.js';

@Entity({ name: 'pets' })
export class Pet {
  @PrimaryGeneratedColumn('uuid', { name: 'id' })
  id!: string;

  @Column({ name: 'owner_id', type: 'uuid' })
  ownerId!: string;

  @Column({ name: 'name', type: 'varchar' })
  name!: string;

  @Column({ name: 'species', type: 'enum', enum: PET_SPECIES, enumName: 'pet_species' })
  species!: 'dog' | 'cat' | 'rabbit' | 'bird' | 'other' | 'fish';

  @Column({ name: 'breed', type: 'varchar', nullable: true })
  breed!: string | null;

  @Column({ name: 'age_months', type: 'integer', nullable: true })
  ageMonths!: number | null;

  @Column({ name: 'sex', type: 'enum', enum: PET_SEX, enumName: 'pet_sex' })
  sex!: 'male' | 'female' | 'unknown';

  @Column({ name: 'size', type: 'enum', enum: PET_SIZE, enumName: 'pet_size', nullable: true })
  size!: 'small' | 'medium' | 'large' | null;

  @Column({ name: 'vaccinated', type: 'boolean' })
  vaccinated!: boolean;

  @Column({ name: 'neutered', type: 'boolean' })
  neutered!: boolean;

  @Column({ name: 'weight_kg', type: 'numeric', nullable: true })
  weightKg!: string | null;

  @Column({ name: 'description', type: 'text', nullable: true })
  description!: string | null;

  @Column({ name: 'location', type: 'varchar' })
  location!: string;

  @Column({ name: 'status', type: 'enum', enum: PET_STATUS, enumName: 'pet_status' })
  status!: 'available' | 'pending' | 'adopted' | 'cancelled';

  @Column({ name: 'adopted_at', type: 'timestamptz', nullable: true })
  adoptedAt!: Date | null;

  @Column({ name: 'like_count', type: 'integer', insert: false, update: false })
  likeCount!: number;

  @Column({ name: 'report_count', type: 'integer', insert: false, update: false })
  reportCount!: number;

  @Column({ name: 'created_at', type: 'timestamptz', insert: false, update: false })
  createdAt!: Date;

  @Column({ name: 'updated_at', type: 'timestamptz', insert: false, update: false })
  updatedAt!: Date;

  @Column({ name: 'deleted_at', type: 'timestamptz', nullable: true })
  deletedAt!: Date | null;

  @Column({ name: 'age_label', type: 'varchar', nullable: true })
  ageLabel!: string | null;

  @Column({ name: 'species_other', type: 'varchar', nullable: true })
  speciesOther!: string | null;
}
