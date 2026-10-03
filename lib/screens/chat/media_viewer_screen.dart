import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../widgets/chat_media_bubble.dart' show formatDuration;
import '../../theme/app_theme.dart';

/// ดูรูปเต็มจอ ซูม/เลื่อนได้ — โชว์ thumbnail (มีใน cache แล้วจาก bubble) ระหว่างรอตัวจริง
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.url, this.thumbnailUrl});

  final String url;
  final String? thumbnailUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
      body: InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Hero(
            tag: url,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (_, __) => thumbnailUrl == null
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : CachedNetworkImage(imageUrl: thumbnailUrl!, fit: BoxFit.contain),
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}

/// เล่นวิดีโอแบบ stream (ไม่ต้องโหลดทั้งไฟล์ก่อน — MinIO/S3 รองรับ Range request)
class VideoViewerScreen extends StatefulWidget {
  const VideoViewerScreen({super.key, required this.url, this.thumbnailUrl});

  final String url;
  final String? thumbnailUrl;

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _failed = false;

  /// ระดับเสียงที่ตั้งไว้ล่าสุด ใช้ต่อกับวิดีโอถัดไปในการเปิดแอปครั้งเดียวกัน
  /// (ปิดเสียงไว้แล้วเปิดวิดีโออื่น ก็ยังเงียบเหมือนเดิม)
  static double _sessionVolume = 1;

  /// ระดับก่อนกดปิดเสียง — กดเปิดเสียงแล้วกลับไปดังเท่าเดิม
  static double _volumeBeforeMute = 1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTick);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller.setVolume(_sessionVolume);
      _controller.play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  void _setVolume(double volume) {
    _sessionVolume = volume;
    _controller.setVolume(volume);
  }

  void _toggleMute() {
    if (_sessionVolume > 0) {
      _volumeBeforeMute = _sessionVolume;
      _setVolume(0);
    } else {
      _setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 1);
    }
  }

  IconData get _volumeIcon {
    if (_sessionVolume == 0) return Icons.volume_off;
    if (_sessionVolume < 0.5) return Icons.volume_down;
    return Icons.volume_up;
  }

  void _togglePlay() {
    if (_volumePinned) setState(() => _volumePinned = false);
    final v = _controller.value;
    if (v.isPlaying) {
      _controller.pause();
    } else {
      // เล่นจบแล้วกดอีกที = เริ่มใหม่ตั้งแต่ต้น
      if (v.position >= v.duration) _controller.seekTo(Duration.zero);
      _controller.play();
    }
  }

  /// เมาส์ชี้อยู่ที่ปุ่มลำโพงหรือแถบเสียง
  bool _volumeHovered = false;

  /// กำลังลากแถบเสียง — เมาส์หลุดออกนอกแถบระหว่างลากก็ยังไม่ซ่อน
  bool _volumeDragging = false;

  /// จอสัมผัสไม่มี hover: กดค้างที่ลำโพงเพื่อเปิด/ปิดแถบเสียงแทน
  bool _volumePinned = false;

  bool get _showVolumeSlider => _volumeHovered || _volumeDragging || _volumePinned;

  /// แถบล่าง: ลำโพงซ้าย, เวลาขวา — แถบเสียงแนวตั้งโผล่เหนือลำโพงเฉพาะตอนชี้เมาส์
  /// (ไม่บังวิดีโอตอนดูปกติ) แถวจัดชิดล่าง แถบที่โผล่จึงยืดขึ้นด้านบนโดยเวลาไม่ขยับ
  Widget _buildControls(VideoPlayerValue v) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildVolume(),
          const Spacer(),
          Padding(
            // ให้ตรงกับกึ่งกลางปุ่มลำโพง (สูง 48)
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              '${formatDuration(v.position)} / ${formatDuration(v.duration)}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolume() {
    // MouseRegion ครอบทั้งปุ่มและแถบ — เลื่อนเมาส์จากปุ่มขึ้นไปที่แถบได้โดยแถบไม่หาย
    return MouseRegion(
      onEnter: (_) => setState(() => _volumeHovered = true),
      onExit: (_) => setState(() => _volumeHovered = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(sizeFactor: animation, alignment: Alignment.bottomCenter, child: child),
            ),
            child: _showVolumeSlider ? _buildVolumeSlider() : const SizedBox(width: 48),
          ),
          // ไม่ใช้ IconButton เพราะ tooltip ของมันแย่ง "กดค้าง" บนจอสัมผัสไป —
          // tooltip ขึ้นเฉพาะตอนชี้เมาส์ (manual) ส่วนกดค้างใช้เปิด/ปิดแถบเสียง
          Tooltip(
            message: _sessionVolume == 0 ? 'เปิดเสียง' : 'ปิดเสียง',
            triggerMode: TooltipTriggerMode.manual,
            child: Semantics(
              button: true,
              child: InkResponse(
                onTap: _toggleMute,
                onLongPress: () => setState(() => _volumePinned = !_volumePinned),
                radius: 24,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(_volumeIcon, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeSlider() {
    return Container(
      key: const ValueKey('volume-slider'),
      width: 36,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: RotatedBox(
        quarterTurns: 3, // ซ้าย->ขวา กลายเป็น ล่าง->บน
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: Colors.white38,
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: _sessionVolume,
            onChanged: _setVolume,
            onChangeStart: (_) => setState(() => _volumeDragging = true),
            onChangeEnd: (_) => setState(() => _volumeDragging = false),
            semanticFormatterCallback: (value) => 'ระดับเสียง ${(value * 100).round()}%',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
      body: Center(
        child: _failed
            ? const Text('เล่นวิดีโอไม่สำเร็จ', style: TextStyle(color: Colors.white70))
            : !v.isInitialized
                ? Hero(
                    tag: widget.url,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (widget.thumbnailUrl != null)
                          CachedNetworkImage(imageUrl: widget.thumbnailUrl!, fit: BoxFit.contain),
                        const CircularProgressIndicator(color: Colors.white),
                      ],
                    ),
                  )
                : GestureDetector(
                    onTap: _togglePlay,
                    child: AspectRatio(
                      aspectRatio: v.aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoPlayer(_controller),
                          if (!v.isPlaying)
                            const CircleAvatar(
                              radius: 32,
                              backgroundColor: Colors.black45,
                              child: Icon(Icons.play_arrow, color: Colors.white, size: 44),
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _buildControls(v),
                                VideoProgressIndicator(
                                  _controller,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(playedColor: AppColors.primary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
