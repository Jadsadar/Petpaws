import 'package:flutter/material.dart';

import '../screens/detail/pet_detail_screen.dart';
import 'pet_network_image.dart';
import '../utils/pet_species.dart';

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
            color: Colors.green.shade300,
            borderRadius: BorderRadius.circular(20)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: const Icon(Icons.favorite, color: Colors.white, size: 50),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
            color: Colors.redAccent.shade100,
            borderRadius: BorderRadius.circular(20)),
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
            borderRadius: BorderRadius.circular(20),
            color: Colors.white,
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 8, spreadRadius: 1)
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: PetNetworkImage(
                  imageUrl: dog['imageUrl'],
                  fit: BoxFit.cover,
                  iconSize: 80,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.6, 1.0],
                  ),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${dog['name']}, ${dog['age']}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text('${petSpeciesLabel(dog)} • ${dog['breed'] ?? 'ไม่ระบุสายพันธุ์'}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 18)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            color: Color(0xFFFFB085), size: 20),
                        const SizedBox(width: 4),
                        Text(dog['province'],
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
