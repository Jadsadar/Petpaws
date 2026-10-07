import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Trait } from '../database/entities/index.js';
import { TraitsController } from './traits.controller.js';

@Module({
  imports: [TypeOrmModule.forFeature([Trait])],
  controllers: [TraitsController],
})
export class TraitsModule {}
