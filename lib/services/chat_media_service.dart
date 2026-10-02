import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

import '../shared/api_client.dart';
import '../shared/api_exception.dart';
import 'video_probe.dart';

/// สื่อที่เตรียมเสร็จแล้ว (ย่อ/บีบอัด + thumbnail) พร้อมอัปโหลด
class PreparedMedia {
  PreparedMedia({
    required this.type,
    required this.bytes,
    required this.contentType,
    required this.thumbnail,
    required this.width,
    required this.height,
    this.durationMs,
  });

  /// 'image' | 'video'
  final String type;
  final Uint8List bytes;
  final String contentType;

  /// JPEG ด้านยาวไม่เกิน [ChatMediaService.thumbnailSize] — ใช้โชว์ใน bubble ระหว่างอัปด้วย
  final Uint8List thumbnail;

  /// ขนาดตอนแสดงผลจริง (หมุนตาม EXIF แล้ว) ให้ bubble จองพื้นที่ได้ถูกสัดส่วน
  final int width;
  final int height;
  final int? durationMs;

  bool get isVideo => type == 'video';
}

/// รูป/วิดีโอในแชท — ฝั่งแอปทำงานหนักเองทั้งหมด (ย่อรูป, ทำ thumbnail, บีบวิดีโอ)
/// แล้วอัปตรงไป S3 ด้วย presigned POST ที่ backend ออกให้ server ไม่ต้องแตะไฟล์เลย
///
///   pick -> prepare -> upload (ได้ key) -> ChatService.sendMessage(media: ...)
class ChatMediaService {
  ChatMediaService._();
  static final ChatMediaService instance = ChatMediaService._();

  final ApiClient _api = ApiClient.instance;
  final ImagePicker _picker = ImagePicker();

  /// ด้านยาวสุดของรูปที่ส่ง — คมพอสำหรับดูเต็มจอมือถือ ไฟล์ราว 200–500KB
  static const int maxImageSide = 1600;
  static const int thumbnailSize = 400;

  /// ต้องตรงกับเพดานฝั่ง backend (chat-media.service.ts) — เช็คก่อนอัปจะได้ไม่เสียเน็ตเปล่า
  static const int maxVideoBytes = 50 * 1024 * 1024;
  static const Duration maxVideoDuration = Duration(minutes: 3);

  /// มือถือบีบอัดวิดีโอด้วย plugin native ก่อนส่ง ส่วน web บีบอัดไม่ได้ จึงส่งไฟล์เดิม
  /// ได้เฉพาะ .mp4 (เล่นได้ทุกแพลตฟอร์ม) และต้องไม่เกิน [maxVideoBytes] อยู่แล้ว
  static bool get canSendVideo => true;

  /// ถ่ายวิดีโอใช้กล้องผ่าน plugin native — บน web เลือกจากไฟล์ได้อย่างเดียว
  static bool get canRecordVideo => !kIsWeb;

  /// คำอธิบายข้อจำกัดใต้ปุ่มเลือกวิดีโอ
  static String get videoLimitHint => kIsWeb
      ? 'ไฟล์ .mp4 ไม่เกิน ${maxVideoBytes ~/ (1024 * 1024)}MB ยาวไม่เกิน ${maxVideoDuration.inMinutes} นาที'
      : 'ยาวไม่เกิน ${maxVideoDuration.inMinutes} นาที';

  Future<PreparedMedia?> pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: maxImageSide.toDouble(),
      maxHeight: maxImageSide.toDouble(),
      imageQuality: 80,
    );
    if (file == null) return null;
    return compute(prepareChatImage, await file.readAsBytes());
  }

  Future<PreparedMedia?> pickVideo(ImageSource source) async {
    final file = await _picker.pickVideo(source: source, maxDuration: maxVideoDuration);
    if (file == null) return null;
    if (kIsWeb) return _prepareWebVideo(file);

    final info = await VideoCompress.getMediaInfo(file.path);
    final durationMs = info.duration?.round() ?? 0;
    if (durationMs <= 0) {
      throw ApiException(0, 'INVALID_VIDEO', 'อ่านไฟล์วิดีโอนี้ไม่ได้');
    }
    if (durationMs > maxVideoDuration.inMilliseconds) {
      throw ApiException(0, 'VIDEO_TOO_LONG', 'วิดีโอต้องยาวไม่เกิน ${maxVideoDuration.inMinutes} นาที');
    }

    final Uint8List bytes;
    final Uint8List? frame;
    try {
      // วิดีโอจากกล้องมือถือ 1 นาที ~100MB+ บีบเหลือ 720p ได้ราว 5–15MB
      final compressed = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.Res1280x720Quality,
        includeAudio: true,
      );
      final path = compressed?.path;
      if (path == null) throw ApiException(0, 'COMPRESS_FAILED', 'บีบอัดวิดีโอไม่สำเร็จ');
      bytes = await XFile(path).readAsBytes();
      // เฟรมแรกที่ได้หมุนตาม metadata แล้ว — ใช้ขนาดของเฟรมนี้เป็นสัดส่วนจริงของวิดีโอ
      // (width/height ใน MediaInfo เป็นค่าก่อนหมุน วิดีโอแนวตั้งจะได้ค่ากลับด้าน)
      frame = await VideoCompress.getByteThumbnail(path, quality: 80, position: 0);
    } finally {
      // อ่านเข้าหน่วยความจำแล้ว ไฟล์บีบอัดชั่วคราวไม่ต้องใช้อีก — ไม่ลบจะกินพื้นที่เครื่องสะสม
      await VideoCompress.deleteAllCache();
    }

    if (bytes.length > maxVideoBytes) {
      throw ApiException(0, 'VIDEO_TOO_LARGE', 'วิดีโอมีขนาดใหญ่เกินไป ลองตัดให้สั้นลง');
    }
    if (frame == null) throw ApiException(0, 'THUMBNAIL_FAILED', 'สร้างภาพตัวอย่างวิดีโอไม่สำเร็จ');
    final thumb = await compute(_makeThumbnail, frame);

    return PreparedMedia(
      type: 'video',
      bytes: bytes,
      contentType: 'video/mp4',
      thumbnail: thumb.jpeg,
      width: thumb.sourceWidth,
      height: thumb.sourceHeight,
      durationMs: durationMs,
    );
  }

  /// web: ไม่มีตัวบีบอัด ส่งไฟล์เดิม — เช็คชนิด/ขนาดก่อน (ถูกที่สุด) แล้วค่อยให้ browser
  /// โหลดอ่านความยาวและทำ thumbnail
  Future<PreparedMedia> _prepareWebVideo(XFile file) async {
    final isMp4 = file.mimeType == 'video/mp4' ||
        ((file.mimeType ?? '').isEmpty && file.name.toLowerCase().endsWith('.mp4'));
    if (!isMp4) {
      throw ApiException(0, 'UNSUPPORTED_VIDEO', 'บนเว็บส่งได้เฉพาะไฟล์ .mp4');
    }
    if (await file.length() > maxVideoBytes) {
      throw ApiException(0, 'VIDEO_TOO_LARGE',
          'วิดีโอต้องไม่เกิน ${maxVideoBytes ~/ (1024 * 1024)}MB (บนเว็บส่งไฟล์เดิมโดยไม่บีบอัด)');
    }

    final VideoProbe probe;
    try {
      probe = await probeVideo(file.path, thumbnailSize: thumbnailSize);
    } catch (_) {
      throw ApiException(0, 'INVALID_VIDEO', 'อ่านไฟล์วิดีโอนี้ไม่ได้');
    }
    if (probe.durationMs > maxVideoDuration.inMilliseconds) {
      throw ApiException(0, 'VIDEO_TOO_LONG', 'วิดีโอต้องยาวไม่เกิน ${maxVideoDuration.inMinutes} นาที');
    }

    return PreparedMedia(
      type: 'video',
      bytes: await file.readAsBytes(),
      contentType: 'video/mp4',
      thumbnail: probe.thumbnailJpeg,
      width: probe.width,
      height: probe.height,
      durationMs: probe.durationMs,
    );
  }

  /// อัปตัวจริง + thumbnail แล้วคืนค่า media สำหรับแนบไปกับข้อความ
  Future<Map<String, dynamic>> upload(
    PreparedMedia media, {
    void Function(double progress)? onProgress,
  }) async {
    final grant = await _api.post('/chats/media-uploads', body: {
      'type': media.type,
      'contentType': media.contentType,
    }) as Map<String, dynamic>;

    final mainUpload = grant['upload'] as Map<String, dynamic>;
    final thumbUpload = grant['thumbnailUpload'] as Map<String, dynamic>;

    // thumbnail ก่อน (เล็ก เสร็จไว) แล้วค่อยตัวจริง — ความคืบหน้าที่โชว์คือของตัวจริง
    await _api.uploadPresigned(
      url: thumbUpload['url'] as String,
      fields: Map<String, String>.from(thumbUpload['fields'] as Map),
      bytes: media.thumbnail,
      contentType: 'image/jpeg',
    );
    await _api.uploadPresigned(
      url: mainUpload['url'] as String,
      fields: Map<String, String>.from(mainUpload['fields'] as Map),
      bytes: media.bytes,
      contentType: media.contentType,
      onProgress: onProgress,
    );

    return {
      'type': media.type,
      'key': grant['key'],
      'thumbnailKey': grant['thumbnailKey'],
      'width': media.width,
      'height': media.height,
      if (media.durationMs != null) 'durationMs': media.durationMs,
    };
  }
}

// -----------------------------------------------------------------------------
// งานประมวลผลรูป — รันใน isolate ผ่าน compute() ไม่ให้ UI กระตุกตอน decode/encode
// (บน web compute รันใน thread เดิม แต่รูปถูกย่อเหลือ ≤1600px มาแล้วจึงเร็วพอ)
// -----------------------------------------------------------------------------

class _Thumbnail {
  _Thumbnail(this.jpeg, this.sourceWidth, this.sourceHeight);
  final Uint8List jpeg;
  final int sourceWidth;
  final int sourceHeight;
}

/// decode แล้วหมุนตาม EXIF ให้เรียบร้อย (ตัว decoder JPEG หมุนให้เองและลบ tag ทิ้ง
/// ส่วนรูปแบบอื่นที่มี orientation ค่อยหมุนเองที่นี่) — ขนาดที่ได้คือขนาดที่ตาเห็นจริง
img.Image _decode(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // ไฟล์เสีย/ไม่ใช่รูป บาง decoder โยน RangeError แทนที่จะคืน null
  }
  if (decoded == null) {
    throw ApiException(0, 'INVALID_IMAGE', 'อ่านไฟล์รูปนี้ไม่ได้');
  }
  final ifd = decoded.exif.imageIfd;
  return ifd.hasOrientation && ifd.orientation != 1 ? img.bakeOrientation(decoded) : decoded;
}

/// รูปจากกล้องมักเก็บพิกเซลแนวนอน + EXIF บอกให้หมุน — ต้องดูจากไฟล์ต้นฉบับ
/// เพราะหลัง decode แล้ว tag นี้หายไป
bool _hasExifRotation(Uint8List bytes, img.ImageFormat format) {
  if (format != img.ImageFormat.jpg) return false;
  try {
    return (img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1) != 1;
  } catch (_) {
    return true; // อ่าน EXIF ไม่ได้ — encode ใหม่ไว้ก่อนปลอดภัยกว่า
  }
}

Uint8List _thumbnailOf(img.Image image) {
  final landscape = image.width >= image.height;
  final small = (landscape ? image.width : image.height) <= ChatMediaService.thumbnailSize
      ? image
      : img.copyResize(
          image,
          width: landscape ? ChatMediaService.thumbnailSize : null,
          height: landscape ? null : ChatMediaService.thumbnailSize,
          interpolation: img.Interpolation.average,
        );
  return img.encodeJpg(small, quality: 70);
}

_Thumbnail _makeThumbnail(Uint8List bytes) {
  final image = _decode(bytes);
  return _Thumbnail(_thumbnailOf(image), image.width, image.height);
}

/// แยกเป็น public ไว้ให้ test เรียกตรง ๆ ได้ (ปกติเรียกผ่าน [ChatMediaService.pickImage])
@visibleForTesting
PreparedMedia prepareChatImage(Uint8List bytes) {
  final image = _decode(bytes);
  final format = img.findFormatForData(bytes);

  // image_picker ย่อให้แล้ว ถ้าเป็น JPEG/PNG/WEBP ที่ไม่ต้องหมุนก็ส่งไฟล์เดิมได้เลย
  // ไม่ต้อง encode ซ้ำให้คุณภาพตก ที่เหลือ (HEIC, GIF, รูปที่มี EXIF หมุน) แปลงเป็น JPEG
  const passthrough = {
    img.ImageFormat.jpg: 'image/jpeg',
    img.ImageFormat.png: 'image/png',
    img.ImageFormat.webp: 'image/webp',
  };
  // รูปที่พึ่ง EXIF หมุน: แต่ละที่แสดงผลไม่เหมือนกัน (บาง browser ไม่หมุน) — encode
  // ใหม่เป็นพิกเซลที่หมุนแล้วจริง ทุกที่จะเห็นตรงกัน และตรงกับ width/height ที่ส่งไป
  final keepOriginal = passthrough.containsKey(format) && !_hasExifRotation(bytes, format);

  return PreparedMedia(
    type: 'image',
    bytes: keepOriginal ? bytes : img.encodeJpg(image, quality: 85),
    contentType: keepOriginal ? passthrough[format]! : 'image/jpeg',
    thumbnail: _thumbnailOf(image),
    width: image.width,
    height: image.height,
  );
}
