import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'video_probe.dart';

Future<VideoProbe> probeVideo(String url, {required int thumbnailSize}) async {
  // ไม่ต้องใส่ลง DOM — โหลด/seek/วาดลง canvas ได้เลย
  // muted + playsInline กัน browser มือถือบล็อกการโหลดหรือเปิดเต็มจอเอง
  final video = web.HTMLVideoElement()
    ..muted = true
    ..playsInline = true
    ..preload = 'auto'
    ..src = url;

  try {
    await _next(video, 'loadedmetadata');

    final seconds = video.duration;
    final width = video.videoWidth;
    final height = video.videoHeight;
    // บางไฟล์ (เช่น webm ที่อัดจาก browser) ได้ duration = Infinity — ส่งไม่ได้
    // เพราะ backend บังคับความยาว และ bubble ต้องโชว์เวลา
    if (!seconds.isFinite || seconds <= 0 || width == 0 || height == 0) {
      throw const FormatException('unreadable video');
    }

    // เฟรมที่ 0 พอดีมักเป็นจอดำ (ยังไม่ decode / fade-in) ขยับไปนิดหนึ่ง
    video.currentTime = math.min(0.1, seconds / 2);
    await _next(video, 'seeked');

    final scale = math.min(1.0, thumbnailSize / math.max(width, height));
    final canvas = web.HTMLCanvasElement()
      ..width = math.max(1, (width * scale).round())
      ..height = math.max(1, (height * scale).round());
    (canvas.getContext('2d') as web.CanvasRenderingContext2D)
        .drawImage(video, 0, 0, canvas.width, canvas.height);

    final blob = await _toJpeg(canvas);
    final bytes = (await blob.arrayBuffer().toDart).toDart.asUint8List();

    return VideoProbe(
      durationMs: (seconds * 1000).round(),
      width: width,
      height: height,
      thumbnailJpeg: bytes,
    );
  } finally {
    // ปล่อย decoder ทันที ไม่ต้องรอ GC
    video.removeAttribute('src');
    video.load();
  }
}

/// รอ event [type] ครั้งถัดไป — ไฟล์ที่ browser เล่นไม่ได้จะได้ 'error' แทน
Future<void> _next(web.HTMLVideoElement video, String type) {
  final done = Completer<void>();
  late final JSFunction onOk;
  late final JSFunction onError;
  void cleanup() {
    video.removeEventListener(type, onOk);
    video.removeEventListener('error', onError);
  }

  onOk = ((web.Event _) {
    cleanup();
    if (!done.isCompleted) done.complete();
  }).toJS;
  onError = ((web.Event _) {
    cleanup();
    if (!done.isCompleted) done.completeError(const FormatException('video error'));
  }).toJS;
  video.addEventListener(type, onOk);
  video.addEventListener('error', onError);

  return done.future.timeout(const Duration(seconds: 20), onTimeout: () {
    cleanup();
    throw TimeoutException('video $type');
  });
}

Future<web.Blob> _toJpeg(web.HTMLCanvasElement canvas) {
  final done = Completer<web.Blob>();
  canvas.toBlob(
    ((web.Blob? blob) {
      if (blob == null) {
        done.completeError(const FormatException('canvas toBlob'));
      } else {
        done.complete(blob);
      }
    }).toJS,
    'image/jpeg',
    0.7.toJS,
  );
  return done.future;
}
