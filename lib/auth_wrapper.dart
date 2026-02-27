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

            return authenticatedHome;
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