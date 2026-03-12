import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

// ============================================================
// LogService — نظام تسجيل العمليات اليومي
//
// Firestore Structure:
//   activity_logs/{YYYY-MM-DD}
//     .date, .count, .lastUpdated
//     /events/{eventId}
// ============================================================

class LogType {
  static const itemAdded            = 'item_added';
  static const itemDeleted          = 'item_deleted';
  static const itemPermanentDeleted = 'item_permanent_deleted'; // ✅ جديد
  static const itemRestored         = 'item_restored';
  static const itemEdited           = 'item_edited';
  static const itemMoved            = 'item_moved';
  static const userCreated          = 'user_created';
  static const adminCreated         = 'admin_created';
  static const userActivated        = 'user_activated';
  static const userDeactivated      = 'user_deactivated';
  static const userLogin            = 'user_login';
  static const userLogout           = 'user_logout';

  static String label(String type) {
    switch (type) {
      case itemAdded:            return 'إضافة قطعة';
      case itemDeleted:          return 'حذف قطعة';
      case itemPermanentDeleted: return 'حذف نهائي';
      case itemRestored:         return 'استعادة قطعة';
      case itemEdited:           return 'تعديل قطعة';
      case itemMoved:            return 'نقل قطعة';
      case userCreated:          return 'إنشاء مستخدم';
      case adminCreated:         return 'إنشاء Admin';
      case userActivated:        return 'تفعيل حساب';
      case userDeactivated:      return 'إيقاف حساب';
      case userLogin:            return 'تسجيل دخول';
      case userLogout:           return 'تسجيل خروج';
      default:                   return type;
    }
  }
}

class LogService {
  static final LogService instance = LogService._();
  LogService._();

  final _db = FirebaseFirestore.instance;

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  CollectionReference _eventsRef(String dateKey) =>
      _db.collection('activity_logs').doc(dateKey).collection('events');

  // ============================================================
  // ✅ سجّل حدث — مع auto-fetch للـ user لو مش متبعت
  // ============================================================
  Future<void> log({
    required String type,
    String? actorUid,
    String? actorName,
    String? actorRole,
    String? adminUid,
    String? adminName,
    String? product,
    String? warehouse,
    String? serial,
    String? reason,
    String? details,
    String? targetUserName,
    String? targetUserEmail,
  }) async {
    try {
      final dateKey = _todayKey();
      final now = DateTime.now();

      // ✅ لو مفيش actorUid، جيب الـ user الحالي
      String? fActorUid  = actorUid;
      String? fActorName = actorName;
      String? fActorRole = actorRole;
      String? fAdminUid  = adminUid;
      String? fAdminName = adminName;

      if (fActorUid == null) {
        try {
          final u = await AuthService.instance.getCurrentUser();
          if (u != null) {
            fActorUid  = u.uid;
            fActorName = u.name;
            fActorRole = u.role;
            fAdminUid ??= u.isAdmin ? u.uid : u.adminUid;
          }
        } catch (_) {}
      }

      // ✅ جيب اسم الـ Admin لو مش موجود
      if (fAdminName == null && fAdminUid != null) {
        try {
          final doc = await _db.collection('users').doc(fAdminUid).get();
          fAdminName = (doc.data()?['name'] as String?) ?? 'Admin';
        } catch (_) {}
      }

      final data = <String, dynamic>{
        'type':         type,
        'typeLabel':    LogType.label(type),
        'date':         dateKey,
        'createdAt':    FieldValue.serverTimestamp(),
        'createdAtIso': now.toIso8601String(),
        if (fActorUid        != null) 'actorUid':         fActorUid,
        if (fActorName       != null) 'actorName':        fActorName,
        if (fActorRole       != null) 'actorRole':        fActorRole,
        if (fAdminUid        != null) 'adminUid':         fAdminUid,
        if (fAdminName       != null) 'adminName':        fAdminName,
        if (product          != null) 'product':          product,
        if (warehouse        != null) 'warehouse':        warehouse,
        if (serial           != null) 'serial':           serial,
        if (reason           != null) 'reason':           reason,
        if (details          != null) 'details':          details,
        if (targetUserName   != null) 'targetUserName':   targetUserName,
        if (targetUserEmail  != null) 'targetUserEmail':  targetUserEmail,
      };

      await _eventsRef(dateKey).add(data);

      // ✅ تحديث عداد اليوم
      await _db.collection('activity_logs').doc(dateKey).set({
        'date':        dateKey,
        'count':       FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

    } catch (e) {
      // نطبع الـ error في debug mode فقط
      assert(() {
        // ignore: avoid_print
        print('⚠️ LogService error: $e');
        return true;
      }());
    }
  }

  // ============================================================
  // ✅ log Login — بيتنادى من auth_wrapper بعد التسجيل
  // ============================================================
  Future<void> logLogin(AppUser user) async {
    await log(
      type: LogType.userLogin,
      actorUid:  user.uid,
      actorName: user.name,
      actorRole: user.role,
      adminUid:  user.isAdmin ? user.uid : user.adminUid,
    );
  }

  // ============================================================
  // ✅ log Logout
  // ============================================================
  Future<void> logLogout(AppUser user) async {
    await log(
      type: LogType.userLogout,
      actorUid:  user.uid,
      actorName: user.name,
      actorRole: user.role,
      adminUid:  user.isAdmin ? user.uid : user.adminUid,
    );
  }

  // ============================================================
  // ✅ log User Created — بيتنادى من users_screen + super_admin_screen
  // ============================================================
  Future<void> logUserCreated({
    required String createdByUid,
    required String createdByName,
    required String createdByRole,
    required String newUserName,
    required String newUserEmail,
    required String newUserRole,
    String? adminUid,
  }) async {
    await log(
      type: newUserRole == 'admin' ? LogType.adminCreated : LogType.userCreated,
      actorUid:        createdByUid,
      actorName:       createdByName,
      actorRole:       createdByRole,
      targetUserName:  newUserName,
      targetUserEmail: newUserEmail,
      adminUid:        adminUid ?? createdByUid,
    );
  }

  // ============================================================
  // ✅ جيب كل الأيام اللي عندها logs
  // ============================================================
  Future<List<Map<String, dynamic>>> getLogDates() async {
    try {
      final snap = await _db
          .collection('activity_logs')
          .orderBy('date', descending: true)
          .limit(90)
          .get();
      return snap.docs.map((d) {
        final data = d.data();
        return {
          'date':  d.id,
          'count': data['count'] ?? 0,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // ✅ جيب events يوم معين
  // ============================================================
  Future<List<Map<String, dynamic>>> getEventsByDate(String dateKey) async {
    try {
      final snap = await _eventsRef(dateKey).get();
      final items = snap.docs.map((doc) {
        final d = Map<String, dynamic>.from(doc.data() as Map);
        d['id'] = doc.id;
        return d;
      }).toList();

      // رتّب في Dart باستخدام createdAtIso (نتجنب Composite Index)
      items.sort((a, b) {
        final aS = a['createdAtIso'] as String? ?? '';
        final bS = b['createdAtIso'] as String? ?? '';
        return bS.compareTo(aS);
      });

      return items;
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // ✅ استرجاع المحذوف نهائياً من الـ Logs
  // ============================================================
  Future<List<Map<String, dynamic>>> getPermanentlyDeletedItems({
    int limitDays = 365,
  }) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: limitDays));
      final cutoffKey =
          '${cutoff.year}-${cutoff.month.toString().padLeft(2,'0')}-${cutoff.day.toString().padLeft(2,'0')}';

      // جيب كل الأيام في النطاق الزمني
      final datesSnap = await _db
          .collection('activity_logs')
          .where('date', isGreaterThanOrEqualTo: cutoffKey)
          .get();

      final List<Map<String, dynamic>> result = [];

      for (final dateDoc in datesSnap.docs) {
        final evSnap = await dateDoc.reference
            .collection('events')
            .where('type', isEqualTo: LogType.itemPermanentDeleted)
            .get();

        for (final doc in evSnap.docs) {
          final d = Map<String, dynamic>.from(doc.data() as Map);
          d['logId'] = doc.id;
          d['logDate'] = dateDoc.id;
          result.add(d);
        }
      }

      // رتّب بالأحدث أولاً
      result.sort((a, b) {
        final aS = a['createdAtIso'] as String? ?? '';
        final bS = b['createdAtIso'] as String? ?? '';
        return bS.compareTo(aS);
      });

      return result;
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // ✅ حذف logs قديمة (cleanup)
  // ============================================================
  Future<int> deleteOldLogs({int olderThanDays = 365}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
      final cutoffKey =
          '${cutoff.year}-${cutoff.month.toString().padLeft(2,'0')}-${cutoff.day.toString().padLeft(2,'0')}';
      final snap = await _db
          .collection('activity_logs')
          .where('date', isLessThan: cutoffKey)
          .get();
      int deleted = 0;
      for (final doc in snap.docs) {
        final evSnap = await doc.reference.collection('events').get();
        for (final e in evSnap.docs) {
          await e.reference.delete();
        }
        await doc.reference.delete();
        deleted++;
      }
      return deleted;
    } catch (_) {
      return 0;
    }
  }
}