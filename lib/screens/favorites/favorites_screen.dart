import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../widgets/pet_avatar.dart';
import '../chat/chat_screen.dart';
import '../detail/pet_detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  final List<Map<String, dynamic>> likedDogs;

  /// สลับถูกใจ/เลิกถูกใจของสัตว์ตัวนั้น (MainScreen ยิง API ให้และย้อนกลับเองถ้าล้มเหลว)
  final Function(Map<String, dynamic>) onToggleFavorite;

  const FavoritesScreen({
    super.key,
    required this.likedDogs,
    required this.onToggleFavorite,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> get likedDogs => widget.likedDogs;
  Function(Map<String, dynamic>) get onToggleFavorite =>
      widget.onToggleFavorite;

  /// โหมดเลือก (ปุ่มมุมขวาบน) — เก็บ id ของสัตว์ที่ติ๊กไว้เพื่อเลิกถูกใจทีเดียวหลายตัว
  bool _selecting = false;
  final Set<String> _selected = {};

  void _exitSelecting() => setState(() {
        _selecting = false;
        _selected.clear();
      });

  void _toggleAll() => setState(() {
        final ids = likedDogs.map((d) => d['id'] as String).toSet();
        if (_selected.length == ids.length) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(ids);
        }
      });

  void _toggleSelected(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  Future<void> _unlikeSelected() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เลิกถูกใจ'),
        content: Text(
            'เลิกถูกใจสัตว์เลี้ยง ${_selected.length} ตัวที่เลือกใช่หรือไม่?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('เลิกถูกใจ')),
        ],
      ),
    );
    if (ok != true) return;
    // คัดลอกก่อนวน เพราะ onToggleFavorite แก้ลิสต์ต้นทางระหว่างทาง
    final targets =
        likedDogs.where((d) => _selected.contains(d['id'])).toList();
    for (final dog in targets) {
      onToggleFavorite(dog);
    }
    if (mounted) _exitSelecting();
  }

  Future<void> _chatWithOwner(
      BuildContext context, Map<String, dynamic> dog) async {
    final ownerId = dog['ownerId'] as String?;
    final myUid = AuthService.instance.currentUser?.uid;
    if (ownerId == null || ownerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'สัตว์เลี้ยงตัวอย่างนี้ยังไม่มีเจ้าของจริงในระบบให้แชทด้วย')));
      return;
    }
    if (ownerId == myUid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('นี่คือประกาศของคุณเอง')));
      return;
    }
    final ownerName = dog['ownerName'] as String? ?? 'เจ้าของ';

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => ChatScreen(
                  petId: dog['id'] as String,
                  dogName: dog['name'] as String,
                  otherUserName: ownerName,
                  otherUserId: ownerId,
                )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            _selecting ? 'เลือกแล้ว ${_selected.length} ตัว' : 'รายการที่สนใจ',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFFFF9E68))),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        leading: _selecting
            ? IconButton(
                key: const ValueKey('fav-cancel-select'),
                icon: const Icon(Icons.close, color: Color(0xFFFF9E68)),
                onPressed: _exitSelecting)
            : null,
        actions: [
          if (_selecting)
            TextButton(
              key: const ValueKey('fav-select-all'),
              onPressed: _toggleAll,
              child: Text(_selected.length == likedDogs.length
                  ? 'ไม่เลือกเลย'
                  : 'เลือกทั้งหมด'),
            )
          else if (likedDogs.isNotEmpty)
            TextButton(
              key: const ValueKey('fav-select'),
              onPressed: () => setState(() => _selecting = true),
              child: const Text('เลือก'),
            ),
        ],
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ElevatedButton.icon(
                  key: const ValueKey('fav-unlike'),
                  onPressed: _selected.isEmpty ? null : _unlikeSelected,
                  icon: const Icon(Icons.heart_broken),
                  label: Text('เลิกถูกใจ (${_selected.length})'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white),
                ),
              ),
            )
          : null,
      body: likedDogs.isEmpty
          ? const Center(
              child: Text('ยังไม่มีสัตว์เลี้ยงที่ถูกใจเลย',
                  style: TextStyle(fontSize: 16, color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: likedDogs.length,
              itemBuilder: (context, index) {
                final dog = likedDogs[index];
                final id = dog['id'] as String;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: PetAvatar(
                      imageUrl: dog['imageUrl'],
                      radius: 30,
                    ),
                    title: Text(dog['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('${dog['province']} • ${dog['breed']}'),
                    trailing: _selecting
                        ? Checkbox(
                            key: ValueKey('fav-check-$id'),
                            value: _selected.contains(id),
                            activeColor: const Color(0xFFFF9E68),
                            onChanged: (_) => _toggleSelected(id),
                          )
                        : ElevatedButton.icon(
                            onPressed: () => _chatWithOwner(context, dog),
                            icon: const Icon(Icons.chat, size: 18),
                            label: const Text('ทักแชท'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFB085),
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                          ),
                    onTap: _selecting
                        ? () => _toggleSelected(id)
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => PetDetailScreen(
                                      dog: dog,
                                      isMyPost: false,
                                      isFavorited: likedDogs
                                          .any((d) => d['id'] == dog['id']),
                                      onToggleFavorite: () =>
                                          onToggleFavorite(dog),
                                    ))),
                  ),
                );
              },
            ),
    );
  }
}
