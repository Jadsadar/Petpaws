# ใช้ node:22 ตรงกับเวอร์ชันที่ CI (.github/workflows/ci.yml) ทดสอบไว้
# ใช้ตัว -bookworm-slim (glibc) ไม่ใช่ alpine เพราะ argon2 มี prebuilt binary
# สำหรับ glibc เสถียรกว่า ถ้าใช้ alpine (musl) เสี่ยง build native module พังตอน npm ci

FROM node:22-bookworm-slim AS builder
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

# ---- runtime stage ----
FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production

# ลงแพตช์ความปลอดภัยของ Debian ที่ออกหลัง base image ถูกสร้าง (image node:22 อัปเดตช้ากว่า)
# เช่น CVE-2026-103111 ใน libpcre2-8-0 ที่ Trivy ใน CI บล็อกไว้ — ไม่ต้องรอ node ออก image ใหม่
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
# ตอนรันจริงใช้แค่ `node` (api, worker, HEALTHCHECK) ไม่ได้ใช้ npm/npx/corepack/yarn
# เลยลบทิ้งหลังลง dependency เสร็จ — Trivy เจอช่องโหว่ HIGH 10 ตัวใน dependency ของ
# npm CLI ที่ติดมากับ base image เอง (brace-expansion, pacote, sigstore ฯลฯ) ไม่ใช่ของแอป
RUN npm ci --omit=dev \
 && npm cache clean --force \
 && rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /usr/local/bin/yarn /usr/local/bin/yarnpkg /opt/yarn-*

COPY --from=builder /app/dist ./dist

USER node
EXPOSE 3000

# เช็คผ่าน node ตรงๆ ไม่ต้องลง curl/wget เพิ่มให้ image ใหญ่ขึ้น
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://localhost:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]

CMD ["node", "dist/main"]
