import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/mock_data.dart';
import '../../services/pet_service.dart';
import '../../services/auth_service.dart';
import '../../services/users_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/pet_avatar.dart';
import '../../widgets/pet_image_picker.dart';
import '../../widgets/province_picker.dart';
import '../../widgets/species_field.dart';
import '../../widgets/tag_selector.dart';
import '../detail/pet_detail_screen.dart';
import 'edit_dog_screen.dart';
import 'pet_post_preview_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/field_error.dart';
import '../../widgets/paw_loader.dart';

class UploadScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onAddDog;
  final Function(Map<String, dynamic>) onDeleteDog;
  final Function(Map<String, dynamic>) onEditDog;
  final Function(Map<String, dynamic>, String) onChangeStatus;
  final List<Map<String, dynamic>> myPostedDogs;
  final List<Map<String, dynamic>> likedDogs;
  final Function(Map<String, dynamic>) onToggleFavorite;

  const UploadScreen({
    super.key,
    required this.onAddDog,
    required this.myPostedDogs,
    required this.onDeleteDog,
    required this.onChangeStatus,
    required this.onEditDog,
    required this.likedDogs,
    required this.onToggleFavorite,
  });

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> with FieldErrors {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController breedController = TextEditingController();
  final TextEditingController ageYearController = TextEditingController();
  final TextEditingController ageMonthController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  final TextEditingController storyController = TextEditingController();

  final TextEditingController speciesOtherController = TextEditingController();
  String selectedSpecies = 'dog';

  final List<String> selectedTags = [];

  String selectedProvince = 'กรุงเทพมหานคร';

  /// ผู้ใช้เลือกจังหวัดเองแล้ว — ถ้าใช่ ห้ามเอาจังหวัดของเจ้าของมาทับตอนโหลดโปรไฟล์เสร็จทีหลัง
  bool _provinceTouched = false;

  @override
  void initState() {
    super.initState();
    _loadOwnerProvince();
  }

  /// จังหวัดเริ่มต้นของประกาศ = จังหวัดในโปรไฟล์ของเจ้าของ (แก้เองได้)
  Future<void> _loadOwnerProvince() async {
    try {
      // จำไว้ตั้งแต่ล็อกอิน/เปิดแอปแล้ว — ถามเซิร์ฟเวอร์เฉพาะตอนยังไม่รู้ (backend รุ่นเก่า)
      final province = AuthService.instance.currentUser?.province ??
          (await UsersService.instance.getMe())['province'] as String?;
      if (!mounted || _provinceTouched) return;
      if (province != null && thaiProvinces.contains(province)) {
        setState(() => selectedProvince = province);
      }
    } catch (_) {
      // โหลดไม่ได้ก็ใช้ค่าเริ่มต้นเดิม ไม่ขัดจังหวะการลงประกาศ
    }
  }
  String selectedGender = 'ผู้';
  Uint8List? _pickedImageBytes;
  int _imagePickerResetKey = 0;
  bool _isSubmitting = false;
  final List<String> genders = ['ผู้', 'เมีย'];

  /// ช่องกรอกตัวเลขล้วนสำหรับอายุ digitsOnly กันทั้งเครื่องหมายลบและจุดทศนิยม
  Widget _ageField(TextEditingController controller, String label) => TextField(
        controller: controller,
        enabled: !_isSubmitting,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
        ),
      );

  /// รวมช่องปี/เดือนเป็นข้อความเดียว เพราะฝั่ง backend เก็บอายุเป็น age_label
  /// (ข้อความอิสระ) ไม่ใช่ตัวเลข — ข้ามส่วนที่เป็น 0 เพื่อไม่ให้ได้ "0 ปี 6 เดือน"
  String _composeAge() {
    final years = int.tryParse(ageYearController.text) ?? 0;
    final months = int.tryParse(ageMonthController.text) ?? 0;
    return [
      if (years > 0) '$years ปี',
      if (months > 0) '$months เดือน',
    ].join(' ');
  }

  void _toggleTag(String tagId) => setState(() {
        if (selectedTags.contains(tagId)) {
          selectedTags.remove(tagId);
        } else {
          selectedTags.add(tagId);
        }
      });

  Future<void> submitForm() async {
    clearFieldErrors();
    final age = _composeAge();
    if (nameController.text.trim().isEmpty || age.isEmpty) {
      showFieldError(nameController.text.trim().isEmpty ? 'name' : 'age',
          'กรุณากรอกชื่อและอายุ');
      return;
    }
    if ((int.tryParse(ageMonthController.text) ?? 0) > 11) {
      showFieldError('age', 'เดือนต้องไม่เกิน 11 ถ้าครบ 12 เดือนให้กรอกเป็นปีแทน');
      return;
    }
    if (selectedSpecies == 'other' &&
        speciesOtherController.text.trim().isEmpty) {
      showFieldError('species', 'กรุณาระบุชนิดสัตว์เลี้ยง');
      return;
    }
    if (selectedTags.isEmpty) {
      showFieldError('tags', 'กรุณาเลือกนิสัยเด่น ๆ อย่างน้อย 1 แท็ก');
      return;
    }
    if (_pickedImageBytes == null) {
      showFieldError('image', 'กรุณาเลือกรูปภาพสัตว์เลี้ยง 1 รูป');
      return;
    }

    // พรีวิวหน้าประกาศให้เจ้าของดูก่อน แล้วค่อยยืนยันโพสต์จริงอีกครั้ง
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PetPostPreviewScreen(
          imageBytes: _pickedImageBytes!,
          dog: {
            'name': nameController.text.trim(),
            'species': selectedSpecies,
            'speciesOther': speciesOtherController.text.trim(),
            'breed': breedController.text.isEmpty ? 'พันทาง' : breedController.text,
            'province': selectedProvince,
            'age': age,
            'gender': selectedGender,
            'weight': weightController.text.isEmpty ? '-' : weightController.text,
            'tags': List<String>.from(selectedTags),
            'story': storyController.text.isEmpty
                ? 'กำลังรอคนใจดีมารับไปดูแลอยู่ครับ/ค่ะ'
                : storyController.text,
          },
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      // อัปโหลดรูปให้เสร็จก่อนเรียกสร้างประกาศเสมอ ถ้าเรียกสลับกันแล้วรูปพัง
      // จะได้ประกาศรูปแตกค้างอยู่ใน deck
      final imageUrl =
          await StorageService.instance.uploadPetImage(_pickedImageBytes!);
      // ให้ backend เป็นคนสร้าง id/ownerId/ownerName จริง ๆ แทนการปลอมขึ้นเอง
      // (เดิม id มาจาก millisecondsSinceEpoch ในเครื่อง ซึ่งไม่ใช่ id จริงและ
      // ทำให้โพสต์นี้ไม่เคยถูกบันทึกไว้ที่ไหนที่บัญชีอื่นจะเห็นได้เลย)
      final newDog = await PetService.instance.create({
        "name": nameController.text,
        "species": selectedSpecies,
        if (selectedSpecies == 'other')
          "speciesOther": speciesOtherController.text.trim(),
        "breed": breedController.text.isEmpty ? "พันทาง" : breedController.text,
        "province": selectedProvince,
        "age": age,
        "gender": selectedGender,
        "weight": weightController.text.isEmpty ? "-" : weightController.text,
        "tags": List<String>.from(selectedTags),
        "story": storyController.text.isEmpty
            ? "กำลังรอคนใจดีมารับไปดูแลอยู่ครับ/ค่ะ"
            : storyController.text,
        "imageUrl": imageUrl,
      });
      widget.onAddDog(newDog);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(shape: AppTheme.snackSuccessShape, duration: AppTheme.snackDuration, content: Text('ประกาศหาบ้านสำเร็จ!', style: AppTheme.snackSuccessText)));
      nameController.clear();
      breedController.clear();
      ageYearController.clear();
      ageMonthController.clear();
      weightController.clear();
      selectedTags.clear();
      storyController.clear();
      setState(() {
        _pickedImageBytes = null;
        _imagePickerResetKey++;
        _provinceTouched = false;
      });
      _loadOwnerProvince();
    } catch (_) {
      if (!mounted) return;
      showFieldError('submit', 'ลงประกาศไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// สถานะที่เลือกเองได้ — ยกเลิกประกาศทำที่ปุ่มถังขยะ (ลบประกาศ) ไม่ใช่ที่นี่
  static const List<String> _statusOptions = ['ยังไม่ถูกรับเลี้ยง', 'ถูกรับเลี้ยงแล้ว'];

  Future<void> _changeStatus(Map<String, dynamic> dog, String newStatus) async {
    if (newStatus == (dog['status'] ?? 'ยังไม่ถูกรับเลี้ยง')) return;
    if (newStatus == 'ถูกรับเลี้ยงแล้ว') {
      // เปลี่ยนแล้วห้องแชทของประกาศนี้ถูกปิดทุกห้องและส่งข้อความแจ้งผู้สนใจ — ย้อนกลับไม่ได้
      // จึงถามยืนยันก่อน กันกดพลาด
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ยืนยันการเปลี่ยนสถานะ'),
          content: Text('เปลี่ยน "${dog['name']}" เป็น "ถูกรับเลี้ยงแล้ว" ใช่หรือไม่?\n\n'
              'ห้องแชทของประกาศนี้จะถูกปิดและแจ้งผู้สนใจทุกคน และเปิดกลับไม่ได้'),
          actions: [
            TextButton(
                key: const ValueKey('status-cancel'),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก')),
            TextButton(
                key: const ValueKey('status-confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ยืนยัน')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    widget.onChangeStatus(dog, newStatus);
  }

  Color _getStatusColor(String status) {
    if (status == 'ถูกรับเลี้ยงแล้ว') return AppColors.success;
    if (status == 'ยกเลิกประกาศ') return AppColors.danger;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('ลงประกาศ',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.textDark)),
        backgroundColor: AppColors.appBar,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'รูปภาพ *',
              children: [
                PetImagePicker(
                  key: ValueKey(_imagePickerResetKey),
                  onChanged: (bytes) => setState(() => _pickedImageBytes = bytes),
                ),
                InlineError(fieldError('image')),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'ข้อมูลสัตว์เลี้ยง',
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                      labelText: 'ชื่อสัตว์เลี้ยง *',
                  error: fieldErrorWidget('name'),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card))),
                ),
                const SizedBox(height: 16),
                SpeciesField(
                  species: selectedSpecies,
                  otherController: speciesOtherController,
                  enabled: !_isSubmitting,
                  onChanged: (v) => setState(() => selectedSpecies = v),
                ),
                InlineError(fieldError('species')),
                const SizedBox(height: 16),
                TextField(
                  controller: breedController,
                  decoration: InputDecoration(
                      labelText: 'สายพันธุ์',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card))),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedGender,
                  decoration: InputDecoration(
                      labelText: 'เพศ',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card))),
                  items: genders
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedGender = val!),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _ageField(ageYearController, 'อายุ (ปี) *')),
                  const SizedBox(width: 16),
                  Expanded(child: _ageField(ageMonthController, 'อายุ (เดือน)')),
                ]),
                InlineError(fieldError('age')),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: ProvinceField(
                      value: selectedProvince,
                      onChanged: (val) => setState(() {
                        _provinceTouched = true;
                        selectedProvince = val;
                      }),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                        controller: weightController,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        // รับเฉพาะตัวเลขกับจุดทศนิยม พิมพ์เครื่องหมายลบไม่ได้
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                        ],
                        decoration: InputDecoration(
                            labelText: 'น้ำหนัก (กก.)',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppRadius.card)))),
                  ),
                ]),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'นิสัยเด่น ๆ ของสัตว์เลี้ยง *',
              children: [
                TagSelector(
                  selectedIds: selectedTags,
                  onToggle: _toggleTag,
                  enabled: !_isSubmitting,
                  backgroundColor: AppColors.background,
                ),
                InlineError(fieldError('tags')),
                const SizedBox(height: 16),
                TextField(
                    controller: storyController,
                    maxLines: 3,
                    decoration: InputDecoration(
                        labelText: 'รายละเอียดเพิ่มเติม / เรื่องราวของสัตว์เลี้ยง',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card)))),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                elevation: 2,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: PawSpinner(color: Colors.white),
                    )
                  : const Text('โพสต์หาบ้าน',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            InlineError(fieldError('submit')),
            const SizedBox(height: 32),
            const Divider(color: Colors.black12),
            const SizedBox(height: 16),
            const TextPanel(child: Text('ประกาศของฉัน',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark))),
            const SizedBox(height: 12),
            widget.myPostedDogs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('คุณยังไม่ได้ลงประกาศสัตว์เลี้ยง',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark)),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.myPostedDogs.length,
                    itemBuilder: (context, index) {
                      final dog = widget.myPostedDogs[index];
                      final currentStatus =
                          dog['status'] ?? 'ยังไม่ถูกรับเลี้ยง';
                      return Card(
                        elevation: 0,
                        color: AppColors.section,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            side: const BorderSide(
                                color: AppColors.sand, width: 1)),
                        margin: const EdgeInsets.only(bottom: 16),
                        child: InkWell(
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => PetDetailScreen(
                                        dog: dog,
                                        isMyPost: true,
                                        isFavorited: widget.likedDogs
                                            .any((d) => d['id'] == dog['id']),
                                        onToggleFavorite: () =>
                                            widget.onToggleFavorite(dog),
                                      ))),
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: PetAvatar(
                                    imageUrl: dog['imageUrl'],
                                    radius: 28,
                                  ),
                                  title: Text(dog['name'],
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: AppColors.textDark)),
                                  subtitle: Text(
                                      '${dog['province']} • อายุ ${dog['age']}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit,
                                            color: Colors.blueGrey),
                                        onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (context) =>
                                                    EditDogScreen(
                                                        dog: dog,
                                                        onSave:
                                                            widget.onEditDog))),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: AppColors.danger),
                                        onPressed: () async {
                                          final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('ลบประกาศ'),
                                              content: Text(
                                                  'ต้องการลบประกาศ "${dog['name']}" ใช่หรือไม่?\n\nลบแล้วกู้คืนไม่ได้'),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(ctx, false),
                                                    child: const Text('ยกเลิก')),
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(ctx, true),
                                                    child: const Text('ลบ',
                                                        style: TextStyle(
                                                            color: AppColors.danger))),
                                              ],
                                            ),
                                          );
                                          if (ok != true || !context.mounted) return;
                                          widget.onDeleteDog(dog);
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                                  shape: AppTheme.snackSuccessShape,
                                                  duration: AppTheme.snackDuration,
                                                  content: Text('ลบประกาศเรียบร้อยแล้ว',
                                                      style: AppTheme.snackSuccessText)));
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(color: Colors.white),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('สถานะปัจจุบัน:',
                                        style:
                                            TextStyle(color: Colors.black54)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(
                                            color: _getStatusColor(currentStatus),
                                            width: 1.4),
                                        borderRadius: BorderRadius.circular(AppRadius.card),
                                      ),
                                      child: DropdownButton<String>(
                                        key: ValueKey('status-${dog['id']}'),
                                        // ประกาศเก่าที่เคยตั้ง "ยกเลิกประกาศ" ไม่อยู่ในตัวเลือกแล้ว
                                        // value ต้องเป็น null เพื่อไม่ให้ dropdown assert (โชว์ hint แทน)
                                        value: _statusOptions.contains(currentStatus)
                                            ? currentStatus
                                            : null,
                                        hint: Text(currentStatus,
                                            style: TextStyle(
                                                color: _getStatusColor(currentStatus),
                                                fontWeight: FontWeight.bold)),
                                        focusColor: Colors.transparent,
                                        dropdownColor: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        underline: const SizedBox(),
                                        icon: Icon(Icons.arrow_drop_down,
                                            color:
                                                _getStatusColor(currentStatus)),
                                        style: TextStyle(
                                          color: _getStatusColor(currentStatus),
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Sarabun',
                                        ),
                                        items: _statusOptions
                                            .map((statusText) =>
                                                DropdownMenuItem(
                                                    value: statusText,
                                                    child: Text(statusText)))
                                            .toList(),
                                        onChanged: (newValue) {
                                          if (newValue != null) {
                                            _changeStatus(dog, newValue);
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
