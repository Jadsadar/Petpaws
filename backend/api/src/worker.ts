import { NestFactory } from '@nestjs/core';
import { WorkerModule } from './worker.module.js';

async function bootstrap() {
  // application context = ไม่เปิด HTTP port มีแค่ BullMQ worker ที่ดึงงานจาก Redis
  const app = await NestFactory.createApplicationContext(WorkerModule);
  // SIGTERM/SIGINT -> ปิด worker ให้ job ที่กำลังทำเสร็จก่อน ไม่ทิ้งค้างกลางทาง
  app.enableShutdownHooks();
  // eslint-disable-next-line no-console
  console.log('PetPaws worker started');
}

bootstrap();
