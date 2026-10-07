import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import 'admin_cache_stats_widgets.dart';
import 'admin_widgets.dart';
import '../../widgets/paw_loader.dart';

const Duration _autoRefresh = Duration(seconds: 15);

/// หน้าดูอัตรา cache hit/miss ของ API แยกตามชนิดข้อมูล + สถานะ Redis cache
/// รีเฟรชเองทุก 15 วินาทีระหว่างเปิดหน้านี้ไว้
class AdminCacheStatsScreen extends StatefulWidget {
  const AdminCacheStatsScreen({super.key});

  @override
  State<AdminCacheStatsScreen> createState() => _AdminCacheStatsScreenState();
}

class _AdminCacheStatsScreenState extends State<AdminCacheStatsScreen> {
  CacheStats? _stats;
  Object? _error;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_autoRefresh, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await AdminService.instance.cacheStats();
      if (!mounted) return;
      setState(() {
        _stats = s;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // มีข้อมูลเก่าอยู่แล้วให้แสดงต่อ แค่แจ้งว่ารีเฟรชไม่สำเร็จ ไม่ล้างจอเป็นหน้า error
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เริ่มนับใหม่'),
        content: const Text('ล้างตัวนับ hit/miss ทั้งหมดแล้วเริ่มนับจากตอนนี้\n(ข้อมูลที่ cache ไว้ยังอยู่)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('เริ่มนับใหม่')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AdminService.instance.resetCacheStats();
      if (mounted) showAdminSnack(context, 'เริ่มนับใหม่แล้ว');
    } catch (e) {
      if (mounted) showAdminSnack(context, adminErrorMessage(e));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('สถิติ cache', style: TextStyle(fontWeight: FontWeight.bold, color: adminOrange)),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        iconTheme: const IconThemeData(color: adminOrange),
        actions: [
          IconButton(
            key: const ValueKey('cache-reset'),
            onPressed: _stats?.available == true ? _reset : null,
            icon: const Icon(Icons.restart_alt),
            tooltip: 'เริ่มนับใหม่',
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: PawLoader(color: adminOrange));
    final s = _stats;
    if (s == null) return AdminErrorView(error: _error!, onRetry: _load);

    return RefreshIndicator(
      color: adminOrange,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            CacheBanner(color: AppColors.warning, text: 'รีเฟรชไม่สำเร็จ: ${adminErrorMessage(_error!)}'),
          if (!s.enabled)
            const CacheBanner(
                color: AppColors.danger,
                text: 'ปิด cache อยู่ (server ไม่ได้ตั้ง REDIS_CACHE_URL) — ทุก request อ่าน DB ตรง')
          else if (!s.available)
            const CacheBanner(
                color: AppColors.danger, text: 'ต่อ Redis cache ไม่ได้ — API ยังทำงานโดยอ่าน DB ตรง แต่จะช้าลง'),
          CacheOverallCard(stats: s),
          const SizedBox(height: 20),
          const CacheSectionTitle('แยกตามชนิดข้อมูล'),
          for (final n in s.namespaces) CacheNamespaceTile(ns: n),
          if (s.redis != null) ...[
            const SizedBox(height: 20),
            const CacheSectionTitle('Redis server'),
            CacheRedisCard(redis: s.redis!, errors: s.errors),
          ],
          const SizedBox(height: 16),
          Text(
            'เกณฑ์: ≥ ${(goodHitRatio * 100).round()}% ดี · ${(fairHitRatio * 100).round()}-${(goodHitRatio * 100).round()}% '
            'ควรดู TTL/การล้าง cache · ต่ำกว่านั้น cache แทบไม่ช่วย\n'
            'สีจะขึ้นเมื่อมีอย่างน้อย $minSampleForColor request · รีเฟรชอัตโนมัติทุก ${_autoRefresh.inSeconds} วินาที',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
