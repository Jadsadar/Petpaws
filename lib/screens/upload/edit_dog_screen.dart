import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/mock_data.dart';
import '../../services/pet_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/pet_image_picker.dart';
import '../../utils/pet_tags.dart';
import '../../widgets/province_picker.dart';
import '../../widgets/species_field.dart';
import '../../utils/pet_species.dart';
import '../../widgets/tag_selector.dart';
import '../../theme/app_theme.dart';

class EditDogScreen extends StatefulWidget {
  final Map<String, dynamic> dog;
  final Function(Map<String, dynamic>) onSave;

  const EditDogScreen({super.key, required this.dog, required this.onSave});

  @override
  State<EditDogScreen> createState() => _EditDogScreenState();
}

class _EditDogScreenState extends State<EditDogScreen> {
  late TextEditingController nameController;
  late TextEditingController breedController;
  late TextEditingController ageController;
  late TextEditingController weightController;
  late TextEditingController storyController;
  late TextEditingController speciesOtherController;
  late String selectedSpecies;

  late List<String> selectedTags;
  late String selectedProvince;
  late String selectedGender;
  Uint8List? _pickedImageBytes;
  bool _isSaving = false;
  final List<String> genders = ['ผู้', 'เมีย'];

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.dog['name']);
    breedController = TextEditingController(text: widget.dog['breed']);
    ageController = TextEditingController(text: widget.dog['age']);
    weightController = TextEditingController(text: widget.dog['weight']);
    storyController = TextEditingController(text: widget.dog['story']);
    speciesOtherController = TextEditingController(
        text: widget.dog['speciesOther'] as String? ?? '');
    final species = widget.dog['species'] as String? ?? 'dog';
    selectedSpecies = petSpeciesLabels.containsKey(species) ? species : 'dog';
    selectedTags = List<String>.from(petTagIds(widget.dog));
    selectedProvince = thaiProvinces.contains(widget.dog['province'])
        ? widget.dog['province']
        : 'กรุงเทพมหานคร';
    selectedGender =
        genders.contains(widget.dog['gender']) ? widget.dog['gender'] : 'ผู้';
  }

  void _toggleTag(String tagId) => setState(() {
        if (selectedTags.contains(tagId)) {
          selectedTags.remove(tagId);
        } else {
          selectedTags.add(tagId);
        }
      });

  Future<void> saveChanges() async {
    if (nameController.text.isEmpty || ageController.text.isEmpty) return;
    if (selectedSpecies == 'other' &&
        speciesOtherController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: AppTheme.snackDuration, content: Text('กรุณาระบุชนิดสัตว์เลี้ยง')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      String imageUrl = widget.dog['imageUrl'] ?? '';
      if (_pickedImageBytes != null) {
        imageUrl =
            await StorageService.instance.uploadPetImage(_pickedImageBytes!);
      }
      // ส่งเฉพาะ field ที่แก้ไขได้ไปให้ backend อัปเดตจริง (ไม่ใช่แค่สร้าง Map
      // ในเครื่องแล้วหลอกตัวเองว่าบันทึกแล้ว) แล้วใช้ผลลัพธ์ที่ server ตอบกลับมา
      // เป็นความจริงชุดใหม่ — กัน field ที่ backend คุมเอง (เช่น likeCount, status
      // ที่ควรแก้ผ่านปุ่มสถานะแยกต่างหาก) หลุดเข้ามาปนโดยไม่ตั้งใจ
      final updatedDog =
          await PetService.instance.update(widget.dog['id'] as String, {
        "name": nameController.text,
        "species": selectedSpecies,
        "speciesOther": selectedSpecies == 'other'
            ? speciesOtherController.text.trim()
            : '',
        "breed": breedController.text.isEmpty ? "พันทาง" : breedController.text,
        "province": selectedProvince,
        "age": ageController.text,
        "gender": selectedGender,
        "weight": weightController.text.isEmpty ? "-" : weightController.text,
        "tags": List<String>.from(selectedTags),
        "story":
            storyController.text.isEmpty ? "ไม่มีข้อมูล" : storyController.text,
        "imageUrl": imageUrl,
      });
      widget.onSave(updatedDog);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(duration: AppTheme.snackDuration, content: Text('อัปเดตข้อมูลสำเร็จ!')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: AppTheme.snackDuration, 
          content: Text('บันทึกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('แก้ไขข้อมูล',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.textDark)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppColors.primary),
        elevation: 1,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'ข้อมูลสัตว์เลี้ยง',
              children: [
                TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                        labelText: 'ชื่อสัตว์เลี้ยง *',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card)))),
                const SizedBox(height: 16),
                SpeciesField(
                  species: selectedSpecies,
                  otherController: speciesOtherController,
                  enabled: !_isSaving,
                  onChanged: (v) => setState(() => selectedSpecies = v),
                ),
                const SizedBox(height: 16),
                TextField(
                    controller: breedController,
                    decoration: InputDecoration(
                        labelText: 'สายพันธุ์',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.card)))),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
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
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                      child: TextField(
                          controller: ageController,
                          // กันไม่ให้พิมพ์เครื่องหมายลบ แต่ยังพิมพ์ "6 เดือน" ได้
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'-'))
                          ],
                          decoration: InputDecoration(
                              labelText: 'อายุ *',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.card))))),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: ProvinceField(
                      value: selectedProvince,
                      onChanged: (val) => setState(() => selectedProvince = val),
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
                                  borderRadius: BorderRadius.circular(AppRadius.card))))),
                ]),
              ],
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'นิสัยเด่นๆ ของสัตว์เลี้ยง',
              children: [
                TagSelector(
                  selectedIds: selectedTags,
                  onToggle: _toggleTag,
                  enabled: !_isSaving,
                  backgroundColor: AppColors.background,
                ),
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
            SectionCard(
              title: 'รูปภาพ',
              children: [
                PetImagePicker(
                  initialImageUrl: widget.dog['imageUrl'],
                  onChanged: (bytes) => setState(() => _pickedImageBytes = bytes),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : saveChanges,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey.shade400,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text('บันทึกการแก้ไข',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
