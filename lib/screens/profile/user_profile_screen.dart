import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/pet_service.dart';
import '../../services/users_service.dart';
import '../../utils/pet_tags.dart';
import '../../widgets/pet_avatar.dart';
import '../../widgets/pet_network_image.dart';
import '../detail/pet_detail_screen.dart';
import '../../theme/app_theme.dart';

/// หน้าโปรไฟล์ของผู้ใช้คนอื่น เปิดได้จากประกาศสัตว์เลี้ยงหรือจากห้องแชท
///
/// ดึงประกาศของเจ้าของเองจาก GET /pets/by-owner/:id ไม่รับส่งเข้ามาจากหน้าที่
/// เรียก เพราะหน้าที่เรียกแต่ละหน้ารู้จักประกาศไม่เท่ากัน (เปิดจากห้องแชทจะไม่รู้
/// ประกาศอื่นของเขาเลย) ทำให้เห็นข้อมูลไม่ตรงกันแล้วแต่ทางที่กดเข้ามา
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.uid,
    this.fallbackName = 'เจ้าของ',
  });

  final String uid;
  final String fallbackName;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _ownerPets = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final profile = await UsersService.instance.getPublicProfile(widget.uid);
      final pets = await PetService.instance.byOwner(widget.uid);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _ownerPets = pets;
      });
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  AppBar _appBar() => AppBar(
        title: const Text('โปรไฟล์ผู้ใช้',
            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textDark)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppColors.primary),
        elevation: 1,
        centerTitle: true,
      );

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _appBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_hasError || _profile == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: _appBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('โหลดโปรไฟล์ไม่สำเร็จ', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('ลองใหม่')),
            ],
          ),
        ),
      );
    }
    return _scaffold(context, _profile!, _ownerPets);
  }

  Widget _scaffold(
      BuildContext context, Map<String, dynamic> profile, List<Map<String, dynamic>> pets) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _appBar(),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _header(profile),
          const SizedBox(height: 24),
          _sectionTitle('ไลฟ์สไตล์ / นิสัย'),
          const SizedBox(height: 12),
          _traits(profile),
          const SizedBox(height: 24),
          _sectionTitle('ข้อมูลการติดต่อ'),
          const SizedBox(height: 12),
          _contact(context, profile),
          const Divider(height: 40, color: Colors.black12),
          Text('ประกาศหาบ้านของผู้ใช้นี้ (${pets.length})',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textDark)),
          const SizedBox(height: 16),
          if (pets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('ยังไม่มีประกาศอื่นให้ดู', style: TextStyle(color: Colors.black45)),
              ),
            )
          else
            ...pets.map((pet) => _petTile(context, pet, pets)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
      );

  /// ข้อความแทนช่องที่เจ้าของยังไม่ได้กรอก — ต้องแสดงหัวข้อไว้เสมอ ไม่ใช่ซ่อนทั้งบล็อก
  /// ไม่งั้นโปรไฟล์ของคนที่ยังกรอกไม่ครบจะว่างเปล่าจนดูเหมือนหน้าจอพัง
  Widget _notFilled() => const Text('ยังไม่ได้ระบุ',
      style: TextStyle(color: Colors.black38, fontStyle: FontStyle.italic));

  Widget _header(Map<String, dynamic> profile) {
    final name = (profile['displayName'] as String?)?.trim();
    final province = (profile['province'] as String?)?.trim() ?? '';
    return Column(
      children: [
        PetAvatar(imageUrl: profile['profileImageUrl'] as String?, radius: 48, icon: Icons.person),
        const SizedBox(height: 12),
        Text(name == null || name.isEmpty ? widget.fallbackName : name,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 8),
        Chip(
          avatar: const Icon(Icons.location_on, color: Colors.white, size: 16),
          label: Text(province.isEmpty ? 'ยังไม่ได้ระบุจังหวัด' : province,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.primarySoft,
          side: BorderSide.none,
        ),
      ],
    );
  }

  Widget _traits(Map<String, dynamic> profile) {
    final ids = (profile['traits'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (ids.isEmpty) return _notFilled();
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: tagLabels(ids)
          .map((label) => Chip(
                label: Text(label,
                    style: const TextStyle(color: AppColors.textDark, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.white,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
              ))
          .toList(),
    );
  }

  void _copyToClipboard(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(shape: AppTheme.snackSuccessShape, content: Text('คัดลอก $label แล้ว', style: AppTheme.snackSuccessText), duration: const Duration(seconds: 1)));
  }

  /// ไม่โชว์เบอร์โทรในหน้าสาธารณะ — backend ก็ไม่ส่ง phone มาให้อยู่แล้ว
  /// (ดู getPublic() ใน users.service.ts และคอมเมนต์บนตาราง user_contacts)
  Widget _contact(BuildContext context, Map<String, dynamic> profile) {
    final lineId = (profile['lineId'] as String?)?.trim() ?? '';
    final fbLink = (profile['fbLink'] as String?)?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        children: [
          _contactRow(
            icon: Icons.chat_bubble_outline,
            label: 'LINE ID',
            value: lineId,
            onCopy: () => _copyToClipboard(context, 'LINE ID', lineId),
          ),
          const Divider(height: 1, color: Colors.black12),
          _contactRow(
            icon: Icons.facebook,
            label: 'ชื่อ Facebook',
            value: fbLink,
            onCopy: () => _copyToClipboard(context, 'ชื่อ Facebook', fbLink),
          ),
        ],
      ),
    );
  }

  Widget _contactRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.black45)),
                value.isEmpty
                    ? _notFilled()
                    : Text(value, style: const TextStyle(fontSize: 15)),
              ],
            ),
          ),
          // ไม่มีข้อมูลก็ไม่มีอะไรให้คัดลอก ปุ่มจึงต้องกดไม่ได้
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'คัดลอก',
            visualDensity: VisualDensity.compact,
            onPressed: value.isEmpty ? null : onCopy,
          ),
        ],
      ),
    );
  }

  Widget _petTile(BuildContext context, Map<String, dynamic> pet, List<Map<String, dynamic>> pets) {
    final isAdopted = pet['status'] == 'ถูกรับเลี้ยงแล้ว';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: PetNetworkImage(imageUrl: pet['imageUrl'] as String?, width: 56, height: 56, iconSize: 28),
        ),
        title: Text(pet['name']?.toString() ?? 'ไม่ระบุชื่อ',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
            '${pet['breed'] ?? '-'} · ${pet['age'] ?? '-'}${isAdopted ? ' · ถูกรับเลี้ยงแล้ว' : ''}',
            style: const TextStyle(fontSize: 13)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.primary),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PetDetailScreen(
              dog: pet,
              isMyPost: false,
              isFavorited: false,
              onToggleFavorite: () {},
            ),
          ),
        ),
      ),
    );
  }
}
