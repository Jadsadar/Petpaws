import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import 'admin_cache_stats_widgets.dart';
import 'admin_widgets.dart';

final _countFormat = NumberFormat.decimalPattern();
String _count(int value) => _countFormat.format(value);
String _duration(double value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(2)} s'
    : '${value.toStringAsFixed(1)} ms';

enum _ApiSort { count, total, average }

class ApiMonitoringPanel extends StatefulWidget {
  const ApiMonitoringPanel({super.key, required this.stats});
  final PerfStats stats;

  @override
  State<ApiMonitoringPanel> createState() => _ApiMonitoringPanelState();
}

class _ApiMonitoringPanelState extends State<ApiMonitoringPanel> {
  _ApiSort _sort = _ApiSort.count;

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final routes = [...stats.routes]..sort((a, b) {
        final result = switch (_sort) {
          _ApiSort.count => b.count.compareTo(a.count),
          _ApiSort.total => b.totalMs.compareTo(a.totalMs),
          _ApiSort.average => b.avgMs.compareTo(a.avgMs),
        };
        return result != 0 ? result : a.route.compareTo(b.route);
      });
    final busiest = stats.routes.isEmpty
        ? null
        : stats.routes.reduce((a, b) => a.count >= b.count ? a : b);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('API ที่ถูกเรียกบ่อยที่สุด',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(
          'จำนวนคำขอสะสมทุกสถานะ · ไม่รวม Health check และการรีเฟรช Monitoring',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
      if (stats.since != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              'เริ่มนับ ${DateFormat('dd/MM/yyyy HH:mm').format(stats.since!.toLocal())}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        ),
      const SizedBox(height: 12),
      if (stats.scope == 'instance' || stats.scope == 'mixed')
        CacheBanner(
          color: AppColors.warning,
          text: stats.scope == 'instance'
              ? 'Redis ใช้ไม่ได้หรือไม่ได้เปิดอยู่: ตัวเลขมาจาก API instance ที่ตอบคำขอนี้เท่านั้น'
              : 'รวม Redis และตัวนับสำรองของ instance นี้: ช่วงที่ Redis ใช้ไม่ได้อาจนับไม่ครบทุก API',
        ),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: adminOrange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              '${_count(stats.totalRequests)} คำขอ · ${_count(stats.routes.length)} endpoints',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: adminOrange)),
          if (busiest != null) ...[
            const SizedBox(height: 10),
            SelectableText(busiest.route,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text(
                '${_count(busiest.count)} ครั้ง · ${stats.totalRequests == 0 ? '0' : (busiest.count / stats.totalRequests * 100).toStringAsFixed(1)}% ของคำขอทั้งหมด'),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<_ApiSort>(
        isExpanded: true,
        key: const ValueKey('api-sort'),
        initialValue: _sort,
        decoration: const InputDecoration(
            labelText: 'เรียงตาม', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(
              value: _ApiSort.count, child: Text('จำนวนคำขอมากที่สุด')),
          DropdownMenuItem(
              value: _ApiSort.total, child: Text('เวลารวมมากที่สุด')),
          DropdownMenuItem(
              value: _ApiSort.average, child: Text('เวลาเฉลี่ยมากที่สุด')),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _sort = value);
        },
      ),
      const SizedBox(height: 12),
      if (routes.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
              'ยังไม่มีคำขอ API ที่ถูกนับ ลองใช้งานระบบแล้วรีเฟรชอีกครั้ง'),
        ),
      for (var i = 0; i < routes.length; i++)
        _ApiRouteCard(
          route: routes[i],
          rank: i + 1,
          total: stats.totalRequests,
          slowThresholdMs: stats.slowThresholdMs,
        ),
      const SizedBox(height: 8),
      const Text(
          'สถิติคำขอ API รวมทุก API instance เมื่อ Redis พร้อมใช้งาน และเป็นยอดสะสมจนกว่าจะรีเซ็ตตัวนับ',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
    ]);
  }
}

class _ApiRouteCard extends StatelessWidget {
  const _ApiRouteCard(
      {required this.route,
      required this.rank,
      required this.total,
      required this.slowThresholdMs});
  final ApiRouteStats route;
  final int rank;
  final int total;
  final int slowThresholdMs;

  @override
  Widget build(BuildContext context) => Card(
        key: ValueKey('api-route-${route.route}'),
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$rank.',
                      style: const TextStyle(
                          color: adminOrange, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: SelectableText(route.route,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 8),
                Text('${_count(route.count)} ครั้ง',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: adminOrange)),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                    value: total > 0 ? route.count / total : 0,
                    color: adminOrange,
                    backgroundColor: adminOrange.withValues(alpha: 0.1)),
                const SizedBox(height: 10),
                Wrap(spacing: 16, runSpacing: 8, children: [
                  Text('เฉลี่ย ${_duration(route.avgMs)}'),
                  Text('สูงสุด ${_duration(route.maxMs)}'),
                  Text('รวม ${_duration(route.totalMs)}'),
                  Text(
                      'ช้า ≥ $slowThresholdMs ms: ${_count(route.slowCount)} ครั้ง',
                      style: TextStyle(
                          color: route.slowCount > 0
                              ? AppColors.danger
                              : Colors.grey.shade700)),
                ]),
              ],
            )),
      );
}

class SqlMonitoringPanel extends StatelessWidget {
  const SqlMonitoringPanel({super.key, required this.stats});
  final PerfStats stats;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('สถิติ SQL',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
            'pg_stat_statements · 15 queries ที่ใช้เวลารวมมากที่สุดของฐานข้อมูลนี้'),
        const SizedBox(height: 8),
        Text(
            'จำนวนครั้งของ SQL แยกจากจำนวนคำขอ API เพราะคำขอหนึ่งอาจเรียกหลาย queries หรืออ่านจาก Cache',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
        const SizedBox(height: 16),
        if (!stats.sqlAvailable) ...[
          const CacheBanner(
              color: AppColors.warning,
              text:
                  'ยังอ่าน pg_stat_statements ไม่ได้ แต่สถิติ API และ Cache ยังดูได้ตามปกติ'),
          if (stats.sqlReason != null)
            SelectableText(stats.sqlReason!,
                style: const TextStyle(fontSize: 12)),
        ] else if (stats.queries.isEmpty)
          const Text('ยังไม่มีสถิติ SQL')
        else
          for (var i = 0; i < stats.queries.length; i++)
            Card(
              key: ValueKey('sql-query-$i'),
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: Text(
                    '${i + 1}. ${_count(stats.queries[i].calls)} ครั้ง · รวม ${_duration(stats.queries[i].totalMs)}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'เฉลี่ย ${_duration(stats.queries[i].meanMs)} · ${_count(stats.queries[i].rows)} แถว'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(stats.queries[i].query,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)))
                ],
              ),
            ),
      ]);
}
