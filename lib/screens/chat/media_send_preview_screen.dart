import 'package:flutter/material.dart';

import '../../services/chat_media_service.dart';
import '../../theme/app_theme.dart';

/// ดูรูป/วิดีโอที่เลือกก่อนส่งในแชท — เลื่อนดูได้, กด ✕ เอาบางชิ้นออก, กด "ส่ง" เพื่อยืนยัน
/// ปิดหน้าพร้อมรายการที่เหลือ (ยกเลิก/ย้อนกลับ = null ไม่ส่งอะไร)
class MediaSendPreviewScreen extends StatefulWidget {
  const MediaSendPreviewScreen({super.key, required this.media});

  final List<PreparedMedia> media;

  @override
  State<MediaSendPreviewScreen> createState() => _MediaSendPreviewScreenState();
}

class _MediaSendPreviewScreenState extends State<MediaSendPreviewScreen> {
  late final List<PreparedMedia> _items = [...widget.media];
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _remove(int i) {
    setState(() {
      _items.removeAt(i);
      if (_index >= _items.length) _index = (_items.length - 1).clamp(0, 999);
    });
    if (_items.isEmpty) {
      Navigator.pop(context); // เอาออกหมด = ไม่ส่ง
    } else if (_page.hasClients) {
      _page.jumpToPage(_index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _items.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(n > 1 ? 'ตรวจก่อนส่ง (${_index + 1}/$n)' : 'ตรวจก่อนส่ง',
            style: const TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          // ภาพใหญ่ เลื่อนซ้ายขวาดูทีละชิ้น ซูมได้
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: n,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => Stack(
                fit: StackFit.expand,
                children: [
                  InteractiveViewer(
                    maxScale: 5,
                    child: Image.memory(
                      _items[i].isVideo ? _items[i].thumbnail : _items[i].bytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (_items[i].isVideo)
                    const Center(
                      child: Icon(Icons.play_circle_fill, size: 72, color: Colors.white70),
                    ),
                ],
              ),
            ),
          ),
          // แถบรูปย่อ: แตะเพื่อไปดู, กด ✕ เพื่อเอาออกจากชุด
          if (n > 0)
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                itemCount: n,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _thumb(i),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('media-preview-cancel'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54)),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      key: const ValueKey('media-preview-send'),
                      onPressed: n == 0 ? null : () => Navigator.pop(context, _items),
                      icon: const Icon(Icons.send),
                      label: Text(n > 1 ? 'ส่ง ($n รายการ)' : 'ส่ง'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(int i) {
    final selected = i == _index;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () {
            setState(() => _index = i);
            _page.animateToPage(i,
                duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          },
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: selected ? AppColors.primary : Colors.white24, width: selected ? 3 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(_items[i].thumbnail, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            key: ValueKey('media-preview-remove-$i'),
            onTap: () => _remove(i),
            child: Container(
              decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
              padding: const EdgeInsets.all(3),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
