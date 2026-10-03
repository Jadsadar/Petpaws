import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../widgets/pet_network_image.dart';

/// เปิดรูปเต็มจอ (เลื่อนดูใบอื่นได้ ซูมได้) เริ่มที่รูปลำดับ [index]
void openAdminPhotoViewer(BuildContext context, List<String> urls, {int index = 0, String? title}) {
  if (urls.isEmpty) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => AdminPhotoViewer(urls: urls, initialIndex: index, title: title)),
  );
}

/// แถบภาพย่อเลื่อนแนวนอน กดรูปแล้วเปิดตัวดูรูปเต็มจอ — ใช้แสดงรูปของประกาศที่ถูกรายงาน
class AdminPhotoStrip extends StatelessWidget {
  const AdminPhotoStrip({super.key, required this.photos, this.size = 88, this.title});

  final List<PetPhoto> photos;
  final double size;
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return Text('ประกาศนี้ไม่มีรูป', style: TextStyle(color: Colors.grey.shade600, fontSize: 12));
    }
    final fullUrls = photos.map((p) => p.url).toList();
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          key: ValueKey('photo-$i'),
          onTap: () => openAdminPhotoViewer(context, fullUrls, index: i, title: title),
          child: PetNetworkImage(
            imageUrl: photos[i].previewUrl,
            width: size,
            height: size,
            borderRadius: BorderRadius.circular(10),
            iconSize: 28,
          ),
        ),
      ),
    );
  }
}

class AdminPhotoViewer extends StatefulWidget {
  const AdminPhotoViewer({super.key, required this.urls, this.initialIndex = 0, this.title});

  final List<String> urls;
  final int initialIndex;
  final String? title;

  @override
  State<AdminPhotoViewer> createState() => _AdminPhotoViewerState();
}

class _AdminPhotoViewerState extends State<AdminPhotoViewer> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(
          '${widget.title == null ? '' : '${widget.title} · '}${_index + 1} / ${widget.urls.length}',
          key: const ValueKey('viewer-counter'),
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: PetNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.contain,
              backgroundColor: Colors.black,
              iconColor: Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}
