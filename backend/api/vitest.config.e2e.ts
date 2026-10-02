import { defineConfig } from 'vitest/config';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  plugins: [tsconfigPaths()],
  test: {
    globals: true,
    root: './',
    include: ['**/*.e2e-spec.ts'],
    // บูต AppModule เต็มตัว (ต่อ DB, Redis, S3) ใช้เวลานานกว่าค่าเริ่มต้น 10 วินาทีได้บน CI
    hookTimeout: 30000,
  },
});
