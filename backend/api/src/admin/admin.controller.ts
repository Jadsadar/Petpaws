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
import { CacheService } from '../cache/cache.service.js';
import { MetricsService } from '../metrics/metrics.service.js';

@Controller('admin')
@UseGuards(AdminGuard)
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly cache: CacheService,
    private readonly metrics: MetricsService,
  ) {}

  @Get('summary')
  summary() {
    return this.adminService.summary();
  }

  /** อัตรา hit/miss ของ cache แยกตามชนิดข้อมูล + สถานะ Redis cache (หน้า "สถิติ cache" ในแอป) */
  @Get('cache-stats')
  cacheStats() {
    return this.cache.stats();
  }

  /** เริ่มนับ hit/miss ใหม่ (ไม่ลบข้อมูลที่ cache ไว้) */
  @HttpCode(HttpStatus.OK)
  @Post('cache-stats/reset')
  resetCacheStats() {
    return this.cache.resetStats();
  }

  /**
   * endpoint ที่ถูกเรียกบ่อยที่สุด + query ที่กินเวลา DB มากสุด (pg_stat_statements)
   * ใช้เลือกว่าจะปรับ query ตัวไหนก่อน
   */
  @Get('perf-stats')
  perfStats() {
    return this.metrics.stats();
  }

  /** เริ่มนับใหม่ (ทั้งเวลาต่อ endpoint และ pg_stat_statements) — ใช้ก่อน/หลังแก้เพื่อเทียบผล */
  @HttpCode(HttpStatus.OK)
  @Post('perf-stats/reset')
  resetPerfStats() {
    return this.metrics.reset();
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
