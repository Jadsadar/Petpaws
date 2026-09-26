import {
  Body,
  Controller,
  DefaultValuePipe,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AdminService } from './admin.service.js';
import { AdminGuard } from './admin.guard.js';
import { BanUserDto } from './dto/ban-user.dto.js';
import { CurrentUser, type AuthUser } from '../common/current-user.decorator.js';

const DEFAULT_MIN_REPORTS = 10;

@Controller('admin')
@UseGuards(AdminGuard)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('reported-users')
  reportedUsers(
    @Query('minReports', new DefaultValuePipe(DEFAULT_MIN_REPORTS), ParseIntPipe) minReports: number,
  ) {
    return this.adminService.reportedUsers(Math.max(1, minReports));
  }

  @Get('banned-users')
  bannedUsers() {
    return this.adminService.bannedUsers();
  }

  @Get('users/:id/reports')
  userReports(@Param('id', ParseUUIDPipe) id: string) {
    return this.adminService.userReports(id);
  }

  @HttpCode(HttpStatus.OK)
  @Post('users/:id/ban')
  ban(
    @CurrentUser() admin: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: BanUserDto,
  ) {
    return this.adminService.ban(admin.id, id, dto);
  }

  @HttpCode(HttpStatus.OK)
  @Post('users/:id/unban')
  unban(@Param('id', ParseUUIDPipe) id: string) {
    return this.adminService.unban(id);
  }

  @HttpCode(HttpStatus.OK)
  @Post('users/:id/dismiss-reports')
  dismissReports(@CurrentUser() admin: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.adminService.dismissReports(admin.id, id);
  }
}
