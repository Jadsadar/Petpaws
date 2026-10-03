import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { PetsService } from './pets.service.js';
import { CreatePetDto } from './dto/create-pet.dto.js';
import { UpdatePetDto } from './dto/update-pet.dto.js';
import { CurrentUser, type AuthUser } from '../common/current-user.decorator.js';

@Controller('pets')
export class PetsController {
  constructor(private readonly petsService: PetsService) {}

  // route คงที่ (deck/mine/likes) ต้องมาก่อน @Get(':id') เสมอ
  // ไม่งั้น Nest จะจับคำว่า "deck"/"mine"/"likes" เป็นค่า :id ไปตรง ๆ
  @Get('deck')
  deck(
    @CurrentUser() user: AuthUser,
    @Query('cursor') cursor?: string,
    @Query('province') province?: string,
    @Query('species') species?: string,
    @Query('tags') tags?: string,
    @Query('limit') limit?: string,
  ) {
    return this.petsService.deck(user.id, {
      cursor,
      province,
      species,
      traitSlugs: tags ? tags.split(',').filter(Boolean) : undefined,
      limit: limit ? Number(limit) : undefined,
    });
  }

  @Get('mine')
  findMine(@CurrentUser() user: AuthUser) {
    return this.petsService.findByOwner(user.id);
  }

  @Get('by-owner/:ownerId')
  findByOwner(@Param('ownerId') ownerId: string) {
    return this.petsService.findByOwner(ownerId);
  }

  @Get('likes')
  myLikes(@CurrentUser() user: AuthUser) {
    return this.petsService.myLikes(user.id);
  }

  @Post()
  create(@CurrentUser() user: AuthUser, @Body() dto: CreatePetDto) {
    return this.petsService.create(user.id, dto);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.petsService.findOne(id);
  }

  @Patch(':id')
  update(
    @Param('id') id: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: UpdatePetDto,
  ) {
    return this.petsService.update(id, user.id, dto);
  }

  @Delete(':id')
  remove(@Param('id') id: string, @CurrentUser() user: AuthUser) {
    return this.petsService.remove(id, user.id);
  }

  @Post(':id/like')
  like(@Param('id') id: string, @CurrentUser() user: AuthUser) {
    return this.petsService.like(id, user.id);
  }

  @Delete(':id/like')
  unlike(@Param('id') id: string, @CurrentUser() user: AuthUser) {
    return this.petsService.unlike(id, user.id);
  }

  @Post(':id/pass')
  pass(@Param('id') id: string, @CurrentUser() user: AuthUser) {
    return this.petsService.pass(id, user.id);
  }

  // ปุ่ม "undo" ในหน้า Discover ต้องลบการปัดออกจริงที่ DB ไม่ใช่แค่คืนการ์ด
  // กลับมาในหน่วยความจำเฉย ๆ ไม่งั้นปิดแอปแล้วเปิดใหม่การ์ดจะหายไปถาวร
  @Delete(':id/pass')
  unpass(@Param('id') id: string, @CurrentUser() user: AuthUser) {
    return this.petsService.unpass(id, user.id);
  }
}
