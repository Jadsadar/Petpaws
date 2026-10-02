import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ChatService } from './chat.service.js';
import { CreateChatDto } from './dto/create-chat.dto.js';
import { CreateMediaUploadDto } from './dto/create-media-upload.dto.js';
import { ListMessagesQueryDto } from './dto/list-messages.dto.js';
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

  /** ขอใบอนุญาตอัปรูป/วิดีโอ + thumbnail ตรงไป S3 ก่อนส่งข้อความที่แนบไฟล์ */
  @Post('media-uploads')
  createMediaUpload(@CurrentUser() user: AuthUser, @Body() dto: CreateMediaUploadDto) {
    return this.chatService.createMediaUpload(user.id, dto);
  }

  @Get(':id/messages')
  messages(
    @Param('id') id: string,
    @CurrentUser() user: AuthUser,
    @Query() query: ListMessagesQueryDto,
  ) {
    return this.chatService.messages(user.id, id, query);
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
