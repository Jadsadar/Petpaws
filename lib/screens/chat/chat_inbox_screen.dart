import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/chat_service.dart';
import '../../widgets/pet_avatar.dart';
import 'chat_screen.dart';
import '../../theme/app_theme.dart';

class ChatInboxScreen extends StatefulWidget {
  /// ถ้าระบุ = โหมดเจ้าของดูแชทของ "ประกาศนี้" ตัวเดียว (กรองด้วยชื่อสัตว์
  /// เพราะ ChatInboxScreen เดิมออกแบบมารับแค่ dogName ไม่ใช่ petId — ยังมีบั๊กเดิม
  /// ที่สัตว์ชื่อซ้ำกันจะกรองปนกันได้ ดูรายละเอียดใน ROADMAP.md)
  /// ถ้าไม่ระบุ (null) = โหมดข้อความทั้งหมดของฉัน
  final String? dogName;

  /// false = แท็บนี้ไม่ได้เปิดอยู่ (อยู่ใน IndexedStack) — ใช้ปิดโหมดเลือกเมื่อสลับไปแท็บอื่น
  final bool active;

  const ChatInboxScreen({super.key, this.dogName, this.active = true});

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

  /// โหมดเลือก (ปุ่ม "เลือก" มุมขวาบน เหมือนหน้ารายการที่สนใจ) — ติ๊กหลายแชทแล้วลบทีเดียว
  /// ลบแชท = ซ่อนเฉพาะฝั่งเรา อีกฝ่ายยังเห็น
  bool _selecting = false;
  final Set<String> _selected = {};
  List<String> _visibleIds = [];

  @override
  void didUpdateWidget(ChatInboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active && _selecting) _exitSelecting();
  }

  void _exitSelecting() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _toggleAll() => setState(() {
        if (_selected.length == _visibleIds.length) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(_visibleIds);
        }
      });

  void _toggleSelected(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  Future<void> _deleteSelected() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบแชท'),
        content: Text(
            'แชท ${_selected.length} รายการที่เลือกจะหายจากรายการของคุณ (อีกฝ่ายยังเห็นอยู่)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (ok != true) return;
    var failed = false;
    for (final id in _selected.toList()) {
      try {
        await ChatService.instance.hideChat(id);
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    if (failed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(duration: AppTheme.snackDuration, content: Text('ลบแชทบางรายการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')));
    }
    _exitSelecting();
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

  Widget _searchButton() => IconButton(
        key: const ValueKey('inbox-search-toggle'),
        tooltip: _search == null ? 'ค้นหาแชท' : 'ปิดการค้นหา',
        icon: Icon(_search == null ? Icons.search : Icons.close),
        onPressed: () => setState(() {
          _search = _search == null ? '' : null;
          _searchController.clear();
        }),
      );

  @override
  Widget build(BuildContext context) {
    // เปิดแบบแท็บ (ไม่มีปุ่มย้อนกลับ) → ค้นหาอยู่ซ้าย ถ้าถูก push มาจะเหลือปุ่มย้อนกลับซ้าย ค้นหาไว้ขวา
    final canPop = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                key: const ValueKey('inbox-cancel-select'),
                icon: const Icon(Icons.close, color: AppColors.primary),
                onPressed: _exitSelecting)
            : (canPop ? null : _searchButton()),
        title: _selecting
            ? Text('เลือกแล้ว ${_selected.length} แชท',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.textDark, fontSize: 18))
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('กล่องข้อความ',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.textDark, fontSize: 18)),
            if (widget.dogName != null)
              Text('สัตว์เลี้ยง: ${widget.dogName}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textMuted, shadows: [])),
          ],
        ),
        backgroundColor: AppColors.appBar,
        iconTheme: const IconThemeData(color: AppColors.primary),
        elevation: 1,
        actions: [
          if (_selecting)
            TextButton(
              key: const ValueKey('inbox-select-all'),
              onPressed: _toggleAll,
              child: Text(_selected.length == _visibleIds.length
                  ? 'ไม่เลือกเลย'
                  : 'เลือกทั้งหมด'),
            )
          else ...[
          TextButton(
            key: const ValueKey('inbox-select'),
            onPressed: () => setState(() => _selecting = true),
            child: const Text('เลือก'),
          ),
          if (canPop) _searchButton(),
          ],
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
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ElevatedButton.icon(
                  key: const ValueKey('inbox-delete'),
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                  label: Text('ลบแชท (${_selected.length})'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white),
                ),
              ),
            )
          : null,
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _chatsStream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final chats = [for (final c in all) if (_matches(c, _search ?? '')) c];
          _visibleIds = [for (final c in chats) c['id'] as String];
          if (all.isNotEmpty && chats.isEmpty) {
            return const Center(child: Text('ไม่พบแชทที่ค้นหา', style: TextStyle(color: Colors.grey)));
          }
          if (chats.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: AppColors.mocha),
                  SizedBox(height: 16),
                  Text('ยังไม่มีคนทักมาเลย',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark)),
                  SizedBox(height: 8),
                  Text('แชร์โพสต์เพื่อให้คนรู้จักสัตว์เลี้ยงของคุณมากขึ้น',
                      style: TextStyle(fontSize: 14, color: AppColors.brown)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final chat = chats[index];
              final otherName = chat['otherUserName'] as String? ?? 'ผู้สนใจรับเลี้ยง';
              final chatDogName = chat['petName'] as String? ?? widget.dogName ?? '';
              final lastMessage = chat['lastMessage'] as String? ?? '';
              final unread = (chat['unreadCount'] as num?)?.toInt() ?? 0;
              final isUnread = unread > 0;

              return Card(
                clipBehavior: Clip.antiAlias,
                elevation: 2,
                shadowColor: Colors.black26,
                child: ListTile(
                key: ValueKey('chat-${chat['id']}'),
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
                        child: CircleAvatar(radius: 6, backgroundColor: AppColors.primary),
                      ),
                  ],
                ),
                trailing: _selecting
                    ? Checkbox(
                        key: ValueKey('inbox-check-${chat['id']}'),
                        value: _selected.contains(chat['id']),
                        activeColor: AppColors.primary,
                        onChanged: (_) => _toggleSelected(chat['id'] as String),
                      )
                    : null,
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
                            color: isUnread ? AppColors.textDark : Colors.grey,
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
                      color: isUnread ? AppColors.textDark : AppColors.textMuted,
                      fontWeight: isUnread ? FontWeight.w500 : FontWeight.normal),
                ),
                onTap: () {
                  if (_selecting) {
                    _toggleSelected(chat['id'] as String);
                    return;
                  }
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
              ),
              );
            },
          );
        },
      ),
    );
  }
}
