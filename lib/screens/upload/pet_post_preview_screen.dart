import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../utils/pet_species.dart';
import '../../utils/pet_tags.dart';
import '../../theme/app_theme.dart';

/// พรีวิวประกาศก่อนโพสต์จริง — หน้าตาเหมือนหน้ารายละเอียดที่คนอื่นจะเห็น
/// ปิดหน้านี้พร้อมค่า true เมื่อกด "ยืนยันโพสต์" (กด "แก้ไข" หรือย้อนกลับ = false/null)
class PetPostPreviewScreen extends StatelessWidget {
  const PetPostPreviewScreen({super.key, required this.dog, required this.imageBytes});

  /// รูปทรงเดียวกับ dog map ที่ backend ส่งกลับ (name, species, breed, province, age, gender, weight, tags, story)
  final Map<String, dynamic> dog;
  final Uint8List imageBytes;

  static const _orange = AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final male = dog['gender'] == 'ผู้';
    final tags = tagLabels(petTagIds(dog));
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('ตัวอย่างประกาศ',
            style: TextStyle(fontWeight: FontWeight.bold, color: _orange)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: _orange),
        elevation: 1,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.memory(imageBytes, width: double.infinity, height: 360, fit: BoxFit.cover),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text('${dog['name']}',
                            key: const ValueKey('preview-name'),
                            style: const TextStyle(
                                fontSize: 32, fontWeight: FontWeight.bold, color: _orange)),
                      ),
                      Icon(male ? Icons.male : Icons.female,
                          size: 32, color: male ? Colors.blue.shade300 : Colors.pink.shade300),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: AppColors.primarySoft),
                      const SizedBox(width: 8),
                      Text('${dog['province']}',
                          style: TextStyle(fontSize: 18, color: Colors.grey[700])),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _info(Icons.pets, petSpeciesLabel(dog), '${dog['breed']}'),
                      const SizedBox(width: 16),
                      _info(Icons.cake, 'อายุ', '${dog['age']}'),
                      const SizedBox(width: 16),
                      _info(Icons.monitor_weight, 'น้ำหนัก', '${dog['weight']} กก.'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('ลักษณะนิสัย',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in tags)
                        Chip(
                          label: Text(t,
                              style: const TextStyle(color: _orange, fontWeight: FontWeight.bold)),
                          backgroundColor: AppColors.background,
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('เกี่ยวกับฉัน',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text('${dog['story']}', style: const TextStyle(fontSize: 16, height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('preview-edit'),
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14), foregroundColor: _orange),
                  child: const Text('แก้ไข'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  key: const ValueKey('preview-confirm'),
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('ยืนยันโพสต์', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String title, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
              color: AppColors.background, borderRadius: BorderRadius.circular(AppRadius.card)),
          child: Column(
            children: [
              Icon(icon, color: _orange),
              const SizedBox(height: 4),
              Text(title,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                  textAlign: TextAlign.center),
              Text(value,
                  style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
