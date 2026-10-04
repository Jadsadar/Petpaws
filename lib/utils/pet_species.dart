/// ชนิดสัตว์เลี้ยงที่เลือกได้ — ค่า key ต้องตรงกับ PET_SPECIES ใน
/// backend/api/src/pets/pet-mappers.ts (ส่งค่าอื่นจะโดน 400)
const Map<String, String> petSpeciesLabels = {
  'dog': 'สุนัข',
  'cat': 'แมว',
  'bird': 'นก',
  'fish': 'ปลา',
  'rabbit': 'กระต่าย',
  'other': 'อื่น ๆ',
};

/// ป้ายที่โชว์ผู้ใช้: ชนิด "อื่นๆ" แสดงข้อความที่เจ้าของพิมพ์เอง (เช่น เต่า) ถ้ามี
String petSpeciesLabel(Map<String, dynamic> dog) {
  final species = dog['species'] as String? ?? 'dog';
  if (species == 'other') {
    final custom = (dog['speciesOther'] as String?)?.trim() ?? '';
    if (custom.isNotEmpty) return custom;
  }
  return petSpeciesLabels[species] ?? petSpeciesLabels['other']!;
}
