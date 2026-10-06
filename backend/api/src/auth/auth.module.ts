import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AuthController } from './auth.controller.js';
import { AuthService } from './auth.service.js';
import { MailModule } from '../mail/mail.module.js';
import { EmailVerificationToken, PasswordResetToken, RefreshToken, User } from '../database/entities/index.js';

@Module({
  imports: [
    JwtModule.register({}),
    MailModule,
    TypeOrmModule.forFeature([User, RefreshToken, PasswordResetToken, EmailVerificationToken]),
  ],
  controllers: [AuthController],
  providers: [AuthService],
})
export class AuthModule {}
