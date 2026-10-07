import { TypeOrmModule } from '@nestjs/typeorm';
import { Block, Report } from '../database/entities/index.js';
import { Module } from '@nestjs/common';
import { ModerationController } from './moderation.controller.js';
import { ModerationService } from './moderation.service.js';

@Module({
  imports: [TypeOrmModule.forFeature([Report, Block])],
  controllers: [ModerationController],
  providers: [ModerationService],
})
export class ModerationModule {}
