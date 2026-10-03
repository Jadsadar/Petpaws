import 'package:flutter/material.dart';

import 'pet_network_image.dart';
import '../theme/app_theme.dart';

/// รูปโปรไฟล์ทรงกลมของสัตว์เลี้ยง/ผู้ใช้ พร้อม fallback icon
class PetAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;

  const PetAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 24,
    this.icon = Icons.pets,
    this.backgroundColor = AppColors.background,
    this.iconColor = AppColors.primary,
  });

  bool get _hasValidUrl {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: PetNetworkImage(
          imageUrl: _hasValidUrl ? imageUrl : null,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          backgroundColor: backgroundColor,
          iconColor: iconColor,
          iconSize: radius,
          fallbackIcon: icon,
        ),
      ),
    );
  }
}
