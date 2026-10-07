import 'package:flutter/material.dart';

import '../screens/detail/pet_detail_screen.dart';
import 'pet_network_image.dart';
import '../utils/pet_species.dart';
import '../theme/app_theme.dart';

/// การ์ดสัตว์เลี้ยงในหน้า Discover ที่ปัดซ้าย/ขวาเพื่อไม่รับ/สนใจรับเลี้ยง
class SwipeableCard extends StatelessWidget {
  final Map<String, dynamic> dog;
  final VoidCallback onLike;
  final VoidCallback onPass;
  final List<Map<String, dynamic>> likedDogs;
  final Function(Map<String, dynamic>) onToggleFavorite;

  const SwipeableCard({
    super.key,
    required this.dog,
    required this.onLike,
    required this.onPass,
    required this.likedDogs,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(dog['id'].toString()),
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          onPass();
        } else if (direction == DismissDirection.startToEnd) {
          onLike();
        }
      },
      background: Container(
        decoration: BoxDecoration(
            color: AppColors.successSoft,
            borderRadius: BorderRadius.circular(AppRadius.card)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: const Icon(Icons.favorite, color: Colors.white, size: 50),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
            color: AppColors.dangerSoft,
            borderRadius: BorderRadius.circular(AppRadius.card)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: const Icon(Icons.close, color: Colors.white, size: 50),
      ),
      child: GestureDetector(
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => PetDetailScreen(
                      dog: dog,
                      isMyPost: false,
                      isFavorited: likedDogs.any((d) => d['id'] == dog['id']),
                      onToggleFavorite: () => onToggleFavorite(dog),
                    ))),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            color: Colors.white,
            boxShadow: AppLayout.shadows,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: PetNetworkImage(
                  imageUrl: dog['imageUrl'],
                  fit: BoxFit.cover,
                  iconSize: 80,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  gradient: const LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.6, 1.0],
                  ),
                ),
                padding: const EdgeInsets.all(20.0),
                // จอเล็ก/ตัวอักษรใหญ่: ชื่อและสายพันธุ์ยาวตัดบรรทัดได้ ถ้ายังไม่พอให้ย่อทั้งก้อนลงแทนล้น
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.bottomLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomLeft,
                      child: SizedBox(
                        width: box.maxWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${dog['name']}, ${dog['age']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text(
                                '${petSpeciesLabel(dog)} • ${dog['breed'] ?? 'ไม่ระบุสายพันธุ์'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 16)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.location_on,
                                    color: AppColors.primarySoft, size: 20),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text('${dog['province']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 16)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
