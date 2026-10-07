import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, type Repository } from 'typeorm';
import { AppException } from '../common/app-exception.js';
import { User } from '../database/entities/index.js';

/**
 * ใช้คู่กับ JwtAuthGuard (global) ซึ่งรันก่อนและแนบ request.user ไว้แล้ว
 * เช็ก is_admin จาก DB ทุกครั้ง ไม่ใช่จาก JWT — payload มีแค่ sub และถ้าถอด
 * สิทธิ์แอดมินต้องมีผลทันที ไม่ใช่รอ token หมดอายุ
 */
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(@InjectRepository(User) private readonly users: Repository<User>) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const userId: string | undefined = context.switchToHttp().getRequest().user?.id;
    if (!userId) throw AppException.unauthorized();

    const user = await this.users.findOne({ select: { isAdmin: true }, where: { id: userId, deletedAt: IsNull() } });
    if (!user?.isAdmin) throw AppException.forbidden('เฉพาะแอดมินเท่านั้น');
    return true;
  }
}
