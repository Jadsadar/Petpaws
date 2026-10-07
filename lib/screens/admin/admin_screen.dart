import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/pet_avatar.dart';
import 'admin_monitoring_screen.dart';
import 'admin_paged_list.dart';
import 'admin_user_reports_screen.dart';
import 'admin_widgets.dart';
import '../../theme/app_theme.dart';

/// แดชบอร์ดของแอดมิน — แอดมินเห็นแค่หน้านี้ ไม่มีหน้าปัดการ์ด/ลงประกาศ/แชทของผู้ใช้ทั่วไป
/// ทำได้อย่างเดียวคือ: ดูสิ่งที่ถูกรายงาน → แบนถาวร / แบนชั่วคราว / ปัดตก → ปลดแบน
/// เข้าได้เฉพาะ users.is_admin = true (server เช็คซ้ำทุก request อยู่แล้ว)
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  late Future<AdminSummary> _summary = AdminService.instance.summary();

  /// เรียกจากแท็บทุกครั้งที่มีการตัดสิน (แบน/ปัดตก/ปลดแบน) ให้ตัวเลขด้านบนตรงกับรายการเสมอ
  void _refreshSummary() => setState(() {
        _summary = AdminService.instance.summary();
      });

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ออกจากระบบ'),
        content: const Text('ต้องการออกจากระบบแอดมินใช่หรือไม่?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ออกจากระบบ',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    AdminService.instance.clearCache();
    await AuthService.instance.signOut();
    // AuthGate สลับไปหน้าล็อกอินเอง แต่ถ้าหน้านี้ถูก push มาซ้อนอยู่ ต้องปิดทิ้งด้วย
    if (mounted && Navigator.canPop(context)) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('แดชบอร์ดแอดมิน',
              style:
                  TextStyle(fontWeight: FontWeight.w600, color: adminOrange)),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: adminOrange),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const AdminMonitoringScreen()),
              ),
              key: const ValueKey('admin-monitoring'),
              icon:
                  const Icon(Icons.monitor_heart_outlined, color: adminOrange),
              tooltip: 'Monitoring',
            ),
            IconButton(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: adminOrange),
              tooltip: 'ออกจากระบบ',
            ),
          ],
          bottom: const TabBar(
            labelColor: adminOrange,
            indicatorColor: adminOrange,
            tabs: [Tab(text: 'รีพอร์ต'), Tab(text: 'ถูกแบน')],
          ),
        ),
        body: AppPageFrame(
            maxWidth: AppLayout.dashboardWidth,
            child: Column(
              children: [
                _SummaryBar(summary: _summary),
                Expanded(
                  child: TabBarView(
                    children: [
                      _ReportedTab(onChanged: _refreshSummary),
                      _BannedTab(onChanged: _refreshSummary),
                    ],
                  ),
                ),
              ],
            )),
      ),
    );
  }
}

/// แถบตัวเลขสรุปบนสุด: ผู้ถูกรายงานที่รอตรวจ / ถูกแบนชั่วคราว / ถูกแบนถาวร
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.summary});

  final Future<AdminSummary> summary;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminSummary>(
      future: summary,
      builder: (context, snap) {
        final s = snap.data;
        String v(int? n) => n == null ? '-' : '$n';
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _StatCard(
                  key: const ValueKey('stat-reported'),
                  label: 'ผู้ถูกรายงาน',
                  value: v(s?.reported),
                  color: AppColors.danger),
              const SizedBox(width: 8),
              _StatCard(
                  key: const ValueKey('stat-temporary'),
                  label: 'แบนชั่วคราว',
                  value: v(s?.temporary),
                  color: adminOrange),
              const SizedBox(width: 8),
              _StatCard(
                  key: const ValueKey('stat-permanent'),
                  label: 'แบนถาวร',
                  value: v(s?.permanent),
                  color: Colors.grey.shade700),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard(
      {super.key,
      required this.label,
      required this.value,
      required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600, color: color)),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class _ReportedTab extends StatefulWidget {
  const _ReportedTab({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_ReportedTab> createState() => _ReportedTabState();
}

class _ReportedTabState extends State<_ReportedTab> {
  /// เกณฑ์ขั้นต่ำของ "จำนวนคนที่รายงาน" — backend ตั้ง default ไว้ที่ 10 แต่ช่วงแรกคนยังน้อย
  /// เลยให้แอดมินเลือกดูตั้งแต่ 1 คนได้
  static const List<int> _thresholds = [1, 3, 5, 10];

  final GlobalKey<AdminPagedListState<ReportedUser>> _listKey = GlobalKey();
  int _minReports = 1;

  Future<void> _open(ReportedUser user) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AdminUserReportsScreen(user: user)),
    );
    if (changed == true && mounted) {
      _listKey.currentState?.reload();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('แสดงผู้ที่ถูกรายงานตั้งแต่',
                  style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in _thresholds)
                    ChoiceChip(
                      label: Text(t == 1 ? 'ทั้งหมด' : '$t คน'),
                      showCheckmark: false,
                      selected: _minReports == t,
                      selectedColor: adminOrange.withValues(alpha: 0.35),
                      onSelected: (_) {
                        setState(() => _minReports = t);
                        // เปลี่ยนเกณฑ์ = ชุดรายการเปลี่ยน ต้องกลับไปเริ่มที่หน้า 1 เสมอ
                        _listKey.currentState?.reload(page: 1);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: AdminPagedList<ReportedUser>(
            key: _listKey,
            fetch: (page) => AdminService.instance
                .reportedUsers(minReports: _minReports, page: page),
            emptyMessage: 'ไม่มีรีพอร์ตที่รอตรวจสอบตามเกณฑ์นี้',
            itemBuilder: (context, user) =>
                _ReportedUserTile(user: user, onTap: () => _open(user)),
          ),
        ),
      ],
    );
  }
}

class _ReportedUserTile extends StatelessWidget {
  const _ReportedUserTile({required this.user, required this.onTap});

  final ReportedUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: ListTile(
        onTap: onTap,
        leading:
            PetAvatar(imageUrl: user.avatarUrl, radius: 24, icon: Icons.person),
        title: Text(user.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
            '@${user.username} · ${user.email}\nล่าสุด ${formatDateTime(user.lastReportedAt)}'),
        isThreeLine: true,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Text('${user.reportCount} คน',
              style: const TextStyle(
                  color: AppColors.danger, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _BannedTab extends StatefulWidget {
  const _BannedTab({required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<_BannedTab> createState() => _BannedTabState();
}

class _BannedTabState extends State<_BannedTab> {
  final GlobalKey<AdminPagedListState<BannedUser>> _listKey = GlobalKey();

  Future<void> _unban(BannedUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ปลดแบน'),
        content: Text(
            'ต้องการปลดแบน "${user.title}" ใช่หรือไม่?\nเขาจะล็อกอินกลับเข้าแอปได้ทันที'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ปลดแบน')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AdminService.instance.unban(user.id);
      if (!mounted) return;
      showAdminSnack(context, 'ปลดแบน "${user.title}" แล้ว');
      _listKey.currentState?.reload();
      widget.onChanged();
    } catch (e) {
      if (mounted) showAdminSnack(context, adminErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminPagedList<BannedUser>(
      key: _listKey,
      fetch: (page) => AdminService.instance.bannedUsers(page: page),
      emptyMessage: 'ยังไม่มีบัญชีที่ถูกแบน',
      itemBuilder: (context, u) => Card(
        elevation: 0,
        child: ListTile(
          leading:
              PetAvatar(imageUrl: u.avatarUrl, radius: 24, icon: Icons.person),
          title: Text(u.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              '@${u.username} · ${u.email}\n${u.permanent ? 'แบนถาวร' : 'ถึง ${formatDate(u.suspendedUntil)}'}'),
          isThreeLine: true,
          trailing: TextButton(
              onPressed: () => _unban(u), child: const Text('ปลดแบน')),
        ),
      ),
    );
  }
}
