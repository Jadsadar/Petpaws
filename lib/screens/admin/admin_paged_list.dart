import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import 'admin_widgets.dart';

/// แถบเลื่อนหน้าใต้รายการ: « ‹ หน้า 2 / 5 · ทั้งหมด 93 รายการ › »
class AdminPager extends StatelessWidget {
  const AdminPager({super.key, required this.page, required this.onPageChanged});

  final AdminPage<Object?> page;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final totalPages = page.totalPages;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('pager-first'),
            tooltip: 'หน้าแรก',
            onPressed: page.hasPrevious ? () => onPageChanged(1) : null,
            icon: const Icon(Icons.first_page),
          ),
          IconButton(
            key: const ValueKey('pager-prev'),
            tooltip: 'หน้าก่อนหน้า',
            onPressed: page.hasPrevious ? () => onPageChanged(page.page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              'หน้า ${page.page} / $totalPages · ทั้งหมด ${page.total} รายการ',
              key: const ValueKey('pager-label'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
          IconButton(
            key: const ValueKey('pager-next'),
            tooltip: 'หน้าถัดไป',
            onPressed: page.hasNext ? () => onPageChanged(page.page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            key: const ValueKey('pager-last'),
            tooltip: 'หน้าสุดท้าย',
            onPressed: page.hasNext ? () => onPageChanged(totalPages) : null,
            icon: const Icon(Icons.last_page),
          ),
        ],
      ),
    );
  }
}

/// รายการที่โหลดทีละหน้าจาก API พร้อมแถบเลื่อนหน้า สถานะโหลด/ว่าง/error และดึงเพื่อรีเฟรช
/// ใช้ร่วมกันทั้งแท็บรีพอร์ต แท็บถูกแบน และรายการรีพอร์ตของผู้ใช้หนึ่งคน
class AdminPagedList<T> extends StatefulWidget {
  const AdminPagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    required this.emptyMessage,
    this.padding = const EdgeInsets.all(16),
  });

  final Future<AdminPage<T>> Function(int page) fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyMessage;
  final EdgeInsets padding;

  @override
  State<AdminPagedList<T>> createState() => AdminPagedListState<T>();
}

class AdminPagedListState<T> extends State<AdminPagedList<T>> {
  int _page = 1;
  late Future<AdminPage<T>> _future = _load();

  Future<AdminPage<T>> _load() async {
    final res = await widget.fetch(_page);
    // หน้านี้เคยมีรายการแต่ตอนนี้ว่าง (เช่นเพิ่งแบนคนสุดท้ายของหน้าสุดท้าย) ให้ถอยไปหน้าก่อนหน้าเอง
    // ไม่งั้นแอดมินจะเห็น "ไม่มีรายการ" ทั้งที่หน้าก่อนหน้ายังมีอยู่
    if (res.items.isEmpty && _page > 1) {
      _page -= 1;
      return _load();
    }
    return res;
  }

  /// โหลดใหม่ ([page] ไม่ระบุ = อยู่หน้าเดิม) — เรียกจากภายนอกผ่าน GlobalKey ตอนเปลี่ยนตัวกรอง
  void reload({int? page}) => setState(() {
        if (page != null) _page = page;
        _future = _load();
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminPage<T>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return AdminErrorView(error: snap.error!, onRetry: reload);
        final page = snap.data!;
        if (page.items.isEmpty) return AdminEmptyView(message: widget.emptyMessage);
        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  reload();
                  try {
                    await _future;
                  } catch (_) {}
                },
                child: ListView.separated(
                  padding: widget.padding,
                  itemCount: page.items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => widget.itemBuilder(context, page.items[i]),
                ),
              ),
            ),
            AdminPager(page: page, onPageChanged: (p) => reload(page: p)),
          ],
        );
      },
    );
  }
}
