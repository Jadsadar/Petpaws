import 'package:flutter/material.dart';

import '../services/report_service.dart';
import '../shared/api_exception.dart';
import '../utils/report_reasons.dart';
import '../theme/app_theme.dart';

class ReportChoice {
  const ReportChoice(this.reason, this.detail);

  final String reason;
  final String detail;
}

/// ถามเหตุผล (+ รายละเอียดไม่บังคับ ≤500 ตามที่ backend จำกัด) แล้วคืนค่าที่เลือก
/// คืน null ถ้าผู้ใช้กดยกเลิก
Future<ReportChoice?> showReportDialog(BuildContext context,
    {required String title}) {
  return showDialog<ReportChoice>(
    context: context,
    builder: (_) => _ReportDialog(title: title),
  );
}

/// ขั้นตอนครบชุด: ถามเหตุผล → [send] → แจ้งผลด้วย SnackBar
/// 409 (รายงานซ้ำ) แปลเป็นข้อความที่เข้าใจง่าย แทนที่จะโชว์ error ดิบ
///
/// ถ้าระบุ [blockUserId] เมื่อรายงานสำเร็จจะถามต่อว่าจะบล็อกเจ้าของเรื่องด้วยไหม
/// เลือกบล็อกแล้วเรียก [onBlocked] ให้หน้าจอจัดการต่อ (เช่น การ์ดในเด็คถือว่าปัดทิ้ง)
Future<void> reportWithDialog(
  BuildContext context, {
  required String title,
  required Future<void> Function(String reason, String detail) send,
  String? blockUserId,
  String blockUserName = 'ผู้ใช้นี้',
  VoidCallback? onBlocked,
}) async {
  final choice = await showReportDialog(context, title: title);
  if (choice == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await send(choice.reason, choice.detail);
    messenger.showSnackBar(const SnackBar(
        shape: AppTheme.snackSuccessShape,
        duration: AppTheme.snackDuration,
        content: Text('ส่งรายงานเรียบร้อยแล้ว ขอบคุณที่ช่วยดูแลชุมชนของเรา',
            style: AppTheme.snackSuccessText)));
    if (blockUserId != null && context.mounted) {
      await _offerBlock(
          context, messenger, blockUserId, blockUserName, onBlocked);
    }
    return;
  } catch (e) {
    final text = e is ApiException
        ? (e.statusCode == 409 ? 'คุณรายงานเรื่องนี้ไปแล้ว' : e.message)
        : 'ส่งรายงานไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
    messenger.showSnackBar(
        SnackBar(duration: AppTheme.snackDuration, content: Text(text)));
  }
}

Future<void> _offerBlock(
  BuildContext context,
  ScaffoldMessengerState messenger,
  String userId,
  String userName,
  VoidCallback? onBlocked,
) async {
  final block = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('บล็อก $userName ด้วยไหม?'),
      content: const Text(
          'คุณจะไม่เห็นประกาศของเขาอีก และแชทระหว่างกันจะถูกปิด ปลดบล็อกได้ภายหลัง'),
      actions: [
        TextButton(
            key: const ValueKey('block-no'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ไม่ต้อง')),
        TextButton(
            key: const ValueKey('block-yes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('บล็อก')),
      ],
    ),
  );
  if (block != true) return;
  try {
    await ReportService.instance.blockUser(userId);
    onBlocked?.call();
    messenger.showSnackBar(SnackBar(
        shape: AppTheme.snackSuccessShape,
        duration: AppTheme.snackDuration,
        content:
            Text('บล็อก $userName แล้ว', style: AppTheme.snackSuccessText)));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        duration: AppTheme.snackDuration,
        content: Text('บล็อกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')));
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.title});

  final String title;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  String? _reason;
  final TextEditingController _detail = TextEditingController();

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      // ความกว้างคงที่ (ไม่เกิน 420) ไม่ให้กล่องยืดตามข้อความที่พิมพ์ยาว ๆ
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v),
                child: Column(
                  children: [
                    for (final entry in reportReasonLabels.entries)
                      RadioListTile<String>(
                        key: ValueKey('reason-${entry.key}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: entry.key,
                        title: Text(entry.value),
                      ),
                  ],
                ),
              ),
              TextField(
                key: const ValueKey('report-detail'),
                controller: _detail,
                maxLength: 500,
                // พิมพ์ยาวแล้วขึ้นบรรทัดใหม่เอง (สูงสุด 5 บรรทัด เกินนั้นเลื่อนในช่อง)
                minLines: 3,
                maxLines: 5,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'รายละเอียดเพิ่มเติม (ไม่บังคับ)',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadius.control))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadius.control)),
                      borderSide: BorderSide(color: AppColors.mocha, width: 1)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadius.control)),
                      borderSide:
                          BorderSide(color: AppColors.brown, width: 1.5)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก')),
        TextButton(
          key: const ValueKey('report-submit'),
          onPressed: _reason == null
              ? null
              : () =>
                  Navigator.pop(context, ReportChoice(_reason!, _detail.text)),
          child: const Text('ส่งรายงาน'),
        ),
      ],
    );
  }
}
