import { defineConfig } from 'vitest/config';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  // Resolves the path aliases declared in tsconfig.json, including the ones
  // added by `nest g library`.
  plugins: [tsconfigPaths()],
  test: {
    globals: true,
    root: './',
    include: ['**/*.spec.ts'],
    // ใช้กับ `npm run test:cov` (CI รันตัวนี้) — นับทุกไฟล์ใน src ไม่ใช่แค่ไฟล์ที่เทสต์ import
    coverage: {
      provider: 'v8',
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.spec.ts', 'src/main.ts', 'src/worker.ts'],
      reporter: ['text-summary', 'lcov'],
      // เกณฑ์แบบ ratchet: ตั้งไว้ที่ค่าปัจจุบัน (ต.ค. 2026) coverage ห้ามลดลงจากนี้
      // เพิ่มเทสต์เมื่อไหร่ให้ขยับตัวเลขขึ้นตาม เป้าระยะยาวคือ 70% เหมือน Quality Gate ทั่วไป
      thresholds: {
        lines: 12,
        statements: 13,
        functions: 9,
        branches: 14,
      },
    },
  },
});
