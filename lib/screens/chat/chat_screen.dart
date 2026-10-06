import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/auth_service.dart';
import '../../services/chat_media_service.dart';
import '../../services/chat_service.dart';
import '../../services/report_service.dart';
import '../../services/users_service.dart';
import '../../shared/api_exception.dart';
import '../../widgets/chat_media_bubble.dart';
import '../../widgets/pet_avatar.dart';
import '../../widgets/report_dialog.dart';
import '../profile/user_profile_screen.dart';
import '../../theme/app_theme.dart';

/// รูป/วิดีโอที่กำลังอัป — โชว์เป็น bubble ท้ายห้องพร้อมความคืบหน้าจนกว่าจะส่งสำเร็จ
class _PendingMedia {
  _PendingMedia(this.media) : id = 'pending_${_seq++}';
  // นับเลขแทนเวลา — เลือกหลายรูปทีเดียวสร้างหลายตัวในไมโครวินาทีเดียวกันได้ id จะชนกัน
  static int _seq = 0;
  final PreparedMedia media;
  final String id;
  double progress = 0;
  bool failed = false;
}

class ChatScreen extends StatefulWidget {
  /// null = ยังไม่มีห้องแชทจริง (เพิ่งกด "ทักแชท" มาจากการ์ด/รายละเอียดสัตว์)
  /// ห้องจะถูกสร้างจริงก็ต่อเมื่อพิมพ์และกดส่งข้อความแรกเท่านั้น ตรงตาม SKILL.md:
  /// "การกดถูกใจต้องไม่สร้างห้องแชทอัตโนมัติ — ห้องแชทเกิดตอนผู้ใช้กดส่งข้อความแรก"
  final String? chatId;

  /// จำเป็นเสมอ แม้ตอนที่ chatId ยังเป็น null ก็ต้องรู้ว่ากำลังทักเรื่องสัตว์ตัวไหน
  /// เพื่อส่งไปสร้างห้องตอนกดส่งข้อความแรก
  final String petId;

  final String dogName;
  final String otherUserName;
  final String otherUserAvatar;
  final String otherUserId;

  const ChatScreen({
    super.key,
    this.chatId,
    required this.petId,
    required this.dogName,
    required this.otherUserName,
    this.otherUserAvatar = '',
    this.otherUserId = '',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String? _chatId;
  final FocusNode _msgFocus = FocusNode();
  bool _sending = false;

  /// สถานะห้องจาก server — closed = อ่านย้อนหลังได้แต่พิมพ์ไม่ได้ (สัตว์ได้บ้าน/ยกเลิกประกาศ/บล็อก)
  bool _closed = false;
  String? _closedReason;
  bool _blockedByMe = false;
  int _systemCount = 0;

  /// ค้นหาข้อความในห้องนี้ (null = ปิดแถบค้นหา)
  String? _search;
  final TextEditingController _searchController = TextEditingController();

  /// รูปคู่สนทนาที่จะโชว์บน AppBar — เริ่มจากค่าที่ส่งมา (มีเฉพาะตอนเข้าจากกล่องข้อความ
  /// ซึ่ง GET /chats ส่ง otherUserAvatarUrl มาให้) ถ้าไม่มีจะไปดึงเองใน _loadOtherAvatar()
  String _otherAvatar = '';

  /// กำลังหาว่าเคยมีห้องแชทของประกาศนี้อยู่แล้วหรือไม่ ระหว่างนี้ยังไม่รู้ว่าจะมี
  /// ประวัติเดิมให้โชว์ไหม เลยต้องกันไม่ให้ขึ้นข้อความ "ทักทาย...กันเลย!" ไปก่อน
  bool _resolvingChat = false;

  /// สร้างครั้งเดียวตอนรู้ห้องแชท (ใน _openRoom) ห้ามสร้างใน build() —
  /// build() รันใหม่ทุกครั้งที่พิมพ์/ส่งข้อความ ถ้าสร้าง stream ใหม่ทุกรอบ
  /// StreamBuilder จะรีเซ็ตกลับไปสถานะ "ยังไม่มีข้อมูล" (เด้งเป็น spinner)
  /// และยิง REST + join ห้องซ้ำทุกครั้ง
  MessageFeed? _feed;
  Stream<List<Map<String, dynamic>>>? _messagesStream;

  final List<_PendingMedia> _pending = [];

  /// กำลังเลือก/ย่อรูป/บีบวิดีโอ (ก่อนมี bubble ให้เห็น) — วิดีโออาจใช้หลายวินาที
  bool _preparingMedia = false;

  /// id ข้อความล่าสุดที่เลื่อนลงไปแล้ว — เลื่อนลงล่างเฉพาะตอนมีข้อความใหม่
  /// ไม่ใช่ทุกครั้งที่ build (ไม่งั้นกดดูข้อความเก่าแล้วจอจะเด้งกลับลงล่างตลอด)
  String? _lastScrolledId;

  static const _typingIdle = Duration(seconds: 2);
  // เผื่อ event "หยุดพิมพ์" หาย (อีกฝ่ายปิดแอปกลางทาง) ไม่ให้ค้าง "กำลังพิมพ์..." ตลอดไป
  static const _typingExpiry = Duration(seconds: 5);

  final List<StreamSubscription> _roomSubs = [];
  bool _otherTyping = false;
  Timer? _otherTypingExpiry;
  bool _iAmTyping = false;
  Timer? _myTypingIdle;

  String get _myUid => AuthService.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _chatId = widget.chatId;
    _otherAvatar = widget.otherUserAvatar;
    if (_chatId != null) {
      _openRoom(_chatId!);
    } else if (widget.otherUserId.isNotEmpty) {
      _resolvingChat = true;
      _resolveExistingChat();
    }
    if (_otherAvatar.isEmpty && widget.otherUserId.isNotEmpty) {
      _loadOtherAvatar();
    }
  }

  /// เข้าจากปุ่ม "ทักแชท" (หน้าปัด/ถูกใจ/รายละเอียดประกาศ) จะไม่มีรูปคู่สนทนาติดมา
  /// เพราะข้อมูลประกาศไม่มี avatar ของเจ้าของอยู่ในนั้น — ดึงจากโปรไฟล์สาธารณะเอง
  /// เพื่อให้ทุกทางเข้าเห็นรูปเหมือนกัน ไม่ใช่เห็นเฉพาะตอนเข้าจากกล่องข้อความ
  Future<void> _loadOtherAvatar() async {
    try {
      final profile = await UsersService.instance.getPublicProfile(widget.otherUserId);
      final url = profile['profileImageUrl'] as String? ?? '';
      if (!mounted || url.isEmpty) return;
      setState(() => _otherAvatar = url);
    } catch (_) {
      // ดึงไม่ได้ก็แค่โชว์ไอคอนคนตามเดิม ไม่ใช่เรื่องที่ต้องขัดจังหวะผู้ใช้
    }
  }

  /// เปิดมาจากปุ่ม "ทักแชท" ซึ่งไม่รู้ chatId — ถ้าเคยคุยกันเรื่องประกาศนี้แล้ว
  /// ต้องเข้าห้องเดิมให้เห็นประวัติ ไม่ใช่เริ่มจากห้องว่าง
  Future<void> _resolveExistingChat() async {
    try {
      final existing = await ChatService.instance.findChatForPet(
        petId: widget.petId,
        otherUserId: widget.otherUserId,
      );
      if (!mounted || existing == null) return;
      setState(() => _openRoom(existing));
    } catch (_) {
      // หาห้องเดิมไม่เจอเพราะเน็ตมีปัญหา ยังพิมพ์ข้อความใหม่ได้ตามปกติ —
      // createOrSend ฝั่ง backend ผูกข้อความเข้าห้องเดิมให้เองอยู่แล้ว
    } finally {
      if (mounted) setState(() => _resolvingChat = false);
    }
  }

  /// เข้าห้อง: ฟังข้อความ (รวมสถานะอ่านแล้ว) กับกำลังพิมพ์ของห้องนี้ และ mark read ทันที
  /// (ต้องเรียกใน setState หรือก่อน build แรก เพราะแก้ _messagesStream)
  void _openRoom(String chatId) {
    final chat = ChatService.instance;
    _chatId = chatId;
    _feed = chat.openMessages(chatId, myUid: _myUid);
    _messagesStream = _feed!.stream;
    _roomSubs.add(chat.otherTyping(chatId, myUid: _myUid).listen((typing) {
      _otherTypingExpiry?.cancel();
      if (typing) {
        _otherTypingExpiry = Timer(_typingExpiry, () {
          if (mounted) setState(() => _otherTyping = false);
        });
      }
      if (mounted) setState(() => _otherTyping = typing);
    }));
    chat.markRead(chatId).catchError((_) {});
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final id = _chatId;
    if (id == null) return;
    try {
      final d = await ChatService.instance.detail(id);
      if (!mounted) return;
      setState(() {
        _closed = d['status'] == 'closed';
        _closedReason = d['closedReason'] as String?;
        _blockedByMe = d['blockedByMe'] == true;
      });
    } catch (_) {
      // ดึงสถานะไม่ได้ก็ปล่อยให้พิมพ์ตามเดิม ถ้าห้องปิดจริง server จะตอบ 403 ตอนส่งอยู่แล้ว
    }
  }

  /// ส่ง "กำลังพิมพ์" ครั้งเดียวตอนเริ่ม แล้วส่ง "หยุด" เมื่อเว้นไป 2 วิ
  /// ไม่ยิงทุกแป้นที่กด
  void _onTextChanged(String text) {
    final chatId = _chatId;
    if (chatId == null) return;
    if (!_iAmTyping && text.isNotEmpty) {
      _iAmTyping = true;
      ChatService.instance.setTyping(chatId, true);
    }
    _myTypingIdle?.cancel();
    _myTypingIdle = Timer(_typingIdle, _stopTyping);
  }

  void _stopTyping() {
    _myTypingIdle?.cancel();
    if (!_iAmTyping || _chatId == null) return;
    _iAmTyping = false;
    ChatService.instance.setTyping(_chatId!, false);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _msgController.clear();
    _stopTyping();
    FocusScope.of(context).unfocus();

    try {
      await _deliver(text: text);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: AppTheme.snackDuration, content: Text('ส่งข้อความไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// ส่งข้อความ (ตัวหนังสือ หรือสื่อที่อัปแล้ว) เข้าห้อง — ถ้ายังไม่มีห้อง ข้อความนี้คือ
  /// ข้อความแรก ต้องสร้างห้องพร้อมกันในธุรกรรมเดียว
  Future<void> _deliver({String text = '', Map<String, dynamic>? media}) async {
    if (_chatId == null) {
      final newChatId = await ChatService.instance
          .createOrSend(petId: widget.petId, message: text, media: media);
      if (!mounted) return;
      // ประวัติ (รวมข้อความนี้) มาจากการโหลดครั้งแรกของ feed
      setState(() => _openRoom(newChatId));
    } else {
      final sent = await ChatService.instance.sendMessage(_chatId!, text: text, media: media);
      // ใส่ลง feed เลยจากผลของ POST ไม่ต้องรอ event จาก socket
      _feed?.upsert(sent);
    }
  }

  // ---------------------------------------------------------------------------
  // รูป / วิดีโอ
  // ---------------------------------------------------------------------------

  /// ห้องยังไม่เกิด: ให้ส่งได้ทีละชิ้น ไม่งั้นสองคำขอจะแย่งกันสร้างห้องเดียวกัน
  bool get _canAttach => !_preparingMedia && !(_chatId == null && _pending.isNotEmpty);

  Future<void> _showAttachSheet() async {
    final media = ChatMediaService.instance;
    Future<List<PreparedMedia>> single(Future<PreparedMedia?> picked) async {
      final m = await picked;
      return m == null ? const [] : [m];
    }

    final pick = await showModalBottomSheet<Future<List<PreparedMedia>> Function()>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('รูปภาพจากคลัง'),
              subtitle: const Text('เลือกได้สูงสุด ${ChatMediaService.maxImagesPerPick} รูป'),
              onTap: () => Navigator.pop(sheet, _pickGalleryImages),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('ถ่ายรูป'),
                onTap: () => Navigator.pop(sheet, () => single(media.pickImage(ImageSource.camera))),
              ),
            if (ChatMediaService.canSendVideo) ...[
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text(kIsWeb ? 'วิดีโอจากเครื่อง' : 'วิดีโอจากคลัง'),
                subtitle: Text(ChatMediaService.videoLimitHint),
                onTap: () => Navigator.pop(sheet, () => single(media.pickVideo(ImageSource.gallery))),
              ),
              if (ChatMediaService.canRecordVideo)
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('ถ่ายวิดีโอ'),
                  onTap: () => Navigator.pop(sheet, () => single(media.pickVideo(ImageSource.camera))),
                ),
            ],
          ],
        ),
      ),
    );
    if (pick != null) await _prepareAndSend(pick);
  }

  Future<List<PreparedMedia>> _pickGalleryImages() async {
    final picked = await ChatMediaService.instance.pickImages();
    if (picked.skipped > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: AppTheme.snackDuration,
          content: Text('ข้าม ${picked.skipped} รูป (อ่านไฟล์ไม่ได้ หรือเกิน '
              '${ChatMediaService.maxImagesPerPick} รูป)')));
    }
    return picked.images;
  }

  Future<void> _prepareAndSend(Future<List<PreparedMedia>> Function() pick) async {
    setState(() => _preparingMedia = true);
    var picked = const <PreparedMedia>[];
    try {
      picked = await pick();
    } catch (e) {
      _showError(e, 'เปิดไฟล์นี้ไม่ได้ กรุณาเลือกไฟล์อื่น');
    } finally {
      if (mounted) setState(() => _preparingMedia = false);
    }
    if (picked.isEmpty || !mounted) return;

    final batch = [for (final m in picked) _PendingMedia(m)];
    setState(() => _pending.addAll(batch));
    await _sendPending(batch);
  }

  /// อัปพร้อมกันได้ครั้งละกี่ไฟล์ — มากกว่านี้เน็ตมือถือแบ่งกันจนทุกไฟล์ช้าลงพอ ๆ กัน
  static const _uploadConcurrency = 3;

  /// อัปทั้งชุดพร้อมกันทีละ [_uploadConcurrency] ไฟล์ แต่ส่งข้อความ "ตามลำดับที่เลือก" เสมอ
  /// (รูปที่ 3 อัปเสร็จก่อนรูปที่ 1 ก็ต้องรอ ไม่งั้นลำดับในห้องสลับกัน)
  ///
  /// ส่งทีละข้อความจึงปลอดภัยตอนห้องยังไม่เกิด: ข้อความแรกสร้างห้อง ที่เหลือเข้าห้องนั้นต่อ
  /// ชิ้นที่ล้มเหลวค้างเป็น bubble ให้แตะลองใหม่ ชิ้นถัดไปส่งต่อได้เลยไม่ต้องรอ
  Future<void> _sendPending(List<_PendingMedia> batch) async {
    setState(() {
      for (final p in batch) {
        p.failed = false;
        p.progress = 0;
      }
    });

    // ผลของแต่ละชิ้นเป็น record ไม่ใช่ completeError — ชิ้นท้าย ๆ ที่ล้มก่อนถึงคิว await
    // จะกลายเป็น unhandled error ของ zone
    final uploads = [
      for (final _ in batch) Completer<({Map<String, dynamic>? media, Object? error})>()
    ];
    var next = 0;
    Future<void> worker() async {
      while (next < batch.length) {
        final i = next++;
        final pending = batch[i];
        try {
          final media = await ChatMediaService.instance.upload(
            pending.media,
            onProgress: (v) {
              if (mounted) setState(() => pending.progress = v);
            },
          );
          uploads[i].complete((media: media, error: null));
        } catch (e) {
          uploads[i].complete((media: null, error: e));
        }
      }
    }

    for (var w = 0; w < math.min(_uploadConcurrency, batch.length); w++) {
      unawaited(worker());
    }

    Object? lastError;
    var failed = 0;
    for (var i = 0; i < batch.length; i++) {
      final pending = batch[i];
      final result = await uploads[i].future;
      try {
        if (result.error != null) throw result.error!;
        await _deliver(media: result.media);
        if (mounted) setState(() => _pending.remove(pending));
      } catch (e) {
        failed++;
        lastError = e;
        if (mounted) setState(() => pending.failed = true);
      }
    }

    if (failed == 0 || !mounted) return;
    if (batch.length == 1) {
      _showError(lastError!, 'ส่งไฟล์ไม่สำเร็จ แตะที่รูปเพื่อลองใหม่');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: AppTheme.snackDuration,
          content: Text('ส่งไม่สำเร็จ $failed จาก ${batch.length} ไฟล์ แตะที่รูปเพื่อลองใหม่')));
    }
  }

  Future<void> _onPendingTap(_PendingMedia pending) async {
    if (!pending.failed) return;
    final retry = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('ลองส่งอีกครั้ง'),
              onTap: () => Navigator.pop(sheet, true),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('ยกเลิก', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(sheet, false),
            ),
          ],
        ),
      ),
    );
    if (retry == null || !mounted) return;
    if (retry) {
      await _sendPending([pending]);
    } else {
      setState(() => _pending.remove(pending));
    }
  }

  void _showError(Object error, String fallback) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: AppTheme.snackDuration, content: Text(error is ApiException ? error.message : fallback)));
  }

  @override
  void dispose() {
    _stopTyping();
    _otherTypingExpiry?.cancel();
    for (final s in _roomSubs) {
      s.cancel();
    }
    _msgController.dispose();
    _searchController.dispose();
    _msgFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = AuthService.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: GestureDetector(
          onTap: widget.otherUserId.isEmpty
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(
                        uid: widget.otherUserId,
                        fallbackName: widget.otherUserName,
                      ),
                    ),
                  ),
          child: Row(
            children: [
              _otherAvatar.isNotEmpty
                  ? PetAvatar(
                      imageUrl: _otherAvatar,
                      radius: 20,
                      icon: Icons.person,
                      backgroundColor: Colors.white,
                    )
                  : const CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 20,
                      child: Icon(Icons.person, color: AppColors.primary, size: 22),
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.otherUserName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis),
                    Text(_otherTyping ? 'กำลังพิมพ์...' : 'สัตว์เลี้ยง: ${widget.dogName}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                            fontStyle: _otherTyping ? FontStyle.italic : FontStyle.normal)),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 1,
        actions: [
          if (_chatId != null)
            PopupMenuButton<String>(
              key: const ValueKey('chat-menu'),
              onSelected: _onMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'search', child: Text('ค้นหาข้อความ')),
                if (widget.otherUserId.isNotEmpty) ...[
                  PopupMenuItem(
                      value: _blockedByMe ? 'unblock' : 'block',
                      child: Text(_blockedByMe ? 'ปลดบล็อก' : 'บล็อก')),
                  const PopupMenuItem(value: 'report', child: Text('รายงานผู้ใช้')),
                ],
                const PopupMenuItem(value: 'delete', child: Text('ลบแชท')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (_search != null) _buildSearchBar(),
          Expanded(child: _buildMessageList(myUid)),
          _closed ? _buildClosedBanner() : _buildComposer(),
        ],
      ),
    );
  }

  Future<bool> _confirm(String title, String message, String ok) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return res == true;
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: AppTheme.snackDuration, content: Text(text)));

  Future<void> _onMenu(String action) async {
    final chatId = _chatId;
    if (chatId == null) return;
    switch (action) {
      case 'search':
        setState(() => _search = '');
      case 'block':
        if (!await _confirm('บล็อก ${widget.otherUserName}',
            'ห้องแชทนี้จะถูกปิด และคุณทั้งสองจะไม่เห็นประกาศของกันและกัน ปลดบล็อกได้ภายหลัง', 'บล็อก')) {
          return;
        }
        try {
          await ReportService.instance.blockUser(widget.otherUserId);
          await _loadDetail();
          if (mounted) _snack('บล็อกแล้ว');
        } catch (_) {
          if (mounted) _snack('บล็อกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
        }
      case 'unblock':
        try {
          await ReportService.instance.unblockUser(widget.otherUserId);
          await _loadDetail();
          if (mounted) _snack('ปลดบล็อกแล้ว');
        } catch (_) {
          if (mounted) _snack('ปลดบล็อกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
        }
      case 'report':
        await reportWithDialog(
          context,
          title: 'รายงาน ${widget.otherUserName}',
          send: (reason, detail) =>
              ReportService.instance.reportUser(widget.otherUserId, reason: reason, detail: detail),
          blockUserId: widget.otherUserId,
          blockUserName: widget.otherUserName,
          onBlocked: _loadDetail,
        );
      case 'delete':
        if (!await _confirm('ลบแชท', 'แชทนี้จะหายจากรายการของคุณ (อีกฝ่ายยังเห็นอยู่) ลบแล้วกู้คืนไม่ได้', 'ลบ')) {
          return;
        }
        try {
          await ChatService.instance.hideChat(chatId);
          if (mounted) Navigator.pop(context);
        } catch (_) {
          if (mounted) _snack('ลบแชทไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
        }
    }
  }

  Widget _buildSearchBar() {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('chat-search'),
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'ค้นหาข้อความในแชทนี้',
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _search = v.trim()),
              ),
            ),
            IconButton(
              tooltip: 'ปิดการค้นหา',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _search = null;
                _searchController.clear();
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// ห้องถูกปิด: แทนช่องพิมพ์ด้วยคำอธิบาย (ถ้าเราเป็นคนบล็อก มีปุ่มปลดบล็อกให้ตรงนี้เลย)
  Widget _buildClosedBanner() {
    final text = _blockedByMe
        ? 'คุณบล็อกผู้ใช้นี้อยู่ ปลดบล็อกเพื่อคุยต่อ'
        : switch (_closedReason) {
            'pet_adopted' => 'สัตว์ตัวนี้มีบ้านแล้ว ห้องแชทนี้ถูกปิด',
            'pet_deleted' => 'ประกาศนี้ถูกยกเลิกแล้ว ห้องแชทนี้ถูกปิด',
            'blocked' => 'ไม่สามารถส่งข้อความในห้องนี้ได้',
            _ => 'ห้องแชทนี้ถูกปิดแล้ว',
          };
    return SafeArea(
      child: Container(
        key: const ValueKey('chat-closed'),
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(text, style: const TextStyle(color: Colors.black54))),
            if (_blockedByMe) TextButton(onPressed: () => _onMenu('unblock'), child: const Text('ปลดบล็อก')),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(String myUid) {
    if (_resolvingChat) {
      return const Center(child: CircularProgressIndicator());
    }

    final messagesStream = _messagesStream;
    if (messagesStream == null && _pending.isNotEmpty) {
      // ข้อความแรกเป็นรูป/วิดีโอที่กำลังอัป — ห้องจะเกิดตอนอัปเสร็จแล้วส่ง
      return ListView(
        padding: const EdgeInsets.all(16),
        children: _pending.map(_buildPending).toList(),
      );
    }
    if (messagesStream == null) {
      // ยังไม่เคยส่งข้อความเลย ไม่มีห้องให้ poll — โชว์ช่องว่างเชิญชวนให้เริ่มคุย
      return Center(
        child: Text('ทักทายเรื่องสัตว์เลี้ยง ${widget.dogName} กันเลย!',
            style: const TextStyle(color: Colors.black38)),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: messagesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError && !snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.black26),
                const SizedBox(height: 12),
                const Text('โหลดข้อความไม่สำเร็จ',
                    key: ValueKey('chat-load-error'), style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 4),
                const Text('เซิร์ฟเวอร์ตอบช้าหรือไม่ตอบสนอง',
                    style: TextStyle(fontSize: 12, color: Colors.black38)),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const ValueKey('chat-retry'),
                  onPressed: () => _feed?.reload(),
                  child: const Text('ลองใหม่'),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final serverMessages = snapshot.data!;

        // มีข้อความระบบใหม่ (สัตว์ได้บ้าน/ประกาศถูกยกเลิก) = ห้องเพิ่งถูกปิด ดึงสถานะใหม่
        final systemCount = serverMessages.where((m) => m['kind'] == 'system').length;
        if (systemCount != _systemCount) {
          _systemCount = systemCount;
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetail());
        }

        // ค้นหาข้อความในห้อง (เมนู ⋮ > ค้นหาข้อความ) กรองเฉพาะข้อความที่มีตัวอักษรตรงกัน
        final query = (_search ?? '').toLowerCase();
        final messages = [
          for (final m in serverMessages)
            if (query.isEmpty || '${m['text']}'.toLowerCase().contains(query)) m,
        ];
        if (messages.isEmpty && query.isNotEmpty) {
          return const Center(child: Text('ไม่พบข้อความที่ค้นหา', style: TextStyle(color: Colors.black38)));
        }
        if (messages.isEmpty && _pending.isEmpty) {
          return Center(
            child: Text('ทักทายเรื่องสัตว์เลี้ยง ${widget.dogName} กันเลย!',
                style: const TextStyle(color: Colors.black38)),
          );
        }

        final readIndex = _lastReadByOther(messages, myUid);
        final latestId = _pending.isNotEmpty
            ? _pending.last.id
            : (messages.isEmpty ? null : messages.last['id'] as String?);
        if (latestId != _lastScrolledId) {
          _lastScrolledId = latestId;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        final feed = _feed;
        final showLoadOlder = feed != null && feed.hasMore;
        final offset = showLoadOlder ? 1 : 0;

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: offset + messages.length + _pending.length,
          itemBuilder: (context, i) {
            if (showLoadOlder && i == 0) return _buildLoadOlder(feed);
            final index = i - offset;
            if (index >= messages.length) {
              return _buildPending(_pending[index - messages.length]);
            }

            final data = messages[index];
            if (data['kind'] == 'system') {
              // ประกาศของระบบ แบบ "เข้าร่วม/ออกจากกลุ่ม" ในไลน์ — อยู่กลางจอ ไม่ใช่ฟองของใคร
              return Center(
                child: Container(
                  key: ValueKey('system-${data['id']}'),
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(AppRadius.card)),
                  child: Text('${data['text']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ),
              );
            }
            final isMe = data['senderId'] == myUid;
            final messageId = data['id'];
            // รายงานได้เฉพาะข้อความของอีกฝ่ายที่ถูกบันทึกลงเซิร์ฟเวอร์แล้ว (ข้อความที่ยังไม่มี id จริงยังไม่ได้)
            final reportable = !isMe && messageId is String && messageId.isNotEmpty;
            Widget bubble = _buildMessage(data, isMe);
            if (reportable) {
              bubble = GestureDetector(
                key: ValueKey('msg-$messageId'),
                onLongPress: () => _offerReport(messageId),
                child: bubble,
              );
            }
            if (index != readIndex) return bubble;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                bubble,
                const Padding(
                  padding: EdgeInsets.only(bottom: 8, right: 4),
                  child: Text('อ่านแล้ว', style: TextStyle(fontSize: 11, color: Colors.black45)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// กดค้างที่ข้อความของอีกฝ่าย → เมนูรายงาน (แอดมินจะเห็นเฉพาะข้อความที่ถูกรายงานนี้ข้อความเดียว)
  Future<void> _offerReport(String messageId) async {
    final go = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          key: const ValueKey('report-message'),
          leading: const Icon(Icons.flag_outlined),
          title: const Text('รายงานข้อความนี้'),
          onTap: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    if (go != true || !mounted) return;
    await reportWithDialog(
      context,
      title: 'รายงานข้อความนี้',
      send: (reason, detail) =>
          ReportService.instance.reportMessage(messageId, reason: reason, detail: detail),
      blockUserId: widget.otherUserId.isEmpty ? null : widget.otherUserId,
      blockUserName: widget.otherUserName,
      onBlocked: _loadDetail,
    );
  }

  Widget _buildLoadOlder(MessageFeed feed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: feed.loadingOlder
            ? const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton.icon(
                onPressed: () => feed
                    .loadOlder()
                    .catchError((Object e) => _showError(e, 'โหลดข้อความก่อนหน้าไม่สำเร็จ')),
                icon: const Icon(Icons.history, size: 18),
                label: const Text('ดูข้อความก่อนหน้า'),
                style: TextButton.styleFrom(foregroundColor: Colors.black54),
              ),
      ),
    );
  }

  Widget _buildPending(_PendingMedia pending) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTap: () => _onPendingTap(pending),
          child: ChatMediaBubble(
            type: pending.media.type,
            width: pending.media.width,
            height: pending.media.height,
            localThumbnail: pending.media.thumbnail,
            progress: pending.progress,
            failed: pending.failed,
          ),
        ),
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> data, bool isMe) {
    final text = data['text'] as String? ?? '';
    final media = data['media'] is Map ? Map<String, dynamic>.from(data['media'] as Map) : null;
    final textBubble = text.isEmpty
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isMe ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 20),
              ),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Text(text,
                style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 16)),
          );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: media == null
            ? textBubble
            : Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  ChatMediaBubble.fromMessage(media),
                  if (textBubble != null) ...[const SizedBox(height: 4), textBubble],
                ],
              ),
      ),
    );
  }

  /// ข้อความล่าสุดของเราที่อีกฝ่ายอ่านแล้ว — โชว์ "อ่านแล้ว" ใต้ข้อความนั้นอันเดียว
  int? _lastReadByOther(List<Map<String, dynamic>> messages, String myUid) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m['senderId'] == myUid && m['readAt'] != null) return i;
    }
    return null;
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'แนบรูปหรือวิดีโอ',
            onPressed: _canAttach ? _showAttachSheet : null,
            color: AppColors.primary,
            icon: _preparingMedia
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_photo_alternate_outlined),
          ),
          Expanded(
            child: TextField(
              controller: _msgController,
              focusNode: _msgFocus,
              // readOnly แทน enabled:false — ถ้า disable ช่องจะเสียโฟกัส กด Enter ส่งต่อรอบถัดไปไม่ได้
              readOnly: _sending,
              decoration: InputDecoration(
                hintText: 'พิมพ์ข้อความ...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onChanged: _onTextChanged,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) {
                _sendMessage();
                _msgFocus.requestFocus(); // ให้พิมพ์/Enter ต่อได้เลย
              },
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
