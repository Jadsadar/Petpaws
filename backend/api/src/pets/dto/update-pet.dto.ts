import { IsArray, IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { PET_SPECIES } from '../pet-mappers.js';

// ทุก field optional เพราะ EditDogScreen ส่ง partial update และ upload_screen's
// สถานะ dropdown ก็ยิง PATCH เดียวกันนี้โดยส่งแค่ field `status`
export class UpdatePetDto {
  @IsOptional() @IsString() @MaxLength(50) name?: string;
  @IsOptional() @IsString() @MaxLength(80) breed?: string;
  @IsOptional() @IsIn(PET_SPECIES) species?: string;
  @IsOptional() @IsString() @MaxLength(50) speciesOther?: string;
  @IsOptional() @IsString() province?: string;
  @IsOptional() @IsString() @MaxLength(50) age?: string;
  @IsOptional() @IsString() gender?: string;
  @IsOptional() @IsString() weight?: string;
  @IsOptional() @IsArray() @IsString({ each: true }) tags?: string[];
  @IsOptional() @IsString() @MaxLength(2000) story?: string;
  @IsOptional() @IsString() imageUrl?: string;
  // 'ยังไม่ถูกรับเลี้ยง' | 'ถูกรับเลี้ยงแล้ว' | 'ยกเลิกประกาศ'
  @IsOptional() @IsString() status?: string;
}
