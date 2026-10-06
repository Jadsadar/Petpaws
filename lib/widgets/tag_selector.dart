import 'package:flutter/material.dart';

import '../utils/pet_tags.dart';
import '../theme/app_theme.dart';

/// ปุ่มเลือกแท็กนิสัย ใช้ชุดเดียวกันทั้งฝั่งผู้ใช้และฝั่งสัตว์เลี้ยง
/// เลือกได้สูงสุด [maxTagSelection] แท็ก พอครบแล้วปุ่มที่ยังไม่ได้เลือกจะกดไม่ได้
class TagSelector extends StatelessWidget {
  const TagSelector({
    super.key,
    required this.selectedIds,
    required this.onToggle,
    this.enabled = true,
    this.backgroundColor = Colors.white,
  });

  final List<String> selectedIds;
  final ValueChanged<String> onToggle;
  final bool enabled;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final reachedMax = selectedIds.length >= maxTagSelection;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: petTags.map((tag) {
            final isSelected = selectedIds.contains(tag.id);
            final canTap = enabled && (isSelected || !reachedMax);
            return ChoiceChip(
              key: ValueKey('tag-${tag.id}'),
              label: Text(tag.label,
                  style: TextStyle(
                      color: isSelected
                          ? AppColors.onPrimary
                          : (canTap ? AppColors.textDark : AppColors.textMuted),
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal)),
              selected: isSelected,
              onSelected: canTap ? (_) => onToggle(tag.id) : null,
              selectedColor: AppColors.primary,
              backgroundColor: backgroundColor,
              disabledColor: isSelected
                  ? AppColors.primary.withValues(alpha: 0.65)
                  : backgroundColor,
              side: const BorderSide(color: AppColors.sand),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card)),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        TextPanel(
          child: Text(
            'เลือกได้สูงสุด $maxTagSelection แท็ก (เลือกแล้ว ${selectedIds.length})',
            style: const TextStyle(fontSize: 12, color: AppColors.textDark),
          ),
        ),
      ],
    );
  }
}
