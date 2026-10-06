import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { APP_GUARD } from '@nestjs/core';
import { AppController } from './app.controller.js';
import { DatabaseModule } from './database/database.module.js';
import { AuthModule } from './auth/auth.module.js';
import { UsersModule } from './users/users.module.js';
import { TraitsModule } from './traits/traits.module.js';
import { PetsModule } from './pets/pets.module.js';
import { MediaModule } from './media/media.module.js';
import { ChatModule } from './chat/chat.module.js';
import { ModerationModule } from './moderation/moderation.module.js';
import { DevicesModule } from './devices/devices.module.js';
import { AdminModule } from './admin/admin.module.js';
import { JwtAuthGuard } from './common/jwt-auth.guard.js';
import { AppConfigModule } from './config/app-config.module.js';
import { CacheModule } from './cache/cache.module.js';
import { ThrottlerModule } from '@nestjs/throttler';
import { AppThrottlerGuard, DEFAULT_RATE_LIMIT } from './common/rate-limit.js';

@Module({
  imports: [
    AppConfigModule,
    JwtModule.register({}),
    ThrottlerModule.forRoot([DEFAULT_RATE_LIMIT]),
    DatabaseModule,
    CacheModule,
    AuthModule,
    UsersModule,
    TraitsModule,
    PetsModule,
    MediaModule,
    ChatModule,
    ModerationModule,
    DevicesModule,
    AdminModule,
  ],
  controllers: [AppController],
  // ลำดับมีผล: JwtAuthGuard ต้องมาก่อน ให้ rate limit นับต่อบัญชีจาก request.user ได้
  providers: [
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: AppThrottlerGuard },
  ],
})
export class AppModule {}
