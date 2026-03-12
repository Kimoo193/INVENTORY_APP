import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // إنشاء Super Admin لو أول مرة
    AuthService.instance.initSuperAdmin();
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final pass  = _passController.text;

    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'ادخل البريد وكلمة السر');
      return;
    }

    setState(() { _loading = true; _error = ''; });
    try {
      await AuthService.instance.login(email, pass);
      // AuthWrapper هيتعرف تلقائياً
    } on FirebaseAuthException catch (e) {
      String msg = 'فشل تسجيل الدخول';
      if (e.code == 'invalid-credential' ||
          e.code == 'wrong-password' ||
          e.code == 'user-not-found') {
        msg = 'البريد الإلكتروني أو كلمة المرور غير صحيحة';
      } else if (e.code == 'invalid-email') {
        msg = 'صيغة البريد الإلكتروني غير صحيحة';
      }
      setState(() => _error = msg);
    } catch (_) {
      setState(() => _error = 'حدث خطأ غير متوقع');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF16324F), Color(0xFF244A70), Color(0xFFF6F4EE)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: -40,
                  right: -10,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC69749).withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Positioned(
                  top: 120,
                  left: -30,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    children: [
                      const SizedBox(height: 18),
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.inventory_2_rounded, size: 58, color: Color(0xFF16324F)),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Karam Stock',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: const Text(
                          'مخزونك منظم. الوصول أسرع. والمتابعة أوضح.',
                          style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '🤍 اللهم صلِّ وسلم على نبينا محمد 🤍',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 34),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF16324F).withValues(alpha: 0.14),
                              blurRadius: 28,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'تسجيل الدخول',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'استخدم بريدك وكلمة السر للوصول إلى لوحة المخزون.',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textDirection: TextDirection.ltr,
                              decoration: InputDecoration(
                                labelText: 'البريد الإلكتروني',
                                prefixIcon: const Icon(Icons.alternate_email_rounded),
                                filled: true,
                                fillColor: const Color(0xFFF6F4EE),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: const BorderSide(color: Color(0xFF16324F), width: 1.3),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _passController,
                              obscureText: _obscure,
                              textDirection: TextDirection.ltr,
                              onSubmitted: (_) => _login(),
                              decoration: InputDecoration(
                                labelText: 'كلمة السر',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF6F4EE),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: const BorderSide(color: Color(0xFF16324F), width: 1.3),
                                ),
                              ),
                            ),
                            if (_error.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  _error,
                                  style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF16324F),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.3),
                                      )
                                    : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text('دخول', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                          SizedBox(width: 8),
                                          Icon(Icons.arrow_forward_rounded, size: 18),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'BY : Kareem Mohamed',
                        style: TextStyle(color: Colors.grey.shade200, fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}