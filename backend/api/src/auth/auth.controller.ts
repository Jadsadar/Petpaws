import { Body, Controller, Get, Header, HttpCode, HttpStatus, Post, Query, Res } from '@nestjs/common';
import type { Response } from 'express';
import { AuthService } from './auth.service.js';
import { RegisterDto } from './dto/register.dto.js';
import { LoginDto } from './dto/login.dto.js';
import { RefreshDto } from './dto/refresh.dto.js';
import { ForgotPasswordDto } from './dto/forgot-password.dto.js';
import { ResetPasswordDto } from './dto/reset-password.dto.js';
import { ResendVerificationDto } from './dto/resend-verification.dto.js';
import { VerifyEmailQueryDto } from './dto/verify-email-query.dto.js';
import { ResetPasswordFormDto, ResetPasswordQueryDto } from './dto/reset-password-page.dto.js';
import { resetFormPage, resetResultPage, verifyResultPage } from './email-templates.js';
import { Public } from '../common/public.decorator.js';
import { Throttle } from '@nestjs/throttler';
import { AUTH_RATE_LIMITS } from '../common/rate-limit.js';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Throttle({ default: AUTH_RATE_LIMITS.register })
  @Post('register')
  register(@Body() dto: RegisterDto) {
    return this.authService.register(dto);
  }

  @Public()
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: AUTH_RATE_LIMITS.login })
  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto);
  }

  /** ลิงก์ที่ผู้ใช้กดจากอีเมล (เปิดในเบราว์เซอร์) — คืนหน้า HTML ผลการยืนยัน */
  @Public()
  @Throttle({ default: AUTH_RATE_LIMITS.verifyEmail })
  @Get('verify-email')
  @Header('Cache-Control', 'no-store')
  @Header('Referrer-Policy', 'no-referrer')
  async verifyEmail(@Query() query: VerifyEmailQueryDto, @Res({ passthrough: true }) res: Response) {
    const outcome = await this.authService.verifyEmail(query.token);
    res.status(outcome === 'ok' ? HttpStatus.OK : HttpStatus.BAD_REQUEST);
    res.type('html');
    return verifyResultPage(outcome);
  }

  @Public()
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: AUTH_RATE_LIMITS.resendVerification })
  @Post('resend-verification')
  resendVerification(@Body() dto: ResendVerificationDto) {
    return this.authService.resendVerification(dto.identifier);
  }

  @Public()
  @HttpCode(HttpStatus.OK)
  @Post('refresh')
  refresh(@Body() dto: RefreshDto) {
    return this.authService.refresh(dto.refreshToken);
  }

  @Public()
  @HttpCode(HttpStatus.OK)
  @Post('logout')
  logout(@Body() dto: RefreshDto) {
    return this.authService.logout(dto.refreshToken);
  }

  @Public()
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: AUTH_RATE_LIMITS.forgotPassword })
  @Post('forgot-password')
  forgotPassword(@Body() dto: ForgotPasswordDto) {
    return this.authService.forgotPassword(dto.email);
  }

  @Public()
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: AUTH_RATE_LIMITS.resetPassword })
  @Post('reset-password')
  resetPassword(@Body() dto: ResetPasswordDto) {
    return this.authService.resetPassword(dto.token, dto.newPassword);
  }

  /**
   * ลิงก์ที่ผู้ใช้กดจากอีเมล "ลืมรหัสผ่าน" (เปิดในเบราว์เซอร์) — ถ้าลิงก์ใช้ได้ คืนฟอร์มตั้งรหัสใหม่
   * การเปิดหน้านี้ไม่ใช้ลิงก์ทิ้ง (กันโปรแกรมสแกนลิงก์ในอีเมลกดแทนผู้ใช้) ลิงก์ถูกใช้ตอนกดบันทึกเท่านั้น
   */
  @Public()
  @Throttle({ default: AUTH_RATE_LIMITS.resetPasswordPage })
  @Get('reset-password')
  @Header('Cache-Control', 'no-store')
  @Header('Referrer-Policy', 'no-referrer')
  async resetPasswordPage(@Query() query: ResetPasswordQueryDto, @Res({ passthrough: true }) res: Response) {
    const outcome = await this.authService.checkResetToken(query.token);
    res.type('html');
    if (outcome !== 'ok') {
      res.status(HttpStatus.BAD_REQUEST);
      return resetResultPage(outcome);
    }
    return resetFormPage({ token: query.token });
  }

  /** ฟอร์มบนหน้าเว็บด้านบนส่งมาที่นี่ (form-urlencoded) — ตอบเป็นหน้าเว็บ ไม่ใช่ JSON */
  @Public()
  @HttpCode(HttpStatus.OK)
  @Throttle({ default: AUTH_RATE_LIMITS.resetPassword })
  @Post('reset-password/form')
  @Header('Cache-Control', 'no-store')
  @Header('Referrer-Policy', 'no-referrer')
  async resetPasswordForm(@Body() dto: ResetPasswordFormDto, @Res({ passthrough: true }) res: Response) {
    const result = await this.authService.resetPasswordFromPage(dto.token, dto.newPassword, dto.confirmPassword);
    res.type('html');
    if (result.outcome === 'retry') {
      res.status(HttpStatus.BAD_REQUEST);
      return resetFormPage({ token: dto.token, error: result.message });
    }
    if (result.outcome !== 'ok') res.status(HttpStatus.BAD_REQUEST);
    return resetResultPage(result.outcome);
  }
}
