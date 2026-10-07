import { Global, MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { MetricsService } from './metrics.service.js';
import { RequestTimingMiddleware } from './request-timing.middleware.js';

/** วัดเวลาต่อ endpoint + query ของ DB — ดูผลที่ GET /admin/perf-stats */
@Global()
@Module({
  providers: [MetricsService],
  exports: [MetricsService],
})
export class MetricsModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(RequestTimingMiddleware).forRoutes('*');
  }
}
