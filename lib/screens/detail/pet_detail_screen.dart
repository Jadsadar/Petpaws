import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../utils/pet_species.dart';
import '../../utils/pet_tags.dart';
import '../../widgets/pet_avatar.dart';
import '../../widgets/pet_network_image.dart';
import '../profile/user_profile_screen.dart';
import '../chat/chat_inbox_screen.dart';
import '../chat/chat_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_heart_button.dart';
import '../chat/media_viewer_screen.dart';

class PetDetailScreen extends StatefulWidget {
  final Map<String, dynamic> dog;
  final bool isMyPost;
  final bool isFavorited;
  final VoidCallback? onToggleFavorite;

  const PetDetailScreen({
    super.key,
    required this.dog,
    this.isMyPost = false,
    this.isFavorited = false,
    this.onToggleFavorite,
  });

  @override
  State<PetDetailScreen> createState() => _PetDetailScreenState();
}

class _PetDetailScreenState extends State<PetDetailScreen> {
  late bool _isFavorited;

  @override
  void initState() {
    super.initState();
    _isFavorited = widget.isFavorited;
  }

  void _handleChatWithOwner() {
    final ownerId = widget.dog['ownerId'] as String?;
    final myUid = AuthService.instance.currentUser?.uid;
    if (ownerId == null || ownerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: AppTheme.snackDuration, 
          content: Text('สัตว์เลี้ยงตัวอย่างนี้ยังไม่มีเจ้าของจริงในระบบให้แชทด้วย')));
      return;
    }
    if (ownerId == myUid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: AppTheme.snackDuration, content: Text('นี่คือประกาศของคุณเอง')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          petId: widget.dog['id'] as String,
          dogName: widget.dog['name'] as String,
          otherUserName: widget.dog['ownerName'] as String? ?? 'เจ้าของ',
          otherUserAvatar: widget.dog['ownerAvatar'] as String?,
          otherUserId: ownerId,
        ),
      ),
    );
  }

  void _handleToggleFavorite() {
    setState(() {
      _isFavorited = !_isFavorited;
    });
    // ไม่มีแจ้งเตือนแล้ว ปุ่มหัวใจมีแอนิเมชันบอกผลแทน
    widget.onToggleFavorite?.call();
  }

  void _openFullImage() {
    final url = widget.dog['imageUrl'] as String?;
    if (url == null || url.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ImageViewerScreen(url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // แตะรูปหรือปุ่มแว่นขยาย → ดูรูปเต็มจอ ซูม/เลื่อนได้
            Stack(
              children: [
                GestureDetector(
                  onTap: _openFullImage,
                  child: PetNetworkImage(
                    imageUrl: widget.dog['imageUrl'],
                    width: double.infinity,
                    height: 400,
                    fit: BoxFit.cover,
                  ),
                ),
                if ((widget.dog['imageUrl'] as String?)?.isNotEmpty ?? false)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      elevation: 3,
                      child: IconButton(
                        key: const ValueKey('detail-zoom'),
                        tooltip: 'ดูรูปเต็ม',
                        icon: const Icon(Icons.zoom_in, color: AppColors.textDark),
                        onPressed: _openFullImage,
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.dog['name'],
                          style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textDark)),
                      Icon(
                          widget.dog['gender'] == 'ผู้'
                              ? Icons.male
                              : Icons.female,
                          size: 32,
                          color: widget.dog['gender'] == 'ผู้'
                              ? Colors.blue.shade300
                              : Colors.pink.shade300),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          color: AppColors.primarySoft),
                      const SizedBox(width: 8),
                      Text(widget.dog['province'],
                          style: TextStyle(
                              fontSize: 18, color: Colors.grey[700])),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _ownerRow(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildInfoCard(Icons.pets, petSpeciesLabel(widget.dog),
                          widget.dog['breed'] ?? 'ไม่ระบุ'),
                      const SizedBox(width: 16),
                      _buildInfoCard(Icons.cake, 'อายุ', widget.dog['age']),
                      const SizedBox(width: 16),
                      _buildInfoCard(Icons.monitor_weight, 'น้ำหนัก',
                          '${widget.dog['weight'] ?? '-'} กก.'),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text('ลักษณะนิสัย',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 8.0,
                    children: (petTagIds(widget.dog).isEmpty
                            ? ['ไม่ระบุ']
                            : tagLabels(petTagIds(widget.dog)))
                        .map((temp) {
                      return Chip(
                        label: Text(temp,
                            style: const TextStyle(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.bold)),
                        backgroundColor: AppColors.background,
                        side: BorderSide.none,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),
                  const Text('เกี่ยวกับฉัน',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87)),
                  const SizedBox(height: 12),
                  Text(widget.dog['story'] ?? 'ยังไม่มีข้อมูลเพิ่มเติม',
                      style: const TextStyle(
                          fontSize: 16, height: 1.5, color: Colors.black87)),
                  const SizedBox(height: 40),

                  // ===== ปุ่มด้านล่าง =====
                  if (widget.isMyPost)
                    // เจ้าของโพสต์ → กดดู inbox แชท
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ChatInboxScreen(dogName: widget.dog['name']),
                          ),
                        ),
                        icon: const Icon(Icons.forum),
                        label: const Text(
                          'ดูแชทจากผู้สนใจรับเลี้ยง',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30)),
                          elevation: 2,
                        ),
                      ),
                    )
                  else
                    // คนอื่น → กดสนใจรับเลี้ยง + ทักแชท
                    Row(
                      children: [
                        // ปุ่ม สนใจ (Favorite)
                        AnimatedHeartButton(
                          isFavorited: _isFavorited,
                          onPressed: _handleToggleFavorite,
                        ),
                        const SizedBox(width: 16),
                        // ปุ่ม ทักแชท
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _handleChatWithOwner,
                            icon: const Icon(Icons.chat),
                            label: const Text(
                              'ทักแชทเจ้าของ',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onPrimary,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30)),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// แถบเจ้าของประกาศ กดแล้วไปดูโปรไฟล์และประกาศตัวอื่นของเขา
  Widget _ownerRow() {
    final ownerId = widget.dog['ownerId'] as String?;
    final ownerName = widget.dog['ownerName'] as String? ?? 'เจ้าของ';
    if (ownerId == null || ownerId.isEmpty) return const SizedBox.shrink();

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.card),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(
            uid: ownerId,
            fallbackName: ownerName,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.card)),
        child: Row(
          children: [
            const PetAvatar(imageUrl: null, radius: 20, icon: Icons.person),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ผู้ลงประกาศ',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  Text(ownerName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Text('ดูโปรไฟล์',
                style: TextStyle(
                    color: AppColors.textDark, fontWeight: FontWeight.bold)),
            const Icon(Icons.chevron_right, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppRadius.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primarySoft),
            const SizedBox(height: 8),
            Text(title,
                style: const TextStyle(color: Colors.black54, fontSize: 14)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textDark),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
