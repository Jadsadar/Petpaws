import 'dart:typed_data';

import 'video_probe_stub.dart' if (dart.library.js_interop) 'video_probe_web.dart' as impl;

/// ข้อมูลวิดีโอที่อ่านจากตัวเล่นของ browser (ใช้บน web ซึ่งไม่มี plugin native)
class VideoProbe {
  VideoProbe({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.thumbnailJpeg,
  });

  final int durationMs;

  /// ขนาดตอนแสดงผลจริง (browser หมุนตาม metadata ให้แล้ว)
  final int width;
  final int height;

  /// เฟรมต้นคลิป ย่อด้านยาวไม่เกิน thumbnailSize แล้ว
  final Uint8List thumbnailJpeg;
}

/// โหลดวิดีโอจาก [url] (บน web = blob URL ที่ image_picker ให้มา) เข้า `<video>`
/// อ่านความยาว/ขนาด แล้ววาดเฟรมแรกลง canvas เป็น thumbnail
Future<VideoProbe> probeVideo(String url, {required int thumbnailSize}) =>
    impl.probeVideo(url, thumbnailSize: thumbnailSize);
