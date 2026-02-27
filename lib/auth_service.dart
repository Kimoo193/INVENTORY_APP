import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

const String kSuperAdminEmail = 'kareem@karamstock.com';
const String kSuperAdminPassword = 'KaramStock@2025';

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
          canExport: true, canImport: true, canManage: true, isActive: true,
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
        'canExport':true,'canImport':true,'canManage':true},
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
      await tempAuth.signOut();

      final newUser = AppUser(
        uid: cred.user!.uid, email: email.trim(), name: name, role: role,
        canAdd: permissions['canAdd'] ?? true,
        canEdit: permissions['canEdit'] ?? false,
        canDelete: permissions['canDelete'] ?? false,
        canExport: permissions['canExport'] ?? false,
        canImport: permissions['canImport'] ?? false,
        canManage: permissions['canManage'] ?? false,
        isActive: true, createdAt: DateTime.now(),
        assignedWarehouse: assignedWarehouse,
        adminUid: adminUid,
        createdBy: createdBy,
      );
      await _db.collection('users').doc(cred.user!.uid).set(newUser.toMap());
      return newUser;
    } on FirebaseAuthException catch (e) {
      throw Exception(_authError(e.code));
    } finally {
      await tempApp?.delete();
    }
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

  Future<void> toggleUserActive(String uid, bool isActive) async {
    await _db.collection('users').doc(uid).update({'isActive': isActive});
  }

  Future<void> changePassword(String newPassword) async {
    await _auth.currentUser?.updatePassword(newPassword);
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
        'canManage': isSuperAdmin, 'isActive': true,
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
              'canManage': true, 'isActive': true,
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