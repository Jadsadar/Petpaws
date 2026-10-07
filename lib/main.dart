import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/mock_data.dart';
import 'screens/admin/admin_screen.dart';
import 'screens/auth/create_profile_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/admin_service.dart';
import 'services/auth_service.dart';
import 'shared/app_user.dart';
import 'theme/app_theme.dart';
import 'widgets/paw_loader.dart';
import 'widgets/update_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // เช็ค token ที่ค้างอยู่ในเครื่อง (ถ้ามี) ก่อนวาดหน้าแรก กันไม่ให้ผู้ใช้ที่
  // เคยล็อกอินไว้แล้วต้องเห็นหน้า login วูบหนึ่งก่อนสลับไป MainScreen
  await AuthService.instance.restoreSession();
  await _lockPortraitOnPhones();
  runApp(const PetPawsApp());
}

/// มือถือ (ด้านสั้นของจอ < 600dp) ล็อกแนวตั้ง: หน้าปัดการ์ด/แชท/ฟอร์มออกแบบมาสำหรับแนวตั้ง
/// แนวนอนจอสูงแค่ ~320dp (ลบแถบบน/ล่างแล้วเหลือที่แสดงการ์ดไม่พอ) แท็บเล็ตและเว็บหมุนได้ตามปกติ
Future<void> _lockPortraitOnPhones() async {
  if (kIsWeb) return;
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  if (view.physicalSize.shortestSide / view.devicePixelRatio < 600) {
    await SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  }
}

class PetPawsApp extends StatelessWidget {
  const PetPawsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PetPaws',
      theme: AppTheme.light,
      // ภาพพื้นหลังอยู่ใต้ทุกหน้า + ขยายตัวอักษรทั้งแอป (คูณกับค่าที่ผู้ใช้ตั้งในเครื่อง)
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: AppTheme.appTextScaler(mq.textScaler)),
          // แจ้งเตือน (SnackBar) อยู่ด้านล่าง ความกว้างไม่เกิน 480 บนจอกว้าง
          child: Builder(builder: (context) {
            final size = MediaQuery.sizeOf(context);
            final side = size.width > 528 ? (size.width - 480) / 2 : 24.0;
            final theme = Theme.of(context);
            return Theme(
              data: theme.copyWith(
                snackBarTheme: theme.snackBarTheme.copyWith(
                  insetPadding:
                      EdgeInsets.fromLTRB(side, 0, side, 16),
                ),
              ),
              child: AppBackground(child: child!),
            );
          }),
        );
      },
      // ตรวจเวอร์ชันใหม่ตอนเปิดแอป (Android เท่านั้น) แล้วถามว่าจะอัพเดตไหม
      home: const UpdateGate(child: AuthGate()),
    );
  }
}

/// ฟังสถานะการล็อกอินแล้วสลับหน้าให้อัตโนมัติ
/// แอดมินเข้าแดชบอร์ดแอดมินอย่างเดียว (ไม่ผ่าน MainScreen ของผู้ใช้ทั่วไป)
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _probedUid;
  Future<bool>? _isAdmin;

  /// เช็กสิทธิ์แอดมินครั้งเดียวต่อผู้ใช้หนึ่งคน (เก็บ Future ไว้ ไม่สร้างใหม่ทุกครั้งที่ build
  /// ไม่งั้น FutureBuilder จะกะพริบหน้าโหลดซ้ำทุกครั้งที่ StreamBuilder วาดใหม่)
  Future<bool> _adminFor(String uid) {
    if (_probedUid != uid) {
      _probedUid = uid;
      _isAdmin = AdminService.instance.checkIsAdmin();
    }
    return _isAdmin!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: AuthService.instance.authStateChanges,
      initialData: AuthService.instance.currentUser,
      builder: (context, snapshot) {
        // ห้ามเช็ค ConnectionState.waiting ที่นี่: StreamBuilder จะตั้งสถานะเป็น
        // waiting ทันทีที่ subscribe และค้างอยู่จนกว่า stream จะส่ง event แรก แต่
        // _controller เป็น broadcast (ไม่ replay ให้ subscriber ที่มาทีหลัง) และ
        // restoreSession() ยิง event ไปตั้งแต่ก่อน runApp() แล้ว — event นั้นจึงหาย
        // ไปก่อน AuthGate จะ subscribe ทัน ถ้าดัก waiting ไว้ = ค้างหน้าโหลดตลอดกาล
        //
        // ค่าที่ถูกต้องมาทาง initialData: currentUser อยู่แล้ว เพราะ main() await
        // restoreSession() จนเสร็จก่อนวาดเฟรมแรก
        final user = snapshot.data;
        if (user == null) {
          // ออกจากระบบแล้ว ล้างผลเช็กสิทธิ์ของบัญชีเก่า กันค้างไปให้บัญชีถัดไป
          _probedUid = null;
          _isAdmin = null;
          AdminService.instance.clearCache();
          return const LoginScreen();
        }
        return FutureBuilder<bool>(
          future: _adminFor(user.uid),
          builder: (context, adminSnap) {
            if (adminSnap.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: PawLoader()));
            }
            // เช็กแอดมินก่อนเช็กโปรไฟล์: แอดมินไม่ต้องกรอกโปรไฟล์ผู้ใช้
            if (adminSnap.data == true) {
              return const AdminScreen();
            }
            // profileCompleted = false คือบัญชีที่เพิ่งสมัคร ยังไม่เคยกรอกหน้าโปรไฟล์
            // (ดู migration 011_profile_completed.sql — แทนที่การเช็ก displayName ว่างแบบเดิม)
            if (!user.profileCompleted) {
              return const CreateProfileScreen();
            }
            currentUserProfile['name'] = user.displayName;
            currentUserProfile['email'] = user.email;
            return const MainScreen();
          },
        );
      },
    );
  }
}
