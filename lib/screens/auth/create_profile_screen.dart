import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/mock_data.dart';
import '../../services/auth_service.dart';
import '../../widgets/province_picker.dart';
import '../../widgets/tag_selector.dart';
import '../../theme/app_theme.dart';
import '../../widgets/field_error.dart';
import '../../widgets/paw_loader.dart';

/// บังคับให้กรอกโปรไฟล์หลังล็อกอินครั้งแรก (บัญชีที่ยังไม่มี displayName)
/// ไม่มีปุ่มย้อนกลับ เพราะเป็นขั้นตอนบังคับก่อนเข้าใช้งานแอป
class CreateProfileScreen extends StatefulWidget {
  const CreateProfileScreen({super.key});

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen>
    with FieldErrors {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController lineController = TextEditingController();
  final TextEditingController fbController = TextEditingController();

  String selectedProvince = thaiProvinces.first;
  String selectedHomeType = homeTypes.first;
  final List<String> selectedTraitIds = [];
  bool _isSaving = false;

  Uint8List? _pickedImageBytes;
  String _pickedImageContentType = 'image/jpeg';

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedImageBytes = bytes;
      _pickedImageContentType = file.mimeType ?? 'image/jpeg';
    });
  }

  void _toggleTrait(String tagId) {
    setState(() {
      if (selectedTraitIds.contains(tagId)) {
        selectedTraitIds.remove(tagId);
      } else {
        selectedTraitIds.add(tagId);
      }
    });
  }

  Future<void> _saveProfile() async {
    clearFieldErrors();
    final name = nameController.text.trim();
    if (name.isEmpty) {
      showFieldError('name', 'กรุณากรอกชื่อผู้ใช้ / ชื่อเล่น');
      return;
    }
    // เบอร์ไม่บังคับ แต่ถ้ากรอกต้องครบ 10 หลัก (ช่องรับเฉพาะตัวเลข สูงสุด 10 หลักอยู่แล้ว)
    final phone = phoneController.text.trim();
    if (phone.isNotEmpty && phone.length != 10) {
      showFieldError('phone', 'กรุณากรอกเบอร์โทรศัพท์ให้ครบ 10 หลัก');
      return;
    }
    if (selectedTraitIds.isEmpty) {
      showFieldError(
          'traits', 'กรุณาเลือกไลฟ์สไตล์ / นิสัยของคุณอย่างน้อย 1 อย่าง');
      return;
    }

    setState(() => _isSaving = true);
    try {
      String? imageUrl;
      if (_pickedImageBytes != null) {
        imageUrl = await AuthService.instance.uploadProfileImage(
          _pickedImageBytes!,
          contentType: _pickedImageContentType,
        );
      }
      await AuthService.instance.completeProfile(
        displayName: name,
        extraFields: {
          'province': selectedProvince,
          'phone': phone,
          'lineId': lineController.text.trim(),
          'fbLink': fbController.text.trim(),
          'homeType': selectedHomeType,
          'traits': selectedTraitIds,
          if (imageUrl != null) 'profileImageUrl': imageUrl,
        },
      );
      currentUserProfile['name'] = name;
      currentUserProfile['province'] = selectedProvince;
      currentUserProfile['phone'] = phone;
      currentUserProfile['lineId'] = lineController.text.trim();
      currentUserProfile['fbLink'] = fbController.text.trim();
      currentUserProfile['homeType'] = selectedHomeType;
      currentUserProfile['traits'] = List<String>.from(selectedTraitIds);
      if (imageUrl != null) currentUserProfile['profileImageUrl'] = imageUrl;
      // ไม่ต้อง Navigator.push เอง — completeProfile() ยิง event เข้า authStateChanges
      // แล้ว AuthGate จะสลับไป MainScreen ให้เอง (แบบเดียวกับ login_screen)
      //
      // ถ้า pushReplacement ที่นี่ด้วยจะกลายเป็นว่า MainScreen ถูก mount พร้อมกัน 2 ตัว
      // (ตัวของ AuthGate + ตัวที่ push เอง) โหลดข้อมูล/เปิด polling ซ้อนกันสองชุด
      // ซ้ำร้ายมันไปแทนที่ route ของ AuthGate ทิ้ง ทำให้ logout/session หมดอายุ
      // พากลับไปหน้า login ไม่ได้อีกเลย
    } catch (_) {
      if (!mounted) return;
      showFieldError('submit', 'บันทึกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    lineController.dispose();
    fbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageFrame(
          maxWidth: AppLayout.formWidth,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: GestureDetector(
                      onTap: _isSaving ? null : _pickImage,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(
                                  color: AppColors.primary, width: 2),
                            ),
                            child: _pickedImageBytes != null
                                ? ClipOval(
                                    child: Image.memory(_pickedImageBytes!,
                                        width: 110,
                                        height: 110,
                                        fit: BoxFit.cover),
                                  )
                                : const Icon(Icons.person,
                                    size: 56, color: AppColors.primarySoft),
                          ),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.fromBorderSide(
                                  BorderSide(color: Colors.white, width: 2)),
                            ),
                            child: const Icon(Icons.add_a_photo,
                                color: Colors.white, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _pickedImageBytes == null
                        ? 'แตะเพื่อเลือกรูปโปรไฟล์ (ไม่บังคับ)'
                        : 'แตะเพื่อเปลี่ยนรูปโปรไฟล์',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brown),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'สร้างโปรไฟล์ของคุณ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'กรอกข้อมูลก่อนเริ่มใช้งาน PetPaws',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Sarabun',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brown),
                  ),
                  const SizedBox(height: 28),
                  SectionCard(
                    title: 'ข้อมูลทั่วไป',
                    children: [
                      TextField(
                        key: const ValueKey('profile-name'),
                        controller: nameController,
                        enabled: !_isSaving,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'ชื่อผู้ใช้ / ชื่อเล่น *',
                          error: fieldErrorWidget('name'),
                          prefixIcon: const Icon(Icons.badge,
                              color: AppColors.primarySoft),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'ข้อมูลสถานที่',
                    children: [
                      ProvinceField(
                        value: selectedProvince,
                        labelText: 'จังหวัดที่อยู่ปัจจุบัน',
                        enabled: !_isSaving,
                        onChanged: (val) =>
                            setState(() => selectedProvince = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'ข้อมูลการติดต่อ',
                    children: [
                      TextField(
                        controller: phoneController,
                        enabled: !_isSaving,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: InputDecoration(
                          labelText: 'เบอร์โทรศัพท์ (10 หลัก)',
                          error: fieldErrorWidget('phone'),
                          prefixIcon: const Icon(Icons.phone),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card),
                              borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: lineController,
                        enabled: !_isSaving,
                        decoration: InputDecoration(
                          labelText: 'LINE ID',
                          prefixIcon: const Icon(Icons.chat_bubble_outline),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card),
                              borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: fbController,
                        enabled: !_isSaving,
                        decoration: InputDecoration(
                          labelText: 'ชื่อ Facebook',
                          hintText: 'เช่น สมชาย ใจดี',
                          prefixIcon: const Icon(Icons.facebook),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.card),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'ข้อมูลเสริมคัดกรองผู้เลี้ยง',
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedHomeType,
                        decoration: InputDecoration(
                            labelText: 'ประเภทที่พักอาศัย',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.card),
                                borderSide: BorderSide.none)),
                        items: homeTypes
                            .map((h) =>
                                DropdownMenuItem(value: h, child: Text(h)))
                            .toList(),
                        onChanged: _isSaving
                            ? null
                            : (val) => setState(() => selectedHomeType = val!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'ไลฟ์สไตล์ / นิสัยของคุณ *',
                    children: [
                      TagSelector(
                        selectedIds: selectedTraitIds,
                        onToggle: _toggleTrait,
                        enabled: !_isSaving,
                      ),
                      InlineError(fieldError('traits')),
                    ],
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    key: const ValueKey('profile-submit'),
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.control)),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: PawSpinner(color: Colors.white),
                          )
                        : const Text('บันทึกและเริ่มใช้งาน',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  InlineError(fieldError('submit')),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          )),
    );
  }
}
