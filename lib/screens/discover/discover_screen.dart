import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../../utils/pet_species.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/swipeable_card.dart';
import '../chat/chat_screen.dart';
import '../../theme/app_theme.dart';

class DiscoverScreen extends StatelessWidget {
  final List<Map<String, dynamic>> dogs;
  final Function(Map<String, dynamic>) onLike;
  final Function(Map<String, dynamic>) onPass;
  final VoidCallback onUndoPass;
  final bool canUndo;
  final List<Map<String, dynamic>> likedDogs;
  final Function(Map<String, dynamic>) onToggleFavorite;

  /// ตัวกรองชนิดสัตว์ ('' = ทั้งหมด) — เปลี่ยนแล้ว MainScreen โหลดเด็คใหม่ตามชนิดนั้น
  final String speciesFilter;
  final ValueChanged<String> onSpeciesFilterChanged;

  const DiscoverScreen({
    super.key,
    required this.dogs,
    required this.onLike,
    required this.onPass,
    required this.onUndoPass,
    required this.canUndo,
    required this.likedDogs,
    required this.onToggleFavorite,
    this.speciesFilter = '',
    required this.onSpeciesFilterChanged,
  });

  Future<void> _handleLikeAndChat(
      BuildContext context, Map<String, dynamic> dog) async {
    onLike(dog);

    final ownerId = dog['ownerId'] as String?;
    final myUid = AuthService.instance.currentUser?.uid;
    if (ownerId == null || ownerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: AppTheme.snackDuration, 
          content: Text('สัตว์เลี้ยงตัวอย่างนี้ยังไม่มีเจ้าของจริงในระบบให้แชทด้วย')));
      return;
    }
    if (ownerId == myUid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(duration: AppTheme.snackDuration, content: Text('นี่คือประกาศของคุณเอง')));
      return;
    }
    final ownerName = dog['ownerName'] as String? ?? 'เจ้าของ';

    // ยังไม่สร้างห้องแชทตรงนี้ — แค่พาไปหน้าคุย ห้องจะถูกสร้างจริงตอนกดส่ง
    // ข้อความแรกใน ChatScreen เท่านั้น (chatId: null) ตรงตามกฎ SKILL.md ที่ว่า
    // "การกดถูกใจต้องไม่สร้างห้องแชทอัตโนมัติ"
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          petId: dog['id'] as String,
          dogName: dog['name'] as String,
          otherUserName: ownerName,
          otherUserId: ownerId,
        ),
      ),
    );
  }

  Future<void> _handleReport(
      BuildContext context, Map<String, dynamic> dog) async {
    final petId = dog['id'] as String;
    final ownerId = dog['ownerId'] as String?;
    await reportWithDialog(
      context,
      title: 'รายงานประกาศนี้',
      send: (reason, detail) =>
          ReportService.instance.reportPet(petId, reason: reason, detail: detail),
      blockUserId: (ownerId == null || ownerId.isEmpty) ? null : ownerId,
      blockUserName: dog['ownerName'] as String? ?? 'เจ้าของประกาศนี้',
      // บล็อกแล้วถือว่าปัดทิ้ง: ตัวที่รายงานกับตัวอื่นของเจ้าของเดียวกันที่ค้างในเด็ค
      // (server เองก็ซ่อนประกาศของคนที่บล็อกอยู่แล้ว แต่เด็คในเครื่องดึงมาไว้ก่อนหน้า)
      onBlocked: () {
        final sameOwner = [for (final d in dogs) if (d['ownerId'] == ownerId) d];
        for (final d in sameOwner) {
          onPass(d);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PetPaws',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.primary, shadows: AppTheme.outline)),
        backgroundColor: AppColors.appBar,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            key: const ValueKey('species-filter'),
            tooltip: 'กรองชนิดสัตว์',
            // สีส้ม = กำลังกรองอยู่ เทา = ดูทั้งหมด
            icon: Icon(Icons.filter_list,
                color: speciesFilter.isEmpty ? Colors.grey.shade600 : AppColors.primary),
            onPressed: () => _pickSpecies(context),
          ),
        ],
      ),
      body: _deck(context),
    );
  }

  Future<void> _pickSpecies(BuildContext context) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _SpeciesPickerDialog(current: speciesFilter),
    );
    if (picked != null) onSpeciesFilterChanged(picked);
  }

  Widget _deck(BuildContext context) {
    return dogs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('ขอบคุณที่ทำให้สัตว์ทุกตัวมีบ้านที่อบอุ่น!',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                  if (canUndo) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: onUndoPass,
                      icon: const Icon(Icons.replay),
                      label: const Text('ลองดูสัตว์เลี้ยงอีกครั้ง'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primarySoft,
                          foregroundColor: AppColors.onPrimary),
                    )
                  ]
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SwipeableCard(
                      dog: dogs.first,
                      onLike: () => onLike(dogs.first),
                      onPass: () => onPass(dogs.first),
                      likedDogs: likedDogs,
                      onToggleFavorite: onToggleFavorite,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton(
                        heroTag: "btn_report",
                        tooltip: 'รายงาน',
                        onPressed: () => _handleReport(context, dogs.first),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.grey.shade500,
                        mini: true,
                        elevation: 2,
                        child: const Icon(Icons.flag_outlined, size: 24),
                      ),
                      const SizedBox(width: 24),
                      FloatingActionButton(
                        heroTag: "btn_pass",
                        onPressed: () => onPass(dogs.first),
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.danger,
                        elevation: 2,
                        child: const Icon(Icons.close, size: 30),
                      ),
                      const SizedBox(width: 24),
                      FloatingActionButton(
                        heroTag: "btn_undo",
                        onPressed: canUndo ? onUndoPass : null,
                        backgroundColor:
                            canUndo ? Colors.white : Colors.grey[200],
                        foregroundColor: AppColors.primarySoft,
                        mini: true,
                        elevation: canUndo ? 2 : 0,
                        child: const Icon(Icons.replay, size: 24),
                      ),
                      const SizedBox(width: 24),
                      FloatingActionButton(
                        heroTag: "btn_like",
                        onPressed: () => onLike(dogs.first),
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.success,
                        elevation: 2,
                        child: const Icon(Icons.favorite, size: 30),
                      ),
                      const SizedBox(width: 24),
                      FloatingActionButton(
                        heroTag: "btn_like_chat",
                        tooltip: 'ถูกใจและแชท',
                        onPressed: () =>
                            _handleLikeAndChat(context, dogs.first),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.pink.shade300,
                        mini: true,
                        elevation: 2,
                        child: const Icon(Icons.chat_bubble, size: 24),
                      ),
                    ],
                  ),
                )
              ],
            );
  }
}

/// เลือกชนิดสัตว์: มีช่องพิมพ์ค้นหา แล้วกดเลือกจากรายการ ('' = ทั้งหมด)
class _SpeciesPickerDialog extends StatefulWidget {
  const _SpeciesPickerDialog({required this.current});

  final String current;

  @override
  State<_SpeciesPickerDialog> createState() => _SpeciesPickerDialogState();
}

class _SpeciesPickerDialogState extends State<_SpeciesPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final options = <String, String>{'': 'ทั้งหมด', ...petSpeciesLabels};
    final shown = options.entries.where((e) => e.value.contains(_query.trim())).toList();
    return AlertDialog(
      title: const Text('กรองชนิดสัตว์'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('species-search'),
              autofocus: true,
              decoration: const InputDecoration(hintText: 'พิมพ์ค้นหา', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in shown)
                    ListTile(
                      key: ValueKey('species-option-${e.key.isEmpty ? 'all' : e.key}'),
                      dense: true,
                      title: Text(e.value),
                      trailing: e.key == widget.current
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                      onTap: () => Navigator.pop(context, e.key),
                    ),
                  if (shown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('ไม่พบชนิดสัตว์นี้', style: TextStyle(color: Colors.grey)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
