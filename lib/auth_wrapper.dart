import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import 'auth_service.dart';
import 'notification_service.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({
    super.key,
    required this.authenticatedHome,
  });

  final Widget authenticatedHome;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // جاري التحميل
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1A237E),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        // مش مسجل دخول
        if (!snapshot.hasData || snapshot.data == null) {
          // ✅ وقّف الـ listener عند الخروج
          NotificationService.instance.stopListening();
          return const LoginScreen();
        }

        // مسجل دخول — تحقق من بياناته في Firestore
        return FutureBuilder<AppUser?>(
          future: AuthService.instance.getCurrentUser(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF1A237E),
                body: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              );
            }

            final appUser = userSnapshot.data;

            // لو الحساب موقوف
            if (appUser != null && !appUser.isActive) {
              FirebaseAuth.instance.signOut();
              return const LoginScreen();
            }

            // ✅ ابدأ الـ Notification Listener للـ Admins فقط
            if (appUser != null && appUser.isAdmin) {
              NotificationService.instance
                  .startListening(snapshot.data!.uid);
            }

            // لو مش موجود في Firestore — اعمل document في الخلفية
            if (appUser == null) {
              _ensureUserDocument(snapshot.data!);
            }

            return _SplashThenHome(home: authenticatedHome);
          },
        );
      },
    );
  }

  void _ensureUserDocument(User firebaseUser) async {
    try {
      await AuthService.instance.ensureUserDocument(firebaseUser);
    } catch (_) {}
  }
}

/// ✅ يعرض السبلاش ثم يعرض الـ Home في نفس المكان (بدون Navigator.pushReplacement)
/// السبب: pushReplacement كانت بتشيل AuthWrapper من الـ Stack فـ logout مكانش بيشتغل
class _SplashThenHome extends StatefulWidget {
  final Widget home;
  const _SplashThenHome({required this.home});

  @override
  State<_SplashThenHome> createState() => _SplashThenHomeState();
}

class _SplashThenHomeState extends State<_SplashThenHome> {
  bool _showHome = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showHome = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // لو خلص الـ splash، اعرض الـ Home مباشرة (AuthWrapper يفضل في الـ stack)
    if (_showHome) return widget.home;
    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.inventory_2,
                    size: 70, color: Color(0xFF1A237E)),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Karam Stock',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
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
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.6,
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
                  color: Colors.white70,
                  fontSize: 16,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}