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
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _chatsStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final chats = snapshot.data!;
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
