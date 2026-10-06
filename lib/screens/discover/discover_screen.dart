import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../services/auth_service.dart';
import '../../services/report_service.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/swipeable_card.dart';
import '../chat/chat_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/pop_icon.dart';

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
          otherUserAvatar: dog['ownerAvatar'] as String?,
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
                fontFamily: AppTheme.logoFont,
                fontWeight: FontWeight.bold, color: AppColors.primary, shadows: AppTheme.outline)),
        backgroundColor: AppColors.appBar,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // แถบเลือกชนิดสัตว์ แตะแล้วกรองการ์ดทันที
          SpeciesFilterBar(
            current: speciesFilter,
            onChanged: onSpeciesFilterChanged,
          ),
          Expanded(child: _deck(context)),
        ],
      ),
    );
  }

  Widget _deck(BuildContext context) {
    return dogs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('ขอบคุณที่ทำให้สัตว์ทุกตัวมีบ้านที่อบอุ่น!',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark)),
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
/// แถบหมวดสัตว์เลี้ยงด้านบนหน้าค้นหา: ทั้งหมด / สุนัข / แมว / นก / ปลา / กระต่าย / อื่นๆ
/// แตะแล้วกรองการ์ดทันที (ค่า key ตรงกับ petSpeciesLabels, '' = ทั้งหมด)
class SpeciesFilterBar extends StatelessWidget {
  const SpeciesFilterBar({super.key, required this.current, required this.onChanged});

  final String current;
  final ValueChanged<String> onChanged;

  static const _items = <(String, String, Widget)>[
    ('', 'ทั้งหมด', Icon(Icons.pets, size: 24)),
    ('dog', 'สุนัข', FaIcon(FontAwesomeIcons.dog, size: 22)),
    ('cat', 'แมว', FaIcon(FontAwesomeIcons.cat, size: 22)),
    ('bird', 'นก', FaIcon(FontAwesomeIcons.crow, size: 22)),
    ('fish', 'ปลา', FaIcon(FontAwesomeIcons.fish, size: 22)),
    ('rabbit', 'กระต่าย', Icon(Icons.cruelty_free, size: 24)),
    ('other', 'อื่น ๆ', Icon(Icons.more_horiz, size: 26)),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // ทุกช่องกว้างเท่ากัน เต็มความกว้างบนมือถือ แต่บนจอกว้าง (เว็บ) จำกัดแถบไม่เกิน
      // 760px แล้วจัดกลาง ไม่ให้ช่องใหญ่เกินไป ไอคอน/ตัวอักษร/ความสูงปรับตามขนาดช่อง
      final width = constraints.maxWidth.clamp(0.0, 760.0);
      final narrow = width < 600;
      final gap = narrow ? 6.0 : 12.0, side = narrow ? 10.0 : 16.0;
      final n = _items.length;
      final tile = (width - side * 2 - gap * (n - 1)) / n;
      final scale = (tile / 72).clamp(0.8, 1.2);
      return Center(
        child: SizedBox(
        width: width,
        height: 74 * scale + 18,
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, 10, side, 8),
          child: Row(children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: _tile(_items[i], double.infinity, scale)),
            ],
          ]),
        ),
        ),
      );
    });
  }

  Widget _tile((String, String, Widget) item, double width, double scale) {
    final (key, label, icon) = item;
    final selected = current == key;
    final fg = selected ? AppColors.onPrimary : AppColors.textDark;
    return PressScale(
      child: Material(
      key: ValueKey('species-chip-${key.isEmpty ? 'all' : key}'),
      color: selected ? AppColors.primary : Colors.white,
      elevation: selected ? 2 : 1,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(18 * scale),
      child: InkWell(
        borderRadius: BorderRadius.circular(18 * scale),
        onTap: () => onChanged(key),
        child: SizedBox(
          width: width,
          child: IconTheme(
            data: IconThemeData(color: fg, size: 24 * scale),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ช่องที่เพิ่งถูกเลือก ไอคอนเด้ง+ส่ายครั้งหนึ่ง (key เปลี่ยน = เล่นใหม่)
                Transform.scale(
                    scale: scale,
                    child: selected
                        ? PopIcon(key: ValueKey('pop-$key'), child: icon)
                        : icon),
                SizedBox(height: 4 * scale),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                    style: TextStyle(
                        fontSize: 12 * scale,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: fg)),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
