import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import 'admin_widgets.dart';

/// ชื่อไทยของกลุ่ม cache ฝั่ง backend (backend/api/src/cache/cache.constants.ts)
const Map<String, String> _namespaceLabels = {
  'traits': 'แท็กนิสัย',
  'pet': 'ประกาศ (รายตัว)',
  'petsByOwner': 'ประกาศของผู้ใช้',
  'userPublic': 'โปรไฟล์สาธารณะ',
  'adminSummary': 'ตัวเลขสรุปแอดมิน',
};

/// เกณฑ์สีของ hit ratio: ตั้งแต่ 80% ถือว่าดี, 50-80% ควรดู TTL/การล้าง cache, ต่ำกว่านั้นแทบไม่ช่วย
const double goodHitRatio = 0.8;
const double fairHitRatio = 0.5;

/// ต้องมี request อย่างน้อยเท่านี้ก่อนจะตัดสินสีจาก ratio ไม่งั้น 1 miss แรกก็ขึ้นแดง
const int minSampleForColor = 20;

Color hitRatioColor(double? ratio, int total) {
  if (ratio == null || total < minSampleForColor) return Colors.grey.shade600;
  if (ratio >= goodHitRatio) return AppColors.success;
  if (ratio >= fairHitRatio) return AppColors.warning;
  return AppColors.danger;
}

String formatRatio(double? ratio) => ratio == null ? '-' : '${(ratio * 100).toStringAsFixed(1)}%';

String _formatBytes(int b) {
  if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '$b B';
}

String _formatDuration(int seconds) {
  if (seconds >= 86400) return '${seconds ~/ 86400} วัน ${(seconds % 86400) ~/ 3600} ชม.';
  if (seconds >= 3600) return '${seconds ~/ 3600} ชม. ${(seconds % 3600) ~/ 60} นาที';
  if (seconds >= 60) return '${seconds ~/ 60} นาที';
  return '$seconds วินาที';
}

String _formatTtl(int seconds) => seconds >= 3600
    ? '${seconds ~/ 3600} ชม.'
    : seconds >= 60
        ? '${seconds ~/ 60} นาที'
        : '$seconds วินาที';

class CacheBanner extends StatelessWidget {
  const CacheBanner({super.key, required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}

class CacheSectionTitle extends StatelessWidget {
  const CacheSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textDark)),
      );
}

class CacheOverallCard extends StatelessWidget {
  const CacheOverallCard({super.key, required this.stats});

  final CacheStats stats;

  @override
  Widget build(BuildContext context) {
    final o = stats.overall;
    final color = hitRatioColor(o.hitRatio, o.total);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Text('Hit ratio รวม', style: TextStyle(color: color)),
          Text(
            formatRatio(o.hitRatio),
            key: const ValueKey('cache-overall-ratio'),
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: color),
          ),
          Text('hit ${o.hits} · miss ${o.misses}', style: TextStyle(color: color)),
          const SizedBox(height: 4),
          Text('นับตั้งแต่ ${formatDateTime(stats.since)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

class CacheNamespaceTile extends StatelessWidget {
  const CacheNamespaceTile({super.key, required this.ns});

  final CacheNamespaceStats ns;

  @override
  Widget build(BuildContext context) {
    final c = ns.counter;
    final color = hitRatioColor(c.hitRatio, c.total);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_namespaceLabels[ns.name] ?? ns.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Text(formatRatio(c.hitRatio), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: c.hitRatio ?? 0,
              minHeight: 8,
              color: color,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'hit ${c.hits} · miss ${c.misses} · TTL ${_formatTtl(ns.ttlSeconds)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

class CacheRedisCard extends StatelessWidget {
  const CacheRedisCard({super.key, required this.redis, required this.errors});

  final RedisServerStats redis;
  final int errors;

  @override
  Widget build(BuildContext context) {
    final usage = redis.memoryUsage;
    final memory = redis.maxMemoryBytes > 0
        ? '${_formatBytes(redis.usedMemoryBytes)} / ${_formatBytes(redis.maxMemoryBytes)}'
        : '${_formatBytes(redis.usedMemoryBytes)} (ไม่จำกัด)';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration:
          BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _row('Hit ratio (ทุกคำสั่ง)', formatRatio(redis.counter.hitRatio)),
          _row('จำนวน key', '${redis.keys}'),
          _row('หน่วยความจำ', memory),
          if (usage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: LinearProgressIndicator(
                value: usage.clamp(0, 1).toDouble(),
                minHeight: 6,
                color: usage >= 0.9 ? AppColors.warning : adminOrange,
                backgroundColor: Colors.grey.shade200,
              ),
            ),
          // evicted ขึ้นเรื่อย ๆ = maxmemory เล็กไป key ถูกไล่ออกก่อนหมด TTL ทำให้ hit ratio ตก
          _row('ถูกไล่ออก (evicted)', '${redis.evictedKeys}', color: redis.evictedKeys > 0 ? AppColors.warning : null),
          _row('หมดอายุ (expired)', '${redis.expiredKeys}'),
          _row('นโยบายไล่ key', redis.maxMemoryPolicy ?? '-'),
          _row('เปิดมาแล้ว', _formatDuration(redis.uptimeSeconds)),
          _row('คำสั่ง cache ล้มเหลว (API process นี้)', '$errors', color: errors > 0 ? AppColors.danger : null),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade700))),
            Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      );
}
