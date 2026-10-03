import { Body, Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import { ChatService } from './chat.service.js';
import { CreateChatDto } from './dto/create-chat.dto.js';
import { SendMessageDto } from './dto/send-message.dto.js';
import { CurrentUser, type AuthUser } from '../common/current-user.decorator.js';

@Controller('chats')
export class ChatController {
  constructor(private readonly chatService: ChatService) {}

  @Get('unread-count')
  unreadCount(@CurrentUser() user: AuthUser) {
    return this.chatService.unreadCount(user.id);
  }

  @Get()
  list(@CurrentUser() user: AuthUser, @Query('petName') petName?: string) {
    return this.chatService.list(user.id, petName);
  }

  @Post()
  createOrSend(@CurrentUser() user: AuthUser, @Body() dto: CreateChatDto) {
    return this.chatService.createOrSend(user.id, dto);
  }

  @Get(':id')
  detail(@Param('id') id: string, @CurrentUser() user: AuthUser) {
    return this.chatService.detail(user.id, id);
  }

  @Delete(':id')
  hide(@Param('id') id: string, @CurrentUser() user: AuthUser) {
    return this.chatService.hide(user.id, id);
  }

  @Get(':id/messages')
  messages(@Param('id') id: string, @CurrentUser() user: AuthUser) {
    return this.chatService.messages(user.id, id);
  }

  @Post(':id/messages')
  sendMessage(
    @Param('id') id: string,
    @CurrentUser() user: AuthUser,
    @Body() dto: SendMessageDto,
  ) {
    return this.chatService.sendMessage(user.id, id, dto);
  }

  @Post(':id/read')
  markRead(@Param('id') id: string, @CurrentUser() user: AuthUser) {
    return this.chatService.markRead(user.id, id);
  }
}
