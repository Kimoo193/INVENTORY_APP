import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'log_service.dart';

// ============================================================
// AuthWrapper — يتحكم في توجيه المستخدم بناءً على حالة الـ Auth
// ✅ الـ AuthWrapper يفضل في الـ widget tree دايماً
//    عشان يسمع الـ authStateChanges حتى بعد دخول الـ HomeScreen
// ============================================================
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key, required this.authenticatedHome});
  final Widget authenticatedHome;

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _showSplash = false;
  bool _showHome  = false;
  // ignore: unused_field
  AppUser? _appUser;

  String? _lastLoggedUid;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  Future<void> _onAuthChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      // ✅ Logout — وقّف الـ notifications وارجع للـ login
      NotificationService.instance.stopListening();
      if (mounted) {
        setState(() {
          _showSplash = false;
          _showHome   = false;
          _appUser    = null;
          _lastLoggedUid = null;
        });
      }
      return;
    }

    // ✅ Login — جيب بيانات الـ user
    final appUser = await AuthService.instance.getCurrentUser();

    // لو الحساب موقوف
    if (appUser != null && !appUser.isActive) {
      await FirebaseAuth.instance.signOut();
      return;
    }

    // لو مش موجود في Firestore
    if (appUser == null) {
      try {
        await AuthService.instance.ensureUserDocument(firebaseUser);
      } catch (_) {}
    }

    // ✅ ابدأ الـ Notifications للـ Admins
    if (appUser != null && appUser.isAdmin) {
      NotificationService.instance.startListening(firebaseUser.uid);
    }

    // ✅ Log Login مرة واحدة بس
    if (appUser != null && _lastLoggedUid != appUser.uid) {
      _lastLoggedUid = appUser.uid;
      LogService.instance.logLogin(appUser);
    }

    if (mounted) {
      setState(() {
        _appUser    = appUser;
        _showSplash = true;
        _showHome   = false;
      });
    }

    // ✅ بعد 3 ثواني انتقل للـ Home
    await Future.delayed(const Duration(seconds: 3));
    if (mounted && _showSplash) {
      setState(() {
        _showSplash = false;
        _showHome   = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ مش مسجل دخول
    if (!_showSplash && !_showHome) {
      return const LoginScreen();
    }

    // ✅ Splash Screen
    if (_showSplash) {
      return const _SplashScreen();
    }

    // ✅ Home Screen
    return widget.authenticatedHome;
  }
}

// ============================================================
// Splash Screen
// ============================================================
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF16324F), Color(0xFF23476B), Color(0xFF0F2236)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: -30,
                left: -20,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC69749).withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned(
                bottom: 120,
                right: -40,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Column(
                children: [
                  const Spacer(),
                  Center(
                    child: Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.inventory_2_rounded, size: 72, color: Color(0xFF16324F)),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Karam Stock',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: const Text(
                      'جاري تجهيز مساحة العمل الخاصة بك',
                      style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: const Column(
                      children: [
                        SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Color(0xFFC69749)),
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '🤍 اللهم صلِّ وسلم على نبينا محمد 🤍',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: Text(
                      'BY : Kareem Mohamed',
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}