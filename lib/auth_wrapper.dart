import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'log_service.dart';

// ============================================================
// AuthWrapper — يتحكم في توجيه المستخدم بناءً على حالة الـ Auth
// ✅ StatefulWidget عشان نقدر نتعامل مع الـ logout صح
// ============================================================
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key, required this.authenticatedHome});
  final Widget authenticatedHome;

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  // ✅ نتذكر آخر حالة للـ user — لو كان logged in وبقى logged out نعمل redirect
  bool _wasLoggedIn = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {

        // جاري التحميل
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final firebaseUser = snapshot.data;

        // ✅ مش مسجل دخول
        if (firebaseUser == null) {
          NotificationService.instance.stopListening();

          // ✅ لو كان logged in قبل (logout حصل) — امسح كل الـ stack
          if (_wasLoggedIn) {
            _wasLoggedIn = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                // امسح كل الـ routes وارجع للـ root (اللي هو AuthWrapper نفسه)
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            });
          }

          return const LoginScreen();
        }

        // ✅ مسجل دخول
        return FutureBuilder<AppUser?>(
          future: AuthService.instance.getCurrentUser(),
          builder: (context, userSnapshot) {

            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            final appUser = userSnapshot.data;

            // لو الحساب موقوف
            if (appUser != null && !appUser.isActive) {
              FirebaseAuth.instance.signOut();
              return const LoginScreen();
            }

            // ✅ سجّل إن المستخدم مسجل دخول دلوقتي
            _wasLoggedIn = true;

            // ✅ ابدأ الـ Notifications للـ Admins
            if (appUser != null && appUser.isAdmin) {
              NotificationService.instance.startListening(firebaseUser.uid);
            }

            // ✅ Log Login — بس مرة واحدة (مش كل rebuild)
            if (appUser != null) {
              _logLoginOnce(appUser);
            }

            // لو مش موجود في Firestore
            if (appUser == null) {
              _ensureUserDocument(firebaseUser);
            }

            return _SplashThenHome(home: widget.authenticatedHome);
          },
        );
      },
    );
  }

  // ✅ Log login مرة واحدة بس — نستخدم flag
  String? _lastLoggedUid;
  void _logLoginOnce(AppUser user) {
    if (_lastLoggedUid == user.uid) return;
    _lastLoggedUid = user.uid;
    LogService.instance.logLogin(user);
  }

  void _ensureUserDocument(User firebaseUser) async {
    try {
      await AuthService.instance.ensureUserDocument(firebaseUser);
    } catch (_) {}
  }
}

// ============================================================
// Loading Screen
// ============================================================
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1A237E),
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

// ============================================================
// Splash Screen ثم Home
// ============================================================
class _SplashThenHome extends StatefulWidget {
  final Widget home;
  const _SplashThenHome({required this.home});

  @override
  State<_SplashThenHome> createState() => _SplashThenHomeState();
}

class _SplashThenHomeState extends State<_SplashThenHome> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => widget.home),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Center(
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20, offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.inventory_2, size: 70, color: Color(0xFF1A237E)),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Karam Stock',
              style: TextStyle(
                color: Colors.white, fontSize: 32,
                fontWeight: FontWeight.bold, letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                '🤍  اللهم صلِّ وسلم على نبينا محمد  🤍',
                style: TextStyle(
                  color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w500, height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text(
                'BY : Kareem Mohamed',
                style: TextStyle(
                  color: Colors.white70, fontSize: 16, letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}