-- =============================================================================
-- 019 — เปิด pg_stat_statements (สถิติต่อ query) ไว้วัดว่า query ไหนควรปรับก่อน
--
-- ต้องคู่กับ shared_preload_libraries=pg_stat_statements ใน docker-compose (ตอนเปิด server)
-- ไม่มีค่านั้น CREATE EXTENSION ยังผ่าน แต่อ่าน view ไม่ได้ — API แค่รายงานว่ายังใช้ไม่ได้ ไม่พัง
-- ดูผลที่ GET /admin/perf-stats
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
