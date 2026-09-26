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

@Module({
  imports: [
    AppConfigModule,
    JwtModule.register({}),
    DatabaseModule,
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
  providers: [{ provide: APP_GUARD, useClass: JwtAuthGuard }],
})
export class AppModule {}
