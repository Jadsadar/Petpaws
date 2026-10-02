import 'video_probe.dart';

/// มือถือใช้ video_compress อ่านข้อมูลแทน (ดู ChatMediaService.pickVideo)
Future<VideoProbe> probeVideo(String url, {required int thumbnailSize}) =>
    throw UnsupportedError('probeVideo ใช้ได้เฉพาะบน web');
