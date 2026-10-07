import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/paw_loader.dart';
import 'admin_cache_stats_screen.dart';
import 'admin_cache_stats_widgets.dart';
import 'admin_monitoring_widgets.dart';
import 'admin_widgets.dart';

class AdminMonitoringScreen extends StatefulWidget {
  const AdminMonitoringScreen({super.key});

  @override
  State<AdminMonitoringScreen> createState() => _AdminMonitoringScreenState();
}

class _AdminMonitoringScreenState extends State<AdminMonitoringScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Timer? _timer;
  PerfStats? _stats;
  Object? _error;
  DateTime? _updatedAt;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_tabChanged);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_tabs.index != 2 && ModalRoute.of(context)?.isCurrent != false) {
        _load();
      }
    });
  }

  void _tabChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_fetching) return;
    setState(() => _fetching = true);
    try {
      final stats = await AdminService.instance.perfStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _error = null;
        _updatedAt = DateTime.now();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Widget _perfBody({required bool sql}) {
    final stats = _stats;
    if (stats == null) {
      if (_error != null) return AdminErrorView(error: _error!, onRetry: _load);
      return const Center(child: PawLoader(color: adminOrange));
    }
    return RefreshIndicator(
      color: adminOrange,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            CacheBanner(
                color: AppColors.warning,
                text: 'รีเฟรชไม่สำเร็จ: ${adminErrorMessage(_error!)}'),
          if (sql)
            SqlMonitoringPanel(stats: stats)
          else
            ApiMonitoringPanel(stats: stats),
          const SizedBox(height: 16),
          Text(
              'อัปเดต ${DateFormat('HH:mm:ss').format(_updatedAt!)} · รีเฟรชอัตโนมัติทุก 15 วินาที',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Monitoring',
              style:
                  TextStyle(fontWeight: FontWeight.w600, color: adminOrange)),
          backgroundColor: Colors.white,
          centerTitle: true,
          iconTheme: const IconThemeData(color: adminOrange),
          actions: [
            if (_tabs.index != 2)
              IconButton(
                key: const ValueKey('monitoring-refresh'),
                onPressed: _fetching ? null : _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'รีเฟรชสถิติ',
              ),
          ],
          bottom: TabBar(
            controller: _tabs,
            labelColor: adminOrange,
            indicatorColor: adminOrange,
            tabs: const [
              Tab(text: 'API'),
              Tab(text: 'SQL'),
              Tab(text: 'Cache')
            ],
          ),
        ),
        body: AppPageFrame(
            maxWidth: AppLayout.dashboardWidth,
            child: TabBarView(controller: _tabs, children: [
              _perfBody(sql: false),
              _perfBody(sql: true),
              const AdminCacheStatsScreen(embedded: true),
            ])),
      );
}
