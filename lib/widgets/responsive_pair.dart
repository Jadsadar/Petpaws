import 'package:flutter/material.dart';

/// ช่องกรอก 2 ช่องที่อยู่ข้างกันบนจอปกติ แต่เรียงบน-ล่างเมื่อจอแคบ (กว้างน้อยกว่า [breakpoint])
/// กันช่องแคบจนข้อความ/ป้ายชื่อถูกตัดหรือตกบรรทัดทีละตัวอักษร
class ResponsivePair extends StatelessWidget {
  const ResponsivePair({super.key, required this.first, required this.second, this.breakpoint = 300, this.gap = 16});

  final Widget first;
  final Widget second;
  final double breakpoint;
  final double gap;

  @override
  Widget build(BuildContext context) {
    // ตัวอักษรใหญ่ (ผู้ใช้ตั้งในเครื่อง) = ช่องต้องกว้างขึ้นตามกัน 1.12 คือขนาดมาตรฐานของแอป (AppTheme.textScale)
    final grow = (MediaQuery.textScalerOf(context).scale(1) / 1.12).clamp(1.0, 2.0);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth < breakpoint * grow) {
        return Column(children: [first, SizedBox(height: gap), second]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: first),
        SizedBox(width: gap),
        Expanded(child: second),
      ]);
    });
  }
}
