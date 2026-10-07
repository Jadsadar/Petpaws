import { Injectable, NestMiddleware } from '@nestjs/common';
import type { NextFunction, Request, Response } from 'express';
import { MetricsService } from './metrics.service.js';

/**
 * จับเวลาทุก HTTP request นับแยกตาม route pattern (เช่น "GET /chats/:id/messages" ไม่ใช่ id จริง
 * — ไม่งั้นทุกห้องแชทกลายเป็นคนละแถว) ข้าม health check ที่ถูกยิงทุกไม่กี่วินาที
 *
 * เป็น middleware ไม่ใช่ interceptor: guard (JWT, rate limit) ทำงานก่อน interceptor
 * request ที่ถูกปฏิเสธจะไม่ถูกนับเลย — ตอน 'finish' express จับคู่ route ให้แล้ว (req.route)
 */
@Injectable()
export class RequestTimingMiddleware implements NestMiddleware {
  constructor(private readonly metrics: MetricsService) {}

  use(req: Request, res: Response, next: NextFunction) {
    const started = performance.now();
    res.on('finish', () => {
      const path = (req.route as { path?: string } | undefined)?.path ?? req.path;
      if (path.startsWith('/health')) return;
      this.metrics.record(`${req.method} ${path}`, performance.now() - started);
    });
    next();
  }
}
