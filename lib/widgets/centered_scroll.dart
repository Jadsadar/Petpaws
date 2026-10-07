import 'package:flutter/material.dart';

/// จัดเนื้อหากลางจอเหมือน Center แต่เลื่อนได้เมื่อพื้นที่เตี้ยกว่าเนื้อหา
/// (มือถือแนวนอน, คีย์บอร์ดขึ้น, ตัวอักษรใหญ่) ใช้กับหน้า "ว่าง" / "โหลดไม่สำเร็จ" ที่เป็นไอคอน+ข้อความ+ปุ่ม
/// ซึ่งถ้าใช้ Center + Column ตรงๆ จะล้นจอและขึ้นแถบเหลืองดำ
class CenteredScroll extends StatelessWidget {
  const CenteredScroll({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight.isFinite ? box.maxHeight : 0),
          child: Center(child: child),
        ),
      ),
    );
  }
}
