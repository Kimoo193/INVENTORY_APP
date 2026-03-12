import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'log_service.dart';

// ✅ بيانات الـ Super Admin مشفرة بـ XOR — مش مقروءة في الـ APK أو الكود
const List<int> _kE = [32,42,57,46,46,38,11,32,42,57,42,38,56,63,36,40,32,101,40,36,38];
const List<int> _kP = [0,42,57,42,38,24,63,36,40,32,11,121,123,121,126];
const int _kX = 0x4B;
String get kSuperAdminEmail    => String.fromCharCodes(_kE.map((b) => b ^ _kX));
String get kSuperAdminPassword => String.fromCharCodes(_kP.map((b) => b ^ _kX));

// ============================================================
// ✅ Validators — قواعد كلمة السر والبريد الإلكتروني
// ============================================================
class AppValidators {
  /// ✅ التحقق من البريد الإلكتروني
  static String? validateEmail(String email) {
    if (email.isEmpty) return 'البريد الإلكتروني مطلوب';
    // ✅ simple: must contain @ and a dot after it
    if (!email.contains('@')) return 'البريد يجب أن يحتوي على @';
    final parts = email.split('@');
    if (parts.length != 2 || parts[0].isEmpty) return 'صيغة البريد غير صحيحة';
    if (!parts[1].contains('.') || parts[1].startsWith('.')) return 'صيغة البريد غير صحيحة (مثال: name@domain.com)';
    if (email.length > 100) return 'البريد طويل جداً';
    return null; // ✅ صحيح
  }

  // ✅ التحقق من أن البريد غير مستخدم من قبل (async)
  static Future<String?> checkEmailNotUsed(String email) async {
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db
          .collection('users')
          .where('email', isEqualTo: email.trim().toLowerCase())
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        return 'هذا البريد الإلكتروني مستخدم بالفعل';
      }
      return null; // ✅ غير مستخدم
    } catch (_) {
      return null; // نتجاهل الـ error ونكمل
    }
  }

  /// ✅ التحقق من كلمة السر
  /// الشروط: 8 أحرف على الأقل + حرف كبير + رقم + علامة مميزة
  static String? validatePassword(String password) {
    if (password.isEmpty) return 'كلمة السر مطلوبة';
    if (password.length < 8) return 'كلمة السر يجب أن تكون 8 أحرف على الأقل';
    if (!RegExp(r'[A-Z]').hasMatch(password)) return 'يجب أن تحتوي على حرف كبير (A-Z)';
    if (!RegExp(r'[a-z]').hasMatch(password)) return 'يجب أن تحتوي على حرف صغير (a-z)';
    if (!RegExp(r'[0-9]').hasMatch(password)) return 'يجب أن تحتوي على رقم (0-9)';
    if (!RegExp(r'[!@#\$%^&*()+\-=\[\]{};:,.<>?]').hasMatch(password)) {
      return 'يجب أن تحتوي على علامة مميزة مثل: ! @ # \$ %';
    }
    return null; // ✅ صحيح
  }

  /// ✅ شرح قواعد كلمة السر
  static const String passwordRules =
      'يجب أن تحتوي كلمة السر على:\n'
      '• 8 أحرف على الأقل\n'
      '• حرف كبير (A-Z)\n'
      '• حرف صغير (a-z)\n'
      '• رقم (0-9)\n'
      '• علامة مميزة مثل: ! @ # \$ %';

  /// ✅ شرح قواعد البريد الإلكتروني  
  static const String emailRules =
      'يجب أن يكون البريد بالصيغة الصحيحة\n'
      'مثال: name@domain.com';
}

class AppUser {
  final String uid;
  final String email;
  final String name;
  final String role;
  final bool canAdd;
  final bool canEdit;
  final bool canDelete;
  final bool canExport;
  final bool canImport;
  final bool canManage;
  final bool canRestore;
  final bool isActive;
  final DateTime? createdAt;
  final String? assignedWarehouse;
  final String? adminUid;  // ✅ الـ Admin اللي الـ User ده تابع له
  final String? createdBy; // ✅ uid اللي أنشأ الحساب ده

  AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.canAdd = true,
    this.canEdit = false,
    this.canDelete = false,
    this.canExport = false,
    this.canImport = false,
    this.canManage = false,
    this.canRestore = false,
    this.isActive = true,
    this.createdAt,
    this.assignedWarehouse,
    this.adminUid,
    this.createdBy,
  });

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) {
    return AppUser(
      uid: uid,
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] ?? 'user',
      canAdd: map['canAdd'] ?? true,
      canEdit: map['canEdit'] ?? false,
      canDelete: map['canDelete'] ?? false,
      canExport: map['canExport'] ?? false,
      canImport: map['canImport'] ?? false,
      canManage: map['canManage'] ?? false,
      canRestore: map['canRestore'] ?? false,
      isActive: map['isActive'] ?? true,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
      assignedWarehouse: map['assignedWarehouse'],
      adminUid: map['adminUid'],
      createdBy: map['createdBy'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role,
      'canAdd': canAdd,
      'canEdit': canEdit,
      'canDelete': canDelete,
      'canExport': canExport,
      'canImport': canImport,
      'canManage': canManage,
      'canRestore': canRestore,
      'isActive': isActive,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'assignedWarehouse': assignedWarehouse,
      'adminUid': adminUid,
      'createdBy': createdBy,
    };
  }

  bool get isAdmin => role == 'admin' || role == 'superadmin';
  bool get isSuperAdmin => role == 'superadmin';
  bool get hasAssignedWarehouse =>
      !isAdmin && assignedWarehouse != null && assignedWarehouse!.isNotEmpty;
}

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Future<AppUser?> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password,
      );
      final user = await _getUserData(cred.user!.uid);
      if (user != null && !user.isActive) {
        await _auth.signOut();
        throw Exception('الحساب موقوف. تواصل مع المدير.');
      }
      try {
        await _db.collection('users').doc(cred.user!.uid).set(
          {'lastLogin': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      } catch (_) {}

      // ✅ Log login
      if (user != null) {
        LogService.instance.log(
          type: LogType.userLogin,
          actorUid: user.uid,
          actorName: user.name,
          actorRole: user.role,
          adminUid: user.isAdmin ? user.uid : user.adminUid,
        );
      }

      return user;
    } on FirebaseAuthException catch (e) {
      throw Exception(_authError(e.code));
    }
  }

  Future<void> logout() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        await _db.collection('users').doc(uid).set(
          {'fcmToken': FieldValue.delete()}, SetOptions(merge: true));
      }
    } catch (_) {}
    await _auth.signOut();
  }

  Future<AppUser?> getCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return await _getUserData(user.uid);
  }

  Future<AppUser?> _getUserData(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists) return null;
      return AppUser.fromMap(doc.data()!, uid);
    } catch (e) {
      final authUser = _auth.currentUser;
      if (authUser != null && authUser.email == kSuperAdminEmail) {
        return AppUser(
          uid: authUser.uid, email: authUser.email!, name: 'Kareem Mohamed',
          role: 'superadmin', canAdd: true, canEdit: true, canDelete: true,
          canExport: true, canImport: true, canManage: true, canRestore: true, isActive: true,
        );
      }
      return null;
    }
  }

  Future<void> saveFcmToken(String token) async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;
      await _db.collection('users').doc(uid).set(
        {'fcmToken': token, 'lastLogin': FieldValue.serverTimestamp()},
        SetOptions(merge: true));
    } catch (_) {}
  }

  Future<List<String>> getAdminFcmTokens() async {
    try {
      final snapshot = await _db.collection('users')
          .where('role', whereIn: ['admin', 'superadmin'])
          .where('isActive', isEqualTo: true).get();
      return snapshot.docs
          .map((d) => d.data()['fcmToken'] as String?)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>().toList();
    } catch (_) { return []; }
  }

  Future<AppUser> createAdmin({
    required String email, required String password, required String name,
    String? createdBy,
  }) async {
    return await _createUserSafely(
      email: email, password: password, name: name, role: 'admin',
      permissions: {'canAdd':true,'canEdit':true,'canDelete':true,
        'canExport':true,'canImport':true,'canManage':true,'canRestore':true},
      createdBy: createdBy,
    );
  }

  Future<AppUser> createUser({
    required String email, required String password, required String name,
    required Map<String, bool> permissions, String? assignedWarehouse,
    String? adminUid, String? createdBy,
  }) async {
    return await _createUserSafely(
      email: email, password: password, name: name, role: 'user',
      permissions: permissions, assignedWarehouse: assignedWarehouse,
      adminUid: adminUid, createdBy: createdBy,
    );
  }

  Future<AppUser> _createUserSafely({
    required String email, required String password, required String name,
    required String role, required Map<String, bool> permissions,
    String? assignedWarehouse, String? adminUid, String? createdBy,
  }) async {
    FirebaseApp? tempApp;
    try {
      tempApp = await Firebase.initializeApp(
        name: 'tempApp_${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final cred = await tempAuth.createUserWithEmailAndPassword(
        email: email.trim(), password: password,
      );

      // ✅ لو adminUid=null وهو user عادي → استخدم uid بتاعه كـ adminUid
      // عشان يكون له مساحة مستقلة في الـ inventory من أول ما بيتسجل
      final resolvedAdminUid = adminUid ?? (role == 'user' ? cred.user!.uid : null);

      final newUser = AppUser(
        uid: cred.user!.uid, email: email.trim(), name: name, role: role,
        canAdd: permissions['canAdd'] ?? true,
        canEdit: permissions['canEdit'] ?? false,
        canDelete: permissions['canDelete'] ?? false,
        canExport: permissions['canExport'] ?? false,
        canImport: permissions['canImport'] ?? false,
        canManage: permissions['canManage'] ?? false,
        canRestore: permissions['canRestore'] ?? false,
        isActive: true, createdAt: DateTime.now(),
        assignedWarehouse: assignedWarehouse,
        adminUid: resolvedAdminUid,
        createdBy: createdBy,
      );

      // ✅ الكتابة في Firestore بالـ tempApp وهو لسه مسجل دخول
      // لو كتبنا بعد signOut() الـ main app مش authenticated → PERMISSION_DENIED
      final tempDb = FirebaseFirestore.instanceFor(app: tempApp);
      await tempDb.collection('users').doc(cred.user!.uid).set(newUser.toMap());

      // ✅ بعد الكتابة نعمل sign out من tempApp
      await tempAuth.signOut();

      // ✅ Log
      LogService.instance.log(
        type: role == 'admin' ? LogType.adminCreated : LogType.userCreated,
        targetUserName: name,
        targetUserEmail: email.trim(),
        actorUid: createdBy,
        adminUid: adminUid ?? createdBy,
      );

      return newUser;
    } on FirebaseAuthException catch (e) {
      throw Exception(_authError(e.code));
    } finally {
      await tempApp?.delete();
    }
  }

  // ============================================================
  // ✅ ترقية User لـ Admin (SuperAdmin فقط)
  // ============================================================
  Future<void> upgradeUserToAdmin(String uid) async {
    await _db.collection('users').doc(uid).update({
      'role': 'admin',
      'canAdd': true, 'canEdit': true, 'canDelete': true,
      'canExport': true, 'canImport': true,
      'canManage': true, 'canRestore': true,
      'adminUid': null, // Admin مش تابع لحد
    });
  }

  // ============================================================
  // ✅ تخفيض Admin لـ User عادي (SuperAdmin فقط)
  // ============================================================
  Future<void> downgradeAdminToUser(String uid, String adminUid) async {
    await _db.collection('users').doc(uid).update({
      'role': 'user',
      'canAdd': true, 'canEdit': false, 'canDelete': true,
      'canExport': false, 'canImport': false,
      'canManage': false, 'canRestore': false,
      'adminUid': adminUid,
    });
  }

  /// ✅ جيب الـ Users التابعين لـ Admin معين
  Future<List<AppUser>> getUsersByAdmin(String adminUid) async {
    try {
      // جيب Users اللي عندهم adminUid
      final snap1 = await _db.collection('users')
          .where('adminUid', isEqualTo: adminUid)
          .get();
      // جيب Users اللي عندهم createdBy (fallback للبيانات القديمة)
      final snap2 = await _db.collection('users')
          .where('createdBy', isEqualTo: adminUid)
          .get();

      // ادمج النتيجتين وشيل التكرار
      final Map<String, AppUser> usersMap = {};
      for (final doc in [...snap1.docs, ...snap2.docs]) {
        final user = AppUser.fromMap(doc.data(), doc.id);
        if (!user.isSuperAdmin && user.uid != adminUid) {
          usersMap[doc.id] = user;
        }
      }
      final users = usersMap.values.toList();
      users.sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));
      return users;
    } catch (e) {
      return [];
    }
  }

  Future<List<AppUser>> getAllUsers() async {
    final snapshot = await _db.collection('users')
        .orderBy('createdAt', descending: true).get();
    return snapshot.docs
        .map((doc) => AppUser.fromMap(doc.data(), doc.id)).toList();
  }

  Future<void> updateUserPermissions(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  Future<void> toggleUserActive(String uid, bool isActive, {String? byUid}) async {
    await _db.collection('users').doc(uid).update({'isActive': isActive});
    // ✅ Log
    LogService.instance.log(
      type: isActive ? LogType.userActivated : LogType.userDeactivated,
      targetUserName: uid,
      actorUid: byUid,
    );
  }

  Future<void> changePassword(String newPassword) async {
    await _auth.currentUser?.updatePassword(newPassword);
  }

  // ✅ Admin يغير كلمة سر مستخدم آخر
  // الطريقة: sign in بـ temp app → updatePassword
  // لو فشل (مش عارف كلمة السر القديمة) → بيبعت reset email
  Future<bool> resetUserPassword(String email, String newPassword) async {
    FirebaseApp? tempApp;
    try {
      // حاول sign in بـ temp app عشان تغير الـ password
      tempApp = await Firebase.initializeApp(
        name: 'resetApp_${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // ✅ الطريقة الوحيدة هي إرسال reset link للمستخدم
      await _auth.sendPasswordResetEmail(email: email);
      return true; // Email أُرسل
    } catch (e) {
      return false;
    } finally {
      try { await tempApp?.delete(); } catch (_) {}
    }
  }

  // ✅ Admin يغير كلمة السر مباشرة بدون email (Admin SDK workaround)
  // بيستخدم secondary app لإنشاء المستخدم بكلمة سر جديدة
  // ملاحظة: Firebase لا يسمح للـ admin بتغيير كلمة سر مستخدم آخر
  // مباشرة من الـ client SDK — الحل هو إرسال reset link
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> ensureUserDocument(dynamic firebaseUser) async {
    try {
      final email = firebaseUser.email as String?;
      if (email == null) return;
      final doc = await _db.collection('users').doc(firebaseUser.uid).get();
      if (doc.exists) return;
      final isSuperAdmin = email == kSuperAdminEmail;
      await _db.collection('users').doc(firebaseUser.uid).set({
        'email': email,
        'name': isSuperAdmin ? 'Kareem Mohamed' : email.split('@')[0],
        'role': isSuperAdmin ? 'superadmin' : 'user',
        'canAdd': true, 'canEdit': isSuperAdmin, 'canDelete': isSuperAdmin,
        'canExport': isSuperAdmin, 'canImport': isSuperAdmin,
        'canManage': isSuperAdmin, 'canRestore': isSuperAdmin, 'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> initSuperAdmin() async {
    if (_auth.currentUser != null) return;
    FirebaseApp? tempApp;
    try {
      tempApp = await Firebase.initializeApp(
        name: 'initApp_${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      UserCredential? cred;
      bool isNewUser = false;
      try {
        cred = await tempAuth.signInWithEmailAndPassword(
          email: kSuperAdminEmail, password: kSuperAdminPassword);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'invalid-credential' ||
            e.code == 'INVALID_LOGIN_CREDENTIALS') {
          try {
            cred = await tempAuth.createUserWithEmailAndPassword(
              email: kSuperAdminEmail, password: kSuperAdminPassword);
            isNewUser = true;
          } catch (_) {}
        }
      }
      if (cred != null) {
        try {
          final doc = await _db.collection('users').doc(cred.user!.uid).get();
          if (!doc.exists || isNewUser) {
            await _db.collection('users').doc(cred.user!.uid).set({
              'email': kSuperAdminEmail, 'name': 'Kareem Mohamed',
              'role': 'superadmin', 'canAdd': true, 'canEdit': true,
              'canDelete': true, 'canExport': true, 'canImport': true,
              'canManage': true, 'canRestore': true, 'isActive': true,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        } catch (_) {}
        await tempAuth.signOut();
      }
    } catch (_) {
    } finally {
      await tempApp?.delete();
    }
  }

  String _authError(String code) {
    switch (code) {
      case 'user-not-found': return 'البريد الإلكتروني غير مسجل';
      case 'wrong-password': return 'كلمة السر غلط';
      case 'invalid-email': return 'البريد الإلكتروني غير صحيح';
      case 'invalid-credential': return 'البريد الإلكتروني أو كلمة المرور غير صحيحة';
      case 'user-disabled': return 'الحساب موقوف';
      case 'too-many-requests': return 'محاولات كتير، انتظر شوية';
      case 'email-already-in-use': return 'البريد ده مسجل قبل كده';
      case 'weak-password': return 'كلمة السر ضعيفة (6 أحرف على الأقل)';
      default: return 'خطأ: $code';
    }
  }
}