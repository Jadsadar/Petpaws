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
    // บังคับเป็นสี่เหลี่ยมจัตุรัสเสมอ — ใน ListTile ความสูงถูกจำกัด ถ้าไม่บังคับ
    // ความกว้างจะเหลือ 2r แต่ความสูงโดนบีบ รูปเลยกลายเป็นวงรี
    return LayoutBuilder(builder: (context, c) {
      var d = radius * 2;
      if (c.hasBoundedWidth && c.maxWidth < d) d = c.maxWidth;
      if (c.hasBoundedHeight && c.maxHeight < d) d = c.maxHeight;
      return Center(
        widthFactor: 1,
        heightFactor: 1,
        child: ClipOval(
          child: SizedBox.square(
            dimension: d,
            child: PetNetworkImage(
              imageUrl: _hasValidUrl ? imageUrl : null,
              width: d,
              height: d,
              fit: BoxFit.cover,
              backgroundColor: backgroundColor,
              iconColor: iconColor,
              iconSize: d / 2,
              fallbackIcon: icon,
            ),
          ),
        ),
      );
    });
  }
}
