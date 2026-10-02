import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpaws/screens/chat/media_viewer_screen.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// ตัวเล่นปลอม — initialize สำเร็จทันที วิดีโอ 640x360 ยาว 10 วินาที
class _FakePlayer extends VideoPlayerPlatform {
  final volumes = <double>[];
  // ไม่ใช่ broadcast: เก็บ event initialized ไว้จนกว่าตัวเล่นจะเริ่มฟัง
  final _events = StreamController<VideoEvent>();

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    scheduleMicrotask(() => _events.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 10),
        size: const Size(640, 360))));
    return 1;
  }
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events.stream;
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async => volumes.add(volume);
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  // ขยายเต็มพื้นที่เหมือนตัวเล่นจริง (ColoredBox เปล่าจะได้ขนาด 0 แตะไม่โดน)
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand(child: ColoredBox(color: Colors.black));
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

/// ตัวเล่นมี timer อัปเดตตำแหน่งตลอดตอนเล่น pumpAndSettle จึงไม่มีวันจบ —
/// รอให้แอนิเมชันแถบเสียง (150ms) เล่นจบแทน
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  late _FakePlayer player;
  setUp(() => VideoPlayerPlatform.instance = player = _FakePlayer());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: VideoViewerScreen(url: 'http://x/v.mp4')));
    await settle(tester);
  }

  testWidgets('แถบเสียงซ่อนไว้ โผล่เมื่อชี้เมาส์ที่ลำโพง และหายเมื่อเอาเมาส์ออก', (tester) async {
    await open(tester);
    expect(find.byType(Slider), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.volume_up)));
    await settle(tester);
    expect(find.byType(Slider), findsOneWidget);

    // แถบอยู่เหนือปุ่ม และเป็นแนวตั้ง (สูงกว่ากว้าง)
    final slider = tester.getRect(find.byType(Slider));
    expect(slider.bottom <= tester.getRect(find.byIcon(Icons.volume_up)).top, isTrue);
    expect(slider.height > slider.width, isTrue);

    // เลื่อนเมาส์จากปุ่มขึ้นไปที่แถบ แถบต้องไม่หาย
    await mouse.moveTo(slider.center);
    await settle(tester);
    expect(find.byType(Slider), findsOneWidget);

    await mouse.moveTo(const Offset(5, 5));
    await settle(tester);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('ลากแถบลงสุด = ปิดเสียง ไอคอนเปลี่ยน, กดลำโพงแล้วกลับมาดังเท่าเดิม', (tester) async {
    await open(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byIcon(Icons.volume_up)));
    await settle(tester);

    final rect = tester.getRect(find.byType(Slider));
    // ล่าง -> บน = 0 -> 1 : แตะใกล้ล่างสุด
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 2));
    await settle(tester);
    expect(player.volumes.last, lessThan(0.1));

    // แถบหาย แล้วลากเป็น 0 ด้วยปุ่ม: ตั้งระดับ 0.3 ก่อน
    await tester.tapAt(Offset(rect.center.dx, rect.top + rect.height * 0.7));
    await settle(tester);
    final before = player.volumes.last;
    expect(before, inInclusiveRange(0.15, 0.45));
    expect(find.byIcon(Icons.volume_down), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_down));
    await settle(tester);
    expect(player.volumes.last, 0);
    expect(find.byIcon(Icons.volume_off), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_off));
    await settle(tester);
    expect(player.volumes.last, before);
  });

  testWidgets('จอสัมผัส: กดค้างที่ลำโพงเปิดแถบ แตะวิดีโอเพื่อปิด', (tester) async {
    await open(tester);
    // ระดับเสียงถูกจำข้ามวิดีโอ (ข้อก่อนหน้าปรับไว้) ไอคอนจึงเป็นแบบไหนก็ได้
    final speaker = find.byWidgetPredicate((w) =>
        w is Icon && {Icons.volume_up, Icons.volume_down, Icons.volume_off}.contains(w.icon));
    await tester.longPress(speaker);
    await settle(tester);
    expect(find.byType(Slider), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.byType(AspectRatio)));
    await settle(tester);
    expect(find.byType(Slider), findsNothing);
  });
}
