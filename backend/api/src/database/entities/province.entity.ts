import { Column, Entity, PrimaryColumn } from 'typeorm';
import { THAI_REGION } from './enums.js';

@Entity({ name: 'provinces' })
export class Province {
  @PrimaryColumn({ name: 'name', type: 'varchar' })
  name!: string;

  @Column({ name: 'region', type: 'enum', enum: THAI_REGION, enumName: 'thai_region' })
  region!: 'central' | 'north' | 'northeast' | 'east' | 'west' | 'south';
}
