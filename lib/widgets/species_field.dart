import 'package:flutter/material.dart';

import '../utils/pet_species.dart';
import '../theme/app_theme.dart';

/// เลือกชนิดสัตว์ (สุนัข/แมว/นก/ปลา/กระต่าย/อื่นๆ) — เลือก "อื่นๆ" แล้วมีช่องให้ระบุเอง
/// ใช้ร่วมกันทั้งหน้าลงประกาศและหน้าแก้ไข
class SpeciesField extends StatelessWidget {
  const SpeciesField({
    super.key,
    required this.species,
    required this.otherController,
    required this.onChanged,
    this.enabled = true,
  });

  final String species;
  final TextEditingController otherController;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('species-field'),
          initialValue: species,
          decoration: InputDecoration(
            labelText: 'ชนิดสัตว์เลี้ยง *',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.control)),
          ),
          items: [
            for (final e in petSpeciesLabels.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: enabled ? (v) => onChanged(v ?? species) : null,
        ),
        if (species == 'other') ...[
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('species-other'),
            controller: otherController,
            enabled: enabled,
            maxLength: 50,
            decoration: InputDecoration(
              labelText: 'ระบุชนิดสัตว์ *',
              hintText: 'เช่น หนู เต่า งู',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control)),
            ),
          ),
        ],
      ],
    );
  }
}
