import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../widgets/pet_avatar.dart';
import 'admin_photos.dart';
import 'admin_widgets.dart';

/// โปรไฟล์ของผู้ใช้ที่ถูกรายงาน (อ่านอย่างเดียว): ข้อมูลบัญชี + ประกาศทั้งหมดพร้อมรูป
/// รวมประกาศที่ถูกลบ/รับเลี้ยงแล้ว เพราะรายงานอาจชี้ไปที่ประกาศที่หายจากเด็คไปแล้ว
/// ไม่แสดงเบอร์โทร/ไลน์ (backend ไม่ส่งมาให้แอดมินตั้งแต่ต้น)
class AdminUserProfileScreen extends StatefulWidget {
  const AdminUserProfileScreen({super.key, required this.userId, required this.fallbackTitle});

  final String userId;

  /// ชื่อที่โชว์บน AppBar ระหว่างรอโหลดโปรไฟล์
  final String fallbackTitle;

  @override
  State<AdminUserProfileScreen> createState() => _AdminUserProfileScreenState();
}

class _AdminUserProfileScreenState extends State<AdminUserProfileScreen> {
  late Future<AdminProfile> _future = AdminService.instance.profile(widget.userId);

  void _reload() => setState(() {
        _future = AdminService.instance.profile(widget.userId);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('โปรไฟล์ · ${widget.fallbackTitle}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: adminOrange, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        iconTheme: const IconThemeData(color: adminOrange),
      ),
      body: FutureBuilder<AdminProfile>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return AdminErrorView(error: snap.error!, onRetry: _reload);
          final p = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ProfileHeader(profile: p),
              const SizedBox(height: 16),
              Text('ประกาศของผู้ใช้นี้ (${p.pets.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (p.pets.isEmpty)
                Text('ยังไม่เคยลงประกาศ', style: TextStyle(color: Colors.grey.shade600))
              else
                for (final pet in p.pets) ...[
                  _PetCard(pet: pet),
                  const SizedBox(height: 8),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final AdminProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final hasAvatar = p.avatarUrl.isNotEmpty;
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  key: const ValueKey('profile-avatar'),
                  onTap: hasAvatar ? () => openAdminPhotoViewer(context, [p.avatarUrl], title: p.title) : null,
                  child: PetAvatar(imageUrl: p.avatarUrl, radius: 36, icon: Icons.person),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('@${p.username}', style: TextStyle(color: Colors.grey.shade700)),
                      Text(p.email, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (p.pendingReportCount > 0)
                  _Tag(text: 'ถูกรายงานรอตรวจ ${p.pendingReportCount} คน', color: Colors.redAccent),
                if (p.isSuspended)
                  _Tag(
                    text: p.suspendedUntil == null ? 'ถูกแบนถาวร' : 'ถูกแบนถึง ${formatDate(p.suspendedUntil)}',
                    color: Colors.grey.shade800,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _InfoRow(label: 'จังหวัด', value: p.province),
            _InfoRow(label: 'ที่อยู่อาศัย', value: p.homeType),
            _InfoRow(label: 'สมัครเมื่อ', value: formatDate(p.createdAt)),
            _InfoRow(label: 'เข้าสู่ระบบล่าสุด', value: p.lastLoginAt == null ? '-' : formatDateTime(p.lastLoginAt)),
            if (p.bio.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('แนะนำตัว', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              Text(p.bio),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

class _PetCard extends StatelessWidget {
  const _PetCard({required this.pet});

  final AdminPet pet;

  @override
  Widget build(BuildContext context) {
    final muted = pet.deleted || pet.status == 'adopted';
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(pet.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                _Tag(text: pet.statusLabel, color: muted ? Colors.grey.shade700 : Colors.green.shade700),
              ],
            ),
            if (pet.location.isNotEmpty)
              Text('${pet.location} · ลงเมื่อ ${formatDate(pet.createdAt)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            if (pet.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(pet.description),
            ],
            const SizedBox(height: 8),
            AdminPhotoStrip(photos: pet.photos, title: pet.name),
          ],
        ),
      ),
    );
  }
}
