import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../utils/report_reasons.dart';
import '../../widgets/pet_avatar.dart';
import 'admin_paged_list.dart';
import 'admin_photos.dart';
import 'admin_user_profile_screen.dart';
import 'admin_widgets.dart';
import '../../theme/app_theme.dart';

/// รายละเอียดรีพอร์ตของผู้ใช้หนึ่งคน + ปุ่มตัดสิน (แบน / ปัดตก)
/// ปิดหน้านี้พร้อมค่า true เมื่อมีการตัดสินแล้ว เพื่อให้หน้ารายการโหลดใหม่
class AdminUserReportsScreen extends StatefulWidget {
  const AdminUserReportsScreen({super.key, required this.user});

  final ReportedUser user;

  @override
  State<AdminUserReportsScreen> createState() => _AdminUserReportsScreenState();
}

class _AdminUserReportsScreenState extends State<AdminUserReportsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String doneMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showAdminSnack(context, doneMessage);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAdminSnack(context, adminErrorMessage(e));
    }
  }

  Future<void> _dismiss() async {
    final ok = await _confirm(
      title: 'ปัดตกรีพอร์ต',
      message:
          'ตรวจแล้วไม่พบความผิด ต้องการปิดรีพอร์ตทั้งหมดของ "${widget.user.title}" โดยไม่แบนใช่หรือไม่?',
      confirmLabel: 'ปัดตก',
    );
    if (ok) {
      await _run(() => AdminService.instance.dismissReports(widget.user.id),
          'ปัดตกรีพอร์ตแล้ว');
    }
  }

  Future<void> _ban({required bool permanent}) async {
    final result = await showDialog<_BanChoice>(
      context: context,
      builder: (_) =>
          _BanDialog(userTitle: widget.user.title, permanent: permanent),
    );
    if (result == null) return;
    await _run(
      () => AdminService.instance
          .ban(widget.user.id, days: result.days, note: result.note),
      'แบน "${widget.user.title}" แล้ว',
    );
  }

  Future<bool> _confirm(
      {required String title,
      required String message,
      required String confirmLabel}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel)),
        ],
      ),
    );
    return ok == true;
  }

  void _openProfile() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdminUserProfileScreen(
              userId: widget.user.id, fallbackTitle: widget.user.title),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(user.title,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: adminOrange)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: adminOrange),
      ),
      body: AppPageFrame(
          maxWidth: AppLayout.dashboardWidth,
          child: LayoutBuilder(
              builder: (context, box) => Column(
                    children: [
                      ConstrainedBox(
                        constraints:
                            BoxConstraints(maxHeight: box.maxHeight * 0.4),
                        child: SingleChildScrollView(
                          child: ListTile(
                            key: const ValueKey('open-profile'),
                            onTap: _openProfile,
                            leading: PetAvatar(
                                imageUrl: user.avatarUrl,
                                radius: 28,
                                icon: Icons.person),
                            title: Text(user.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '@${user.username} · ${user.email}\nถูกรายงาน ${user.reportCount} คน'),
                            isThreeLine: true,
                            trailing: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('ดูโปรไฟล์',
                                    style: TextStyle(color: adminOrange)),
                                Icon(Icons.chevron_right, color: adminOrange),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: AdminPagedList<UserReport>(
                          fetch: (page) => AdminService.instance
                              .userReports(user.id, page: page),
                          emptyMessage:
                              'ไม่มีรีพอร์ตค้างแล้ว (อาจถูกตัดสินไปก่อนหน้านี้)',
                          itemBuilder: (context, report) =>
                              _ReportCard(report: report),
                        ),
                      ),
                    ],
                  ))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 12)),
                  onPressed: _busy ? null : _dismiss,
                  child: const FittedBox(
                      fit: BoxFit.scaleDown, child: Text('ปัดตก')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _ban(permanent: false),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: adminOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 12)),
                  child: const FittedBox(
                      fit: BoxFit.scaleDown, child: Text('แบนชั่วคราว')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _ban(permanent: true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 12)),
                  child: const FittedBox(
                      fit: BoxFit.scaleDown, child: Text('แบนถาวร')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final UserReport report;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  label: Text(reportReasonLabel(report.reason)),
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.12),
                  labelStyle: const TextStyle(
                      color: AppColors.danger, fontWeight: FontWeight.w600),
                ),
                Text(formatDateTime(report.createdAt),
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
            _target(context),
            if (report.detail.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('รายละเอียด: ${report.detail}'),
            ],
            const SizedBox(height: 6),
            Text('โดย ${report.reporterName}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  /// ส่วน "สิ่งที่ถูกรายงาน" — ประกาศแสดงรูปให้ตรวจ ข้อความแสดงเฉพาะข้อความนั้นข้อความเดียว
  Widget _target(BuildContext context) {
    switch (report.targetType) {
      case 'pet':
        final pet = report.pet;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ประกาศสัตว์: ${pet?.name ?? report.petName ?? '-'}'
                '${pet == null ? '' : ' (${pet.statusLabel})'}'),
            if (pet != null && pet.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(pet.description,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            ],
            const SizedBox(height: 8),
            AdminPhotoStrip(photos: pet?.photos ?? const [], title: pet?.name),
          ],
        );
      case 'message':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ข้อความที่ถูกรายงาน'
                '${report.messageCreatedAt == null ? '' : ' (ส่งเมื่อ ${formatDateTime(report.messageCreatedAt)})'}'),
            const SizedBox(height: 6),
            Container(
              key: const ValueKey('reported-message'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: const Border(
                    left: BorderSide(color: AppColors.danger, width: 4)),
              ),
              child: Text(report.messageBody ?? '(ข้อความนี้ถูกลบแล้ว)'),
            ),
          ],
        );
      default:
        return const Text('เรื่องที่ถูกรายงาน: ตัวผู้ใช้');
    }
  }
}

class _BanChoice {
  const _BanChoice({this.days, this.note});

  final int? days;
  final String? note;
}

class _BanDialog extends StatefulWidget {
  const _BanDialog({required this.userTitle, required this.permanent});

  final String userTitle;
  final bool permanent;

  @override
  State<_BanDialog> createState() => _BanDialogState();
}

class _BanDialogState extends State<_BanDialog> {
  static const List<int> _durations = [1, 7, 30, 90];

  int _days = 7;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.permanent ? 'แบนถาวร' : 'แบนชั่วคราว'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '"${widget.userTitle}" จะถูกเตะออกจากทุกเครื่องและล็อกอินกลับเข้าแอปไม่ได้'
                '${widget.permanent ? ' จนกว่าแอดมินจะปลดแบน' : ''}'),
            if (!widget.permanent) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (final d in _durations)
                      ButtonSegment<int>(value: d, label: Text('$d วัน')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (v) => setState(() => _days = v.first),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration:
                  const InputDecoration(labelText: 'บันทึกเหตุผล (ไม่บังคับ)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก')),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _BanChoice(days: widget.permanent ? null : _days, note: _note.text),
          ),
          child:
              Text('ยืนยันแบน', style: TextStyle(color: Colors.red.shade700)),
        ),
      ],
    );
  }
}
