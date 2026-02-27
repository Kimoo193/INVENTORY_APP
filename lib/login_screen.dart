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
    if (_emailController.text.isEmpty || _passController.text.isEmpty) {
      setState(() => _error = 'ادخل البريد وكلمة السر');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      await AuthService.instance.login(
        _emailController.text,
        _passController.text,
      );
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
        backgroundColor: const Color(0xFF1A237E),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                // أيقونة
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.inventory_2, size: 60, color: Color(0xFF1A237E)),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Karam Stock',
                  style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                const Text(
                  '🤍  اللهم صلِّ وسلم على نبينا محمد  🤍',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'سجّل دخولك للمتابعة',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 48),

                // Card تسجيل الدخول
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'تسجيل الدخول',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),

                      // البريد الإلكتروني
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: 'البريد الإلكتروني',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // كلمة السر
                      TextField(
                        controller: _passController,
                        obscureText: _obscure,
                        textDirection: TextDirection.ltr,
                        onSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'كلمة السر',
                          prefixIcon: const Icon(Icons.lock_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),

                      if (_error.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            _error,
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // زرار الدخول
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _loading
                              ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                              : const Text('دخول', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),

                
                const SizedBox(height: 12),
                const Text(
                  'BY : Kareem Mohamed',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}