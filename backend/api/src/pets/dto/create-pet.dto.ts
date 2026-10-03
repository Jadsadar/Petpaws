import { IsArray, IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { PET_SPECIES } from '../pet-mappers.js';

// ชื่อ field ตรงกับ "dog" map ที่ upload_screen.dart ส่งมาเป๊ะ ๆ
// (name, breed, province, age, gender, weight, tags, story, imageUrl)
export class CreatePetDto {
  @IsString()
  @MaxLength(50)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  breed?: string;

  // dog | cat | bird | fish | rabbit | other (ไม่ส่งมา = dog ตามค่าเริ่มต้นของตาราง)
  @IsOptional()
  @IsIn(PET_SPECIES)
  species?: string;

  // ข้อความที่พิมพ์เองเมื่อ species = 'other' (เช่น หนู, เต่า) — ถูกล้างทิ้งถ้าเลือกชนิดอื่น
  @IsOptional()
  @IsString()
  @MaxLength(50)
  speciesOther?: string;

  @IsString()
  province!: string;

  @IsString()
  @MaxLength(50)
  age!: string;

  @IsString()
  gender!: string; // 'ผู้' | 'เมีย'

  @IsOptional()
  @IsString()
  weight?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  tags?: string[];

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  story?: string;

  // upload_screen.dart ส่งค่านี้มาเสมอ แต่เป็น '' ได้ถ้ายังไม่ได้เลือกรูป
  // (ตาม ROADMAP.md "เส้นทางสั้นที่สุดถึงลงประกาศได้" — ลงประกาศไม่ใส่รูปก่อนได้)
  // ไม่ใช้ @IsUrl() เพราะจะปฏิเสธค่าว่างทั้งที่ @IsOptional() ควรอนุญาต — ตรวจรูปแบบ
  // URL เองในชั้น service เฉพาะตอนค่าไม่ว่างแทน
  @IsOptional()
  @IsString()
  imageUrl?: string;
}
