import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../screens/chat/media_viewer_screen.dart';
import '../theme/app_theme.dart';
import 'paw_loader.dart';

/// กรอบรูป/วิดีโอใน bubble แชท — โหลดแค่ thumbnail (~30KB) ตัวจริงโหลดตอนกดเปิด
///
/// จองพื้นที่ตามสัดส่วนจริง (width/height จาก server) ตั้งแต่ก่อนรูปโหลดเสร็จ
/// รายการข้อความจึงไม่กระโดดตอนรูปทยอยขึ้น
class ChatMediaBubble extends StatelessWidget {
  const ChatMediaBubble({
    super.key,
    required this.type,
    required this.width,
    required this.height,
    this.thumbnailUrl,
    this.url,
    this.localThumbnail,
    this.durationMs,
    this.progress,
    this.failed = false,
  });

  /// สร้างจาก field `media` ของข้อความที่ได้จาก API / socket
  factory ChatMediaBubble.fromMessage(Map<String, dynamic> media) => ChatMediaBubble(
        type: media['type'] as String,
        url: media['url'] as String?,
        thumbnailUrl: media['thumbnailUrl'] as String?,
        width: (media['width'] as num).toInt(),
        height: (media['height'] as num).toInt(),
        durationMs: (media['durationMs'] as num?)?.toInt(),
      );

  final String type;
  final int width;
  final int height;
  final String? thumbnailUrl;
  final String? url;
  final int? durationMs;

  /// ระหว่างกำลังอัป: thumbnail ในเครื่อง + ความคืบหน้า 0.0–1.0 (null = ส่งเสร็จแล้ว)
  final Uint8List? localThumbnail;
  final double? progress;
  final bool failed;

  static const double maxWidth = 240;
  static const double maxHeight = 320;

  bool get _isVideo => type == 'video';

  Size _displaySize() {
    // กันรูปยาว/กว้างสุดโต่ง (พาโนรามา, screenshot ยาว) ทำ bubble เพี้ยน — crop ด้วย BoxFit.cover
    final ratio = (width / height).clamp(0.6, 1.8);
    var w = maxWidth;
    var h = w / ratio;
    if (h > maxHeight) {
      h = maxHeight;
      w = h * ratio;
    }
    return Size(w, h);
  }

  @override
  Widget build(BuildContext context) {
    final size = _displaySize();
    final uploading = progress != null;

    final Widget image = localThumbnail != null
        ? Image.memory(localThumbnail!, fit: BoxFit.cover, gaplessPlayback: true)
        : CachedNetworkImage(
            imageUrl: thumbnailUrl ?? '',
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (_, __) => Container(color: Colors.black12),
            errorWidget: (_, __, ___) => Container(
              color: Colors.black12,
              child: const Icon(Icons.broken_image_outlined, color: Colors.black38),
            ),
          );

    return GestureDetector(
      onTap: uploading || url == null ? null : () => _open(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(tag: url ?? hashCode, child: image),
              if (_isVideo && !uploading)
                const Center(
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.black45,
                    child: Icon(Icons.play_arrow, color: Colors.white, size: 32),
                  ),
                ),
              if (_isVideo && durationMs != null && !uploading)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _Badge(text: formatDuration(Duration(milliseconds: durationMs!))),
                ),
              if (uploading)
                Container(
                  color: Colors.black38,
                  alignment: Alignment.center,
                  child: failed
                      ? const Icon(Icons.error_outline, color: Colors.white, size: 36)
                      // วงแหวนบอก % อัปโหลด + อุ้งเท้าหมุนตรงกลาง
                      : SizedBox(
                          width: 44,
                          height: 44,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (progress! > 0)
                                CircularProgressIndicator(
                                  value: progress,
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              const PawSpinner(size: 22, color: Colors.white),
                            ],
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _isVideo
          ? VideoViewerScreen(url: url!, thumbnailUrl: thumbnailUrl)
          : ImageViewerScreen(url: url!, thumbnailUrl: thumbnailUrl),
    ));
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
      );
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
