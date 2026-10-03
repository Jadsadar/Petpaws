import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/chat_service.dart';
import '../../widgets/pet_avatar.dart';
import 'chat_screen.dart';

class ChatInboxScreen extends StatefulWidget {
  /// ถ้าระบุ = โหมดเจ้าของดูแชทของ "ประกาศนี้" ตัวเดียว (กรองด้วยชื่อสัตว์
  /// เพราะ ChatInboxScreen เดิมออกแบบมารับแค่ dogName ไม่ใช่ petId — ยังมีบั๊กเดิม
  /// ที่สัตว์ชื่อซ้ำกันจะกรองปนกันได้ ดูรายละเอียดใน ROADMAP.md)
  /// ถ้าไม่ระบุ (null) = โหมดข้อความทั้งหมดของฉัน
  final String? dogName;

  const ChatInboxScreen({super.key, this.dogName});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  /// สร้าง stream ครั้งเดียวตอน initState ห้ามสร้างใน build() เด็ดขาด —
  /// หน้านี้อยู่ใน IndexedStack ของ MainScreen ซึ่ง rebuild ทุกครั้งที่ปัดการ์ด/
  /// สลับแท็บ ถ้าสร้างใหม่ทุก build จะยิง REST ซ้ำและสมัครฟัง event ซ้อนกันเรื่อย ๆ
  late final Stream<List<Map<String, dynamic>>> _chatsStream;

  /// null = ปิดช่องค้นหา — ค้นจากชื่อคู่สนทนา ชื่อสัตว์ และข้อความล่าสุด
  String? _search;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(Map<String, dynamic> chat, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return ['otherUserName', 'petName', 'lastMessage']
        .any((k) => '${chat[k] ?? ''}'.toLowerCase().contains(q));
  }

  /// ลบแชท = ซ่อนเฉพาะฝั่งเรา อีกฝ่ายยังเห็น (กดค้างที่แถวเพื่อลบ)
  Future<void> _deleteChat(Map<String, dynamic> chat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบแชท'),
        content: Text('แชทกับ ${chat['otherUserName'] ?? 'ผู้ใช้'} จะหายจากรายการของคุณ (อีกฝ่ายยังเห็นอยู่)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ChatService.instance.hideChat(chat['id'] as String);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ลบแชทไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _chatsStream = ChatService.instance.watchChats(petName: widget.dogName);
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final date = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return DateFormat.Hm().format(date);
    }
    return DateFormat('d MMM').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF6F0),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('กล่องข้อความ',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFFFF9E68), fontSize: 18)),
            Text(
                widget.dogName == null
                    ? 'ข้อความทั้งหมด'
                    : 'สัตว์เลี้ยง: ${widget.dogName}',
                style: const TextStyle(fontSize: 12, color: Colors.black45)),
          ],
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFFFF9E68)),
        elevation: 1,
        actions: [
          IconButton(
            key: const ValueKey('inbox-search-toggle'),
            tooltip: _search == null ? 'ค้นหาแชท' : 'ปิดการค้นหา',
            icon: Icon(_search == null ? Icons.search : Icons.close),
            onPressed: () => setState(() {
              _search = _search == null ? '' : null;
              _searchController.clear();
            }),
          ),
        ],
        bottom: _search == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    key: const ValueKey('inbox-search'),
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'ค้นหาชื่อ สัตว์เลี้ยง หรือข้อความ',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) => setState(() => _search = v.trim()),
                  ),
                ),
              ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _chatsStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final chats = [for (final c in all) if (_matches(c, _search ?? '')) c];
          if (all.isNotEmpty && chats.isEmpty) {
            return const Center(child: Text('ไม่พบแชทที่ค้นหา', style: TextStyle(color: Colors.grey)));
          }
          if (chats.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.black12),
                  SizedBox(height: 16),
                  Text('ยังไม่มีคนทักมาเลย',
                      style: TextStyle(fontSize: 16, color: Colors.grey)),
                  SizedBox(height: 8),
                  Text('แชร์โพสต์เพื่อให้คนรู้จักสัตว์เลี้ยงของคุณมากขึ้น',
                      style: TextStyle(fontSize: 13, color: Colors.black38)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 80),
            itemBuilder: (context, index) {
              final chat = chats[index];
              final otherName = chat['otherUserName'] as String? ?? 'ผู้สนใจรับเลี้ยง';
              final chatDogName = chat['petName'] as String? ?? widget.dogName ?? '';
              final lastMessage = chat['lastMessage'] as String? ?? '';
              final unread = (chat['unreadCount'] as num?)?.toInt() ?? 0;
              final isUnread = unread > 0;

              return ListTile(
                key: ValueKey('chat-${chat['id']}'),
                onLongPress: () => _deleteChat(chat),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                leading: Stack(
                  children: [
                    PetAvatar(
                      imageUrl: chat['petImageUrl'] as String?,
                      radius: 28,
                      icon: Icons.person,
                    ),
                    if (isUnread)
                      const Positioned(
                        right: 0,
                        top: 0,
                        child: CircleAvatar(radius: 6, backgroundColor: Color(0xFFFF9E68)),
                      ),
                  ],
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(otherName,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                              fontSize: 16)),
                    ),
                    Text(_formatTime(chat['lastMessageAt'] as String?),
                        style: TextStyle(
                            fontSize: 12,
                            color: isUnread ? const Color(0xFFFF9E68) : Colors.grey,
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.normal)),
                  ],
                ),
                subtitle: Text(
                  widget.dogName == null
                      ? 'สัตว์เลี้ยง: $chatDogName • ${lastMessage.isEmpty ? "เริ่มการสนทนาแล้ว" : lastMessage}'
                      : (lastMessage.isEmpty ? 'เริ่มการสนทนาแล้ว' : lastMessage),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isUnread ? Colors.black87 : Colors.grey,
                      fontWeight: isUnread ? FontWeight.w500 : FontWeight.normal),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        chatId: chat['id'] as String,
                        petId: chat['petId'] as String,
                        dogName: chatDogName,
                        otherUserName: otherName,
                        otherUserAvatar: chat['otherUserAvatarUrl'] as String? ?? '',
                        otherUserId: chat['otherUserId'] as String? ?? '',
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
