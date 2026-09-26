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

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY --from=builder /app/dist ./dist

USER node
EXPOSE 3000

# เช็คผ่าน node ตรงๆ ไม่ต้องลง curl/wget เพิ่มให้ image ใหญ่ขึ้น
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD ["node", "-e", "require('http').get('http://localhost:3000/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"]

CMD ["node", "dist/main"]
