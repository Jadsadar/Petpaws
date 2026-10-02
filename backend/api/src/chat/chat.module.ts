import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { MediaModule } from '../media/media.module.js';
import { QueueModule } from '../queue/queue.module.js';
import { ChatController } from './chat.controller.js';
import { ChatService } from './chat.service.js';
import { ChatGateway } from './chat.gateway.js';
import { ChatMediaService } from './chat-media.service.js';

@Module({
  imports: [JwtModule.register({}), QueueModule, MediaModule],
  controllers: [ChatController],
  providers: [ChatService, ChatGateway, ChatMediaService],
})
export class ChatModule {}
