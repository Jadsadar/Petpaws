import { IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';

export class BanUserDto {
  // ไม่ส่ง = แบนถาวร (suspended_until = NULL) จนกว่าแอดมินจะปลดเอง
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(3650)
  days?: number;

  @IsOptional()
  @IsString()
  @MaxLength(200)
  note?: string;
}
