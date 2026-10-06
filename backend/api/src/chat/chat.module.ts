import { TypeOrmModule } from '@nestjs/typeorm';
import { Conversation, MediaUpload, Message } from '../database/entities/index.js';
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { MediaModule } from '../media/media.module.js';
import { QueueModule } from '../queue/queue.module.js';
import { ChatController } from './chat.controller.js';
import { ChatService } from './chat.service.js';
import { ChatGateway } from './chat.gateway.js';
import { ChatMediaService } from './chat-media.service.js';

@Module({
  imports: [
    JwtModule.register({}),
    QueueModule,
    MediaModule,
    TypeOrmModule.forFeature([Conversation, Message, MediaUpload]),
  ],
  controllers: [ChatController],
  providers: [ChatService, ChatGateway, ChatMediaService],
  exports: [ChatService],
})
export class ChatModule {}
