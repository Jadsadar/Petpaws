import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'paw_loader.dart';

/// แสดงรูปภาพจาก URL พร้อม fallback icon เมื่อไม่มีรูปหรือโหลดไม่สำเร็จ
class PetNetworkImage extends StatelessWidget {
  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final Color backgroundColor;
  final Color iconColor;
  final double iconSize;
  final IconData fallbackIcon;

  const PetNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.backgroundColor = AppColors.background,
    this.iconColor = Colors.black12,
    this.iconSize = 64,
    this.fallbackIcon = Icons.pets,
  });

  bool get _hasValidUrl {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  Widget _fallback() => Container(
        width: width,
        height: height,
        color: backgroundColor,
        child: Center(
          child: Icon(fallbackIcon, size: iconSize, color: iconColor),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final child = !_hasValidUrl
        ? _fallback()
        : Image.network(
            imageUrl!.trim(),
            width: width,
            height: height,
            fit: fit,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (context, error, stackTrace) => _fallback(),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: width,
                height: height,
                color: backgroundColor,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: PawSpinner(color: iconColor.withValues(alpha: 0.45)),
                  ),
                ),
              );
            },
          );

    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }
}
