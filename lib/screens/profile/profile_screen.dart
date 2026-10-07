import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/mock_data.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/users_service.dart';
import '../../widgets/pet_avatar.dart';
import '../../widgets/province_picker.dart';
import '../../widgets/tag_selector.dart';
import '../chat/chat_inbox_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/field_error.dart';
import '../../widgets/paw_loader.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.active = true});

  /// แท็บนี้กำลังแสดงอยู่ไหม (หน้าหลักใช้ IndexedStack จึงไม่ถูกสร้างใหม่ตอนสลับแท็บ)
  final bool active;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with FieldErrors {
  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ออกจากแท็บโปรไฟล์ → ล้างข้อความเตือนค้าง กลับมาใหม่จะไม่เห็นของเก่า
    if (oldWidget.active && !widget.active) clearFieldErrors();
  }

  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;

  Map<String, dynamic> _profile = Map<String, dynamic>.from(currentUserProfile);

  final TextEditingController phoneController = TextEditingController();
  final TextEditingController lineController = TextEditingController();
  final TextEditingController fbController = TextEditingController();

  String currentProvince = thaiProvinces.first;
  String currentHomeType = homeTypes.first;
  List<String> selectedTraitIds = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// โหลดโปรไฟล์เต็มจาก backend ทุกครั้งที่เปิดหน้า — ไม่พึ่งค่าที่ค้างอยู่ใน
  /// currentUserProfile (mock Map) เพราะมันจะไม่ถูกอัปเดตหลัง restore session
  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final profile = await UsersService.instance.getMe();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        phoneController.text = (profile['phone'] as String?) ?? '';
        lineController.text = (profile['lineId'] as String?) ?? '';
        fbController.text = (profile['fbLink'] as String?) ?? '';
        currentProvince = thaiProvinces.contains(profile['province'])
            ? profile['province'] as String
            : thaiProvinces.first;
        currentHomeType = homeTypes.contains(profile['homeType'])
            ? profile['homeType'] as String
            : homeTypes.first;
        selectedTraitIds = List<String>.from(profile['traits'] ?? []);
      });
      currentUserProfile
        ..['name'] = profile['name']
        ..['email'] = profile['email'];
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: AppTheme.snackDuration,
          content: Text('โหลดโปรไฟล์ไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// ตอนยังไม่กดแก้ไข ช่องพวกนี้จะกดไม่ได้ ถ้าผู้ใช้แตะจะนึกว่าแอปค้าง
  /// เลยดักการแตะไว้แล้วบอกให้กดปุ่มแก้ไขก่อน
  Widget _lockedHint(Widget child, String key) {
    if (_isEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [child, InlineError(fieldError(key))],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showFieldError(
              key, 'กดปุ่ม "แก้ไขข้อมูล" ด้านบนก่อน จึงจะเปลี่ยนข้อมูลได้'),
          child: AbsorbPointer(child: child),
        ),
        InlineError(fieldError(key)),
      ],
    );
  }

  void toggleTrait(String tagId) {
    if (!_isEditing) return;
    // ตอนสร้างโปรไฟล์บังคับอย่างน้อย 1 แท็ก — ตอนแก้ไขก็ต้องเอาออกจนหมดไม่ได้
    if (selectedTraitIds.length == 1 && selectedTraitIds.contains(tagId)) {
      showFieldError('traits', _minTraitMessage);
      return;
    }
    clearFieldErrors();
    setState(() {
      if (selectedTraitIds.contains(tagId)) {
        selectedTraitIds.remove(tagId);
      } else {
        selectedTraitIds.add(tagId);
      }
    });
  }

  static const _minTraitMessage =
      'ต้องเลือกไลฟ์สไตล์ / นิสัยของคุณไว้อย่างน้อย 1 แท็ก';

  Future<void> saveProfileData() async {
    clearFieldErrors();
    // บัญชีเก่าที่ยังไม่มีแท็กเลย ต้องเลือกก่อนถึงจะบันทึกได้
    if (selectedTraitIds.isEmpty) {
      showFieldError('traits', _minTraitMessage);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final updated = await UsersService.instance.updateMe({
        'province': currentProvince,
        'phone': phoneController.text,
        'lineId': lineController.text,
        'fbLink': fbController.text,
        'homeType': currentHomeType,
        'traits': selectedTraitIds,
      });
      AuthService.instance.rememberProfile(updated);
      if (!mounted) return;
      setState(() {
        _profile = updated;
        _isEditing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          shape: AppTheme.snackSuccessShape,
          content: Text('บันทึกข้อมูลโปรไฟล์เรียบร้อยแล้ว!',
              style: AppTheme.snackSuccessText),
          duration: Duration(seconds: 2)));
    } catch (_) {
      if (!mounted) return;
      showFieldError('submit', 'บันทึกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void startEditing() {
    clearFieldErrors();
    setState(() {
      _isEditing = true;
    });
  }

  Future<void> _pickAndUploadImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    try {
      final url = await AuthService.instance.uploadProfileImage(bytes,
          contentType: file.mimeType ?? 'image/jpeg');
      if (!mounted) return;
      setState(() => _profile['profileImageUrl'] = url);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          shape: AppTheme.snackSuccessShape,
          duration: AppTheme.snackDuration,
          content:
              Text('อัปเดตรูปโปรไฟล์แล้ว', style: AppTheme.snackSuccessText)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: AppTheme.snackDuration,
          content: Text('อัปโหลดรูปไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')));
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ออกจากระบบ'),
        content: const Text('ต้องการออกจากระบบใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ออกจากระบบ',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService.instance.signOut();
      // AuthGate จะสลับกลับไปหน้า LoginScreen ให้อัตโนมัติ
    }
  }

  /// เปิดกล่องข้อความทั้งหมดของฉัน (ทุกสัตว์เลี้ยง)
  void _openInbox() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ChatInboxScreen(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('โปรไฟล์ของฉัน',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.textDark)),
          backgroundColor: AppColors.appBar,
          elevation: 0,
          centerTitle: true,
        ),
        body: const AppPageFrame(
            maxWidth: AppLayout.formWidth, child: Center(child: PawLoader())),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('โปรไฟล์ของฉัน',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.textDark)),
        backgroundColor: AppColors.appBar,
        elevation: 0,
        centerTitle: true,
        // badge แจ้งเตือนแชทที่ AppBar
        actions: [
          StreamBuilder<int>(
            stream: ChatService.instance.unreadChatCountStream(),
            builder: (context, snapshot) {
              final totalUnread = snapshot.data ?? 0;
              if (totalUnread == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: GestureDetector(
                  onTap: _openInbox,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.notifications,
                          color: AppColors.primary, size: 28),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: AppColors.danger,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$totalUnread',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: AppColors.danger),
            tooltip: 'ออกจากระบบ',
          ),
        ],
      ),
      body: AppPageFrame(
          maxWidth: AppLayout.formWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    PetAvatar(
                      imageUrl: _profile['profileImageUrl'],
                      radius: 60,
                      icon: Icons.person,
                    ),
                    if (_isEditing)
                      GestureDetector(
                        onTap: _pickAndUploadImage,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.white, size: 20),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(_profile['name'] ?? '',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark)),
                Text(_profile['email'] ?? '',
                    style: const TextStyle(
                        fontFamily: 'Sarabun',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark)),
                Chip(
                  avatar: const Icon(Icons.location_on,
                      color: Colors.white, size: 16),
                  label: Text(_profile['province'] ?? '-',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  backgroundColor: AppColors.primarySoft,
                  side: BorderSide.none,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : (_isEditing ? saveProfileData : startEditing),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: PawSpinner(color: Colors.white),
                          )
                        : Icon(_isEditing ? Icons.save : Icons.edit),
                    label: Text(_isEditing ? 'บันทึกข้อมูล' : 'แก้ไขข้อมูล',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.control)),
                      elevation: 0,
                    ),
                  ),
                ),
                InlineError(fieldError('submit')),

                // ===== แบนเนอร์แชทรอการตอบกลับ =====
                StreamBuilder<int>(
                  stream: ChatService.instance.unreadChatCountStream(),
                  builder: (context, snapshot) {
                    final totalUnread = snapshot.data ?? 0;
                    if (totalUnread == 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: GestureDetector(
                        onTap: _openInbox,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.chat,
                                    color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'มีข้อความใหม่ $totalUnread ข้อความ',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          color: AppColors.textDark),
                                    ),
                                    const Text(
                                      'มีคนสนใจรับเลี้ยงสัตว์เลี้ยงของคุณ กดเพื่อดูแชท',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.black54),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppColors.primary),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),
                SectionCard(
                  title: 'ไลฟ์สไตล์ / นิสัยของคุณ',
                  children: [
                    _lockedHint(
                        TagSelector(
                          selectedIds: selectedTraitIds,
                          onToggle: toggleTrait,
                          enabled: _isEditing,
                          backgroundColor: AppColors.background,
                        ),
                        'traits'),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'ข้อมูลการติดต่อ',
                  children: [
                    TextField(
                      controller: phoneController,
                      enabled: _isEditing,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                          labelText: 'เบอร์โทรศัพท์',
                          prefixIcon: const Icon(Icons.phone),
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card))),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: lineController,
                      enabled: _isEditing,
                      decoration: InputDecoration(
                          labelText: 'LINE ID',
                          prefixIcon: const Icon(Icons.chat_bubble_outline),
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card))),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: fbController,
                      enabled: _isEditing,
                      decoration: InputDecoration(
                          labelText: 'ชื่อ Facebook',
                          prefixIcon: const Icon(Icons.facebook),
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card))),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'ข้อมูลสถานที่',
                  children: [
                    ProvinceField(
                      value: currentProvince,
                      labelText: 'จังหวัดที่อยู่ปัจจุบัน',
                      enabled: _isEditing,
                      onChanged: (val) => setState(() => currentProvince = val),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  title: 'ข้อมูลเสริมคัดกรองผู้เลี้ยง',
                  children: [
                    IgnorePointer(
                        ignoring: !_isEditing,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: currentHomeType,
                          disabledHint: Text(currentHomeType),
                          // ตอนยังไม่กดแก้ไข ให้ดูเป็นช่องปิดแบบเดียวกับช่องอื่น (ขอบจาง)
                          decoration: InputDecoration(
                              labelText: 'ประเภทที่พักอาศัย',
                              enabled: _isEditing),
                          items: homeTypes
                              .map((h) =>
                                  DropdownMenuItem(value: h, child: Text(h)))
                              .toList(),
                          onChanged: _isEditing
                              ? (val) => setState(() => currentHomeType = val!)
                              : null,
                        )),
                  ],
                ),
              ],
            ),
          )),
    );
  }
}
