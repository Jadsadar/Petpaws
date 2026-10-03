import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { AdminService } from './admin.service.js';
import { AdminGuard } from './admin.guard.js';
import { BanUserDto } from './dto/ban-user.dto.js';
import { PaginationQueryDto, resolvePaging } from './dto/pagination.dto.js';
import { DEFAULT_MIN_REPORTS, ReportedUsersQueryDto } from './dto/reported-users-query.dto.js';
import { CurrentUser, type AuthUser } from '../common/current-user.decorator.js';

@Controller('admin')
@UseGuards(AdminGuard)
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('summary')
  summary() {
    return this.adminService.summary();
  }

  /** ?minReports=&page=&pageSize= → { items, total, page, pageSize } */
  @Get('reported-users')
  reportedUsers(@Query() query: ReportedUsersQueryDto) {
    return this.adminService.reportedUsers(query.minReports ?? DEFAULT_MIN_REPORTS, resolvePaging(query));
  }

  @Get('banned-users')
  bannedUsers(@Query() query: PaginationQueryDto) {
    return this.adminService.bannedUsers(resolvePaging(query));
  }

  /** โปรไฟล์ + ประกาศทั้งหมดของผู้ใช้ พร้อมรูป (ให้แอดมินตรวจสิ่งที่ถูกรายงาน) */
  @Get('users/:id')
  userProfile(@Param('id', ParseUUIDPipe) id: string) {
    return this.adminService.userProfile(id);
  }

  @Get('users/:id/reports')
  userReports(@Param('id', ParseUUIDPipe) id: string, @Query() query: PaginationQueryDto) {
    return this.adminService.userReports(id, resolvePaging(query));
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
