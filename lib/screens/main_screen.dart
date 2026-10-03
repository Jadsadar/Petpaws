import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/pet_service.dart';
import '../shared/api_exception.dart';
import 'chat/chat_inbox_screen.dart';
import 'discover/discover_screen.dart';
import 'favorites/favorites_screen.dart';
import 'profile/profile_screen.dart';
import 'upload/upload_screen.dart';
import '../theme/app_theme.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _petService = PetService.instance;

  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _loadError;

  List<Map<String, dynamic>> allDogs = [];
  List<Map<String, dynamic>> myPostedDogs = [];
  List<Map<String, dynamic>> likedDogs = [];
  List<Map<String, dynamic>> passedDogs = [];

  /// ตัวกรองชนิดสัตว์ของเด็ค ('' = ทั้งหมด)
  String _speciesFilter = '';
  String? _deckCursor;
  bool _deckHasMore = true;
  bool _isFetchingMore = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _petService.deck(species: _speciesFilter),
        _petService.mine(),
        _petService.myLikes(),
      ]);
      final deckPage = results[0] as DeckPage;
      setState(() {
        allDogs = deckPage.dogs;
        _deckCursor = deckPage.nextCursor;
        _deckHasMore = deckPage.hasMore;
        myPostedDogs = results[1] as List<Map<String, dynamic>>;
        likedDogs = results[2] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      setState(() => _loadError = 'โหลดข้อมูลไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// ดึงการ์ดหน้าถัดไปมาต่อท้ายเงียบ ๆ เมื่อเหลือน้อย (prefetch ตาม SKILL.md)
  Future<void> _maybeFetchMoreDeck() async {
    if (_isFetchingMore || !_deckHasMore || allDogs.length > 3) return;
    _isFetchingMore = true;
    try {
      final page = await _petService.deck(cursor: _deckCursor, species: _speciesFilter);
      if (!mounted) return;
      setState(() {
        // ตัวที่ใส่กลับเข้า deck เอง (เลิกถูกใจ/เลิกปัด) กลายเป็นตัวที่ server
        // ส่งมาได้อีกในหน้าถัดไป ถ้าต่อท้ายดื้อ ๆ จะเห็นการ์ดเดิมซ้ำสองใบ
        final knownIds = allDogs.map((d) => d['id']).toSet();
        allDogs = [
          ...allDogs,
          ...page.dogs.where((d) => !knownIds.contains(d['id'])),
        ];
        _deckCursor = page.nextCursor;
        _deckHasMore = page.hasMore;
      });
    } catch (_) {
      // เงียบไว้ — ถ้าโหลดเพิ่มไม่สำเร็จ ผู้ใช้แค่เห็นการ์ดน้อยลง ไม่ใช่ error ที่ต้องขัดจังหวะ
    } finally {
      _isFetchingMore = false;
    }
  }

  /// เปลี่ยนตัวกรองชนิดสัตว์ → ดึงเด็คใหม่ตามชนิดนั้นตั้งแต่ต้น (เริ่ม cursor ใหม่)
  Future<void> onSpeciesFilterChanged(String species) async {
    if (species == _speciesFilter) return;
    setState(() => _speciesFilter = species);
    try {
      final page = await _petService.deck(species: species);
      // ระหว่างรอ ผู้ใช้อาจเปลี่ยนตัวกรองซ้ำ — ใช้ผลของรอบล่าสุดเท่านั้น
      if (!mounted || species != _speciesFilter) return;
      setState(() {
        allDogs = page.dogs;
        _deckCursor = page.nextCursor;
        _deckHasMore = page.hasMore;
        passedDogs.clear();
      });
    } catch (_) {
      if (mounted) _showError('โหลดการ์ดไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    }
  }

  void _showError(String message) {
    _messengerKey.currentState?.clearSnackBars();
    _messengerKey.currentState?.showSnackBar(SnackBar(duration: AppTheme.snackDuration, content: Text(message)));
  }

  void onLike(Map<String, dynamic> dog) {
    setState(() {
      likedDogs.add(dog);
      allDogs.remove(dog);
    });
    _maybeFetchMoreDeck();
    _petService.like(dog['id'] as String).catchError((Object e) {
      if (!mounted) return;
      if (_isGone(e)) {
        setState(() => likedDogs.remove(dog));
        _onPetGone();
        return;
      }
      setState(() {
        likedDogs.remove(dog);
        allDogs.insert(0, dog);
      });
      _showError('บันทึกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    });
  }

  void onPass(Map<String, dynamic> dog) {
    setState(() {
      passedDogs.add(dog);
      allDogs.remove(dog);
    });
    _maybeFetchMoreDeck();
    _petService.pass(dog['id'] as String).catchError((Object e) {
      // ปัดซ้ายพลาดไม่ร้ายแรง แค่ตัวนี้อาจโผล่มาให้เห็นซ้ำในเซสชันหน้า ไม่ต้องแจ้งเตือน
      // ยกเว้นประกาศหายไปแล้ว — ไม่ต้องให้ย้อนกลับมาได้
      if (mounted && _isGone(e)) {
        setState(() => passedDogs.remove(dog));
        _onPetGone();
      }
    });
  }

  /// server ตอบ 404 = ประกาศถูกลบไปแล้ว (เจ้าของลบ หรือข้อมูลถูกรีเซ็ต) แต่การ์ดยังค้าง
  /// อยู่ในเครื่อง — ไม่ต้องใส่การ์ดกลับ ไม่งั้นปัดเท่าไรก็ตีกลับมาที่เดิมไม่จบ
  bool _isGone(Object error) => error is ApiException && error.statusCode == 404;

  bool _reloadingStaleDeck = false;

  /// เจอการ์ดที่หายไปแล้วหนึ่งใบ ที่เหลือในเครื่องก็น่าจะเก่าเหมือนกัน — โหลด deck ใหม่
  /// (กันไว้ไม่ให้โหลดซ้อนถ้าปัดเร็ว ๆ แล้วเจอหลายใบติดกัน)
  Future<void> _onPetGone() async {
    _showError('ประกาศนี้ถูกลบไปแล้ว');
    if (_reloadingStaleDeck) return;
    _reloadingStaleDeck = true;
    try {
      final page = await _petService.deck();
      if (!mounted) return;
      setState(() {
        allDogs = page.dogs;
        _deckCursor = page.nextCursor;
        _deckHasMore = page.hasMore;
      });
    } catch (_) {
      // โหลดไม่สำเร็จก็ใช้การ์ดเดิมต่อไป ไม่ต้องแจ้งซ้ำ
    } finally {
      _reloadingStaleDeck = false;
    }
  }

  void onUndoPass() {
    if (passedDogs.isEmpty) return;
    final dog = passedDogs.removeLast();
    setState(() => allDogs.insert(0, dog));
    _petService.unpass(dog['id'] as String).catchError((_) {});
  }

  void onAddDog(Map<String, dynamic> newDog) =>
      setState(() => myPostedDogs.insert(0, newDog));

  Future<void> onDeleteDog(Map<String, dynamic> dog) async {
    final id = dog['id'] as String;
    try {
      await _petService.delete(id);
      if (!mounted) return;
      setState(() => myPostedDogs.remove(dog));
    } catch (_) {
      if (mounted) _showError('ลบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    }
  }

  void onEditDog(Map<String, dynamic> updatedDog) => setState(() {
        final index = myPostedDogs.indexWhere((d) => d['id'] == updatedDog['id']);
        if (index != -1) myPostedDogs[index] = updatedDog;
      });

  Future<void> onChangeStatus(Map<String, dynamic> dog, String newStatus) async {
    final id = dog['id'] as String;
    final previousStatus = dog['status'];
    setState(() {
      final index = myPostedDogs.indexWhere((d) => d['id'] == id);
      if (index != -1) myPostedDogs[index]['status'] = newStatus;
    });
    try {
      final updated = await _petService.update(id, {'status': newStatus});
      if (!mounted) return;
      setState(() {
        final index = myPostedDogs.indexWhere((d) => d['id'] == id);
        if (index != -1) myPostedDogs[index] = updated;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final index = myPostedDogs.indexWhere((d) => d['id'] == id);
        if (index != -1) myPostedDogs[index]['status'] = previousStatus;
      });
      _showError('เปลี่ยนสถานะไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    }
  }

  // ฟังก์ชันสำหรับการกดสนใจรับเลี้ยง (หัวใจในหน้ารายละเอียด/การ์ด) — toggle
  // สลับกับปุ่มถูกใจตอนปัด (onLike) แต่ทั้งคู่จบที่ POST/DELETE /pets/:id/like เหมือนกัน
  void onToggleFavoriteDog(Map<String, dynamic> dog) {
    final id = dog['id'] as String;
    final exists = likedDogs.any((d) => d['id'] == id);
    setState(() {
      if (exists) {
        likedDogs.removeWhere((d) => d['id'] == id);
        _returnToDeck(dog);
      } else {
        likedDogs.add(dog);
        allDogs.removeWhere((d) => d['id'] == id);
      }
    });
    final future = exists ? _petService.unlike(id) : _petService.like(id);
    future.catchError((_) {
      if (!mounted) return;
      setState(() {
        if (exists) {
          likedDogs.add(dog);
          allDogs.removeWhere((d) => d['id'] == id);
        } else {
          likedDogs.removeWhere((d) => d['id'] == id);
        }
      });
      _showError('บันทึกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
    });
  }

  /// เลิกถูกใจแล้วต้องกลับมาเห็นในหน้าค้นหาอีกครั้ง — ฝั่ง DB ปลดให้เองตอนลบแถว
  /// likes (deck_feed กรองด้วย NOT EXISTS likes) แต่ allDogs ดึงมาไว้ในเครื่องแล้ว
  /// จึงต้องใส่กลับเอง ไม่งั้นต้องปิดแล้วเปิดแอปใหม่ถึงจะเจอ
  ///
  /// ใส่ไว้บนสุดแบบเดียวกับปุ่มเลิกปัด (onUndoPass) เพื่อให้เห็นผลทันทีว่ากลับมาแล้ว
  void _returnToDeck(Map<String, dynamic> dog) {
    // ตัวที่ถูกรับเลี้ยง/ยกเลิกประกาศไปแล้ว deck_feed ก็ไม่ส่งมาให้อยู่ดี
    if (dog['status'] != 'ยังไม่ถูกรับเลี้ยง') return;
    if (allDogs.any((d) => d['id'] == dog['id'])) return;
    allDogs.insert(0, dog);
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        body: _buildBody(),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          backgroundColor: Colors.white,
          items: [
            const BottomNavigationBarItem(icon: Icon(Icons.search), label: 'ค้นหา'),
            const BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'ถูกใจ'),
            BottomNavigationBarItem(
              label: 'แชท',
              icon: StreamBuilder<int>(
                stream: ChatService.instance.unreadChatCountStream(),
                builder: (context, snapshot) {
                  final unread = snapshot.data ?? 0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.chat_bubble_outline),
                      if (unread > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text('$unread',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const BottomNavigationBarItem(icon: Icon(Icons.post_add), label: 'ลงประกาศ'),
            const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'โปรไฟล์'),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_loadError!, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadInitialData, child: const Text('ลองใหม่')),
          ],
        ),
      );
    }

    // ใช้ IndexedStack ไม่ใช่ list สลับ widget ตรง ๆ เพื่อให้แต่ละแท็บคง state
    // ของตัวเองไว้ (เช่น scroll position) ตอนสลับไปมา แทนที่จะ rebuild ใหม่ทุกครั้ง
    return IndexedStack(
      index: _selectedIndex,
      children: [
        DiscoverScreen(
          dogs: allDogs,
          onLike: onLike,
          onPass: onPass,
          onUndoPass: onUndoPass,
          canUndo: passedDogs.isNotEmpty,
          likedDogs: likedDogs,
          onToggleFavorite: onToggleFavoriteDog,
          speciesFilter: _speciesFilter,
          onSpeciesFilterChanged: onSpeciesFilterChanged,
        ),
        FavoritesScreen(
          likedDogs: likedDogs,
          onToggleFavorite: onToggleFavoriteDog,
        ),
        const ChatInboxScreen(),
        UploadScreen(
          onAddDog: onAddDog,
          myPostedDogs: myPostedDogs,
          onDeleteDog: onDeleteDog,
          onEditDog: onEditDog,
          onChangeStatus: onChangeStatus,
          likedDogs: likedDogs,
          onToggleFavorite: onToggleFavoriteDog,
        ),
        const ProfileScreen(),
      ],
    );
  }
}
