// E2E ฝั่งแอป: เปิดแอปจริง กดจริง ต่อ backend จริง (API + Postgres + Redis + S3)
//
// รันในเครื่อง (ต้องเปิด backend ที่ localhost:3000 และใส่ seed demo ไว้แล้ว):
//   chromedriver --port=4444
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_e2e_test.dart -d web-server --browser-name=chrome \
//     --dart-define=API_BASE_URL=http://localhost:3000
//
// ใน CI รันโดย job "Mobile e2e" ใน .github/workflows/ci.yml
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:petpaws/main.dart' as app;
import 'package:petpaws/services/auth_service.dart';
import 'package:petpaws/shared/token_storage.dart';
import 'package:petpaws/widgets/swipeable_card.dart';

/// บัญชีจาก backend/db/seeds/003_demo_accounts.sql
const _demoUser = 'demo01';
const _demoPassword = 'Petpaws1!';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// เริ่มแอปใหม่ทุกเคสแบบยังไม่ล็อกอิน (ล้าง token ที่ค้างจากเคสก่อน)
  Future<void> startLoggedOut(WidgetTester tester) async {
    await TokenStorage.instance.clear();
    if (AuthService.instance.currentUser != null) {
      await AuthService.instance.signOut();
    }
    await app.main();
    await settle(tester);
  }

  testWidgets('1) ล็อกอินรหัสผิด → ขึ้นข้อความเตือนใต้ช่อง ไม่เข้าแอป', (tester) async {
    await startLoggedOut(tester);
    await tester.enterText(find.byKey(const ValueKey('login-identifier')), _demoUser);
    await tester.enterText(find.byKey(const ValueKey('login-password')), 'Wrong-pass-1');
    await tester.tap(find.byKey(const ValueKey('login-submit')));
    await waitFor(tester, find.byIcon(Icons.error_outline));

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byKey(const ValueKey('login-submit')), findsOneWidget,
        reason: 'ยังอยู่หน้าเข้าสู่ระบบ');
  });

  testWidgets('2) ล็อกอินถูก → เข้าหน้าค้นหา เห็นแถบหมวดและการ์ดสัตว์', (tester) async {
    await startLoggedOut(tester);
    await login(tester);

    expect(find.byKey(const ValueKey('species-chip-all')), findsOneWidget);
    expect(find.byType(SwipeableCard), findsOneWidget);
  });

  testWidgets('3) กดหมวด "แมว" → การ์ดที่แสดงเป็นแมว', (tester) async {
    await startLoggedOut(tester);
    await login(tester);

    await tester.tap(find.byKey(const ValueKey('species-chip-cat')));
    await waitFor(tester, find.textContaining('แมว •'));

    expect(find.textContaining('แมว •'), findsOneWidget);
    expect(find.textContaining('สุนัข •'), findsNothing);
  });

  testWidgets('4) กดถูกใจการ์ด → สัตว์ตัวนั้นไปอยู่ในหน้าถูกใจ', (tester) async {
    await startLoggedOut(tester);
    await login(tester);

    final name = topCardName(tester);
    await tester.tap(find.byKey(const ValueKey('discover-like')));
    await settle(tester);

    await tester.tap(find.text('ถูกใจ').last); // แท็บเมนูล่าง
    await waitFor(tester, find.text(name));
    expect(find.text(name), findsWidgets);
  });

  testWidgets('5) สมัครสมาชิก → ล็อกอิน → สร้างโปรไฟล์ → เข้าแอปได้', (tester) async {
    await startLoggedOut(tester);
    // ชื่อไม่ซ้ำทุกครั้งที่รัน
    final id = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
    final username = 'e2e$id';
    const password = 'E2eTest!234';

    await tester.tap(find.byKey(const ValueKey('login-register-link')));
    await settle(tester);
    await tester.enterText(find.byKey(const ValueKey('register-username')), username);
    await tester.enterText(find.byKey(const ValueKey('register-email')), '$username@e2e.test');
    await tester.enterText(find.byKey(const ValueKey('register-password')), password);
    await tester.enterText(find.byKey(const ValueKey('register-confirm')), password);
    await tester.ensureVisible(find.byKey(const ValueKey('register-submit')));
    await tester.tap(find.byKey(const ValueKey('register-submit')));
    await waitFor(tester, find.byKey(const ValueKey('login-submit')));

    await login(tester, user: username, password: password, expectHome: false);
    await waitFor(tester, find.byKey(const ValueKey('profile-name')));

    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'ผู้ทดสอบ E2E');
    final firstTag = find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('tag-'));
    await tester.ensureVisible(firstTag.first);
    await tester.tap(firstTag.first);
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('profile-submit')));
    await tester.tap(find.byKey(const ValueKey('profile-submit')));
    await waitFor(tester, find.byKey(const ValueKey('species-chip-all')));

    expect(find.byKey(const ValueKey('species-chip-all')), findsOneWidget,
        reason: 'สร้างโปรไฟล์เสร็จแล้วเข้าหน้าค้นหา');
  });
}

Future<void> login(WidgetTester tester,
    {String user = _demoUser, String password = _demoPassword, bool expectHome = true}) async {
  await tester.enterText(find.byKey(const ValueKey('login-identifier')), user);
  await tester.enterText(find.byKey(const ValueKey('login-password')), password);
  await tester.tap(find.byKey(const ValueKey('login-submit')));
  if (expectHome) await waitFor(tester, find.byType(SwipeableCard));
}

/// ชื่อสัตว์บนการ์ดบนสุด (ข้อความรูปแบบ "ชื่อ, อายุ")
String topCardName(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.descendant(of: find.byType(SwipeableCard), matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .where((s) => s.contains(', '));
  return texts.first.split(', ').first;
}

/// pump จนกว่าแอนิเมชันสงบ (ไม่ใช้ pumpAndSettle ตรง ๆ เพราะบางหน้ามีตัวโหลดหมุนค้าง)
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// รอ (สูงสุด 20 วินาที) จนกว่าจะเจอ widget ที่ต้องการ — รอผลจาก backend จริง
Future<void> waitFor(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (finder.evaluate().isNotEmpty) {
      await settle(tester);
      return;
    }
  }
  throw TestFailure('รอ ${finder.describeMatch(Plurality.many)} เกิน ${timeout.inSeconds} วินาที');
}
