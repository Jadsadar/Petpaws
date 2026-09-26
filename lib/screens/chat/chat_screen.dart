import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/users_service.dart';
import '../../widgets/pet_avatar.dart';
import '../profile/user_profile_screen.dart';

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
  bool _sending = false;

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
  Stream<List<Map<String, dynamic>>>? _messagesStream;

  // ข้อความที่ยิง POST ไปแล้วแต่ event จาก server ยังมาไม่ถึง — โชว์ค้างไว้ก่อน
  // (optimistic) กันช่วงเสี้ยววินาทีที่ข้อความหายไปก่อนโผล่จริง
  final List<Map<String, dynamic>> _optimisticMessages = [];

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
    _messagesStream = chat.watchMessages(chatId, myUid: _myUid);
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

    final optimistic = {
      'id': 'local_${DateTime.now().microsecondsSinceEpoch}',
      'senderId': _myUid,
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    };

    try {
      if (_chatId == null) {
        // ยังไม่มีห้อง — ข้อความนี้คือข้อความแรก ต้องสร้างห้องพร้อมกันในธุรกรรมเดียว
        final newChatId =
            await ChatService.instance.createOrSend(petId: widget.petId, message: text);
        if (!mounted) return;
        setState(() {
          _openRoom(newChatId);
          _optimisticMessages.add(optimistic);
        });
      } else {
        await ChatService.instance.sendMessage(_chatId!, text);
        if (!mounted) return;
        setState(() => _optimisticMessages.add(optimistic));
      }
      _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ส่งข้อความไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _stopTyping();
    _otherTypingExpiry?.cancel();
    for (final s in _roomSubs) {
      s.cancel();
    }
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myUid = AuthService.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF6F0),
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
                      child: Icon(Icons.person, color: Color(0xFFFF9E68), size: 22),
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
        backgroundColor: const Color(0xFFFF9E68),
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(myUid)),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildMessageList(String myUid) {
    if (_resolvingChat) {
      return const Center(child: CircularProgressIndicator());
    }

    final messagesStream = _messagesStream;
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
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        // รวมข้อความจริงจาก server กับข้อความ optimistic ที่ event ยังมาไม่ถึง
        // (เทียบด้วย text+senderId คร่าว ๆ พอ — ไม่ต้องเป๊ะเพราะเป็นแค่กันจอกระพริบชั่วคราว)
        final serverMessages = snapshot.data!;
        final pendingStillMissing = _optimisticMessages.where((opt) {
          return !serverMessages.any((m) =>
              m['senderId'] == opt['senderId'] && m['text'] == opt['text']);
        }).toList();
        if (pendingStillMissing.length != _optimisticMessages.length) {
          // บาง optimistic message โผล่จริงแล้วจาก server ตัดตัวที่ซ้ำทิ้ง
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _optimisticMessages
              ..clear()
              ..addAll(pendingStillMissing));
          });
        }

        final messages = [...serverMessages, ...pendingStillMissing];
        if (messages.isEmpty) {
          return Center(
            child: Text('ทักทายเรื่องสัตว์เลี้ยง ${widget.dogName} กันเลย!',
                style: const TextStyle(color: Colors.black38)),
          );
        }

        final readIndex = _lastReadByOther(messages, myUid);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final data = messages[index];
            final isMe = data['senderId'] == myUid;
            final bubble = Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                decoration: BoxDecoration(
                  color: isMe ? const Color(0xFFFF9E68) : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isMe ? 20 : 0),
                    bottomRight: Radius.circular(isMe ? 0 : 20),
                  ),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Text(data['text'] as String? ?? '',
                    style: TextStyle(color: isMe ? Colors.white : Colors.black87, fontSize: 16)),
              ),
            );
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
          Expanded(
            child: TextField(
              controller: _msgController,
              enabled: !_sending,
              decoration: InputDecoration(
                hintText: 'พิมพ์ข้อความ...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onChanged: _onTextChanged,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Color(0xFFFF9E68), shape: BoxShape.circle),
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
