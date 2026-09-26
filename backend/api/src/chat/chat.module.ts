import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { QueueModule } from '../queue/queue.module.js';
import { ChatController } from './chat.controller.js';
import { ChatService } from './chat.service.js';
import { ChatGateway } from './chat.gateway.js';

@Module({
  imports: [JwtModule.register({}), QueueModule],
  controllers: [ChatController],
  providers: [ChatService, ChatGateway],
})
export class ChatModule {}
