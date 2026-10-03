import 'package:flutter/material.dart';

import '../data/mock_data.dart';
import '../theme/app_theme.dart';

/// เปิด bottom sheet ให้เลือกจังหวัดแบบค้นหาได้ คืนค่าจังหวัดที่เลือก หรือ null ถ้ายกเลิก
Future<String?> showProvincePicker(
  BuildContext context, {
  String? selectedProvince,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _ProvincePickerSheet(selectedProvince: selectedProvince),
  );
}

class _ProvincePickerSheet extends StatefulWidget {
  final String? selectedProvince;
  const _ProvincePickerSheet({this.selectedProvince});

  @override
  State<_ProvincePickerSheet> createState() => _ProvincePickerSheetState();
}

class _ProvincePickerSheetState extends State<_ProvincePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filtered = thaiProvinces;

  void _onSearchChanged(String query) {
    final q = query.trim();
    setState(() {
      _filtered = q.isEmpty
          ? thaiProvinces
          : thaiProvinces.where((p) => p.contains(q)).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('เลือกจังหวัด',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'ค้นหาจังหวัด',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _filtered.isEmpty
                    ? const Center(
                        child: Text('ไม่พบจังหวัดที่ค้นหา',
                            style: TextStyle(color: Colors.grey)))
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, color: Colors.grey.shade100),
                        itemBuilder: (context, index) {
                          final province = _filtered[index];
                          final isSelected =
                              province == widget.selectedProvince;
                          return ListTile(
                            title: Text(province,
                                style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? AppColors.textDark
                                        : Colors.black87)),
                            trailing: isSelected
                                ? const Icon(Icons.check,
                                    color: AppColors.primary)
                                : null,
                            tileColor:
                                isSelected ? AppColors.background : null,
                            onTap: () => Navigator.pop(context, province),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// ช่องเลือกจังหวัดสไตล์เดียวกับ InputDecorator ปกติ แตะแล้วเปิด [showProvincePicker]
class ProvinceField extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String labelText;
  final bool enabled;

  const ProvinceField({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelText = 'จังหวัด',
    this.enabled = true,
  });

  Future<void> _openPicker(BuildContext context) async {
    final result =
        await showProvincePicker(context, selectedProvince: value);
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _openPicker(context) : null,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: labelText,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(value),
      ),
    );
  }
}
