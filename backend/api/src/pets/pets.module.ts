import { Module } from '@nestjs/common';
import { ChatModule } from '../chat/chat.module.js';
import { PetsController } from './pets.controller.js';
import { PetsService } from './pets.service.js';

@Module({
  imports: [ChatModule],
  controllers: [PetsController],
  providers: [PetsService],
})
export class PetsModule {}
