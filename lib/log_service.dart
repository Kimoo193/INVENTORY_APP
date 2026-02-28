import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

// ============================================================
// LogService — نظام تسجيل العمليات اليومي
//
// Firestore Structure:
//   activity_logs/{YYYY-MM-DD}        ← document لكل يوم
//     .date, .count, .lastUpdated
//     /events/{eventId}               ← كل حدث
//       type, typeLabel, actorUid, actorName, actorRole,
//       adminUid, adminName,
//       product, warehouse, serial,
//       reason, details,
//       targetUserName, targetUserEmail,
//       createdAt (Timestamp), createdAtIso (String)
// ============================================================

class LogType {
  static const itemAdded       = 'item_added';
  static const itemDeleted     = 'item_deleted';
  static const itemRestored    = 'item_restored';
  static const itemEdited      = 'item_edited';
  static const itemMoved       = 'item_moved';
  static const userCreated     = 'user_created';
  static const adminCreated    = 'admin_created';
  static const userActivated   = 'user_activated';
  static const userDeactivated = 'user_deactivated';
  static const userLogin       = 'user_login';
  static const userLogout      = 'user_logout';

  static String label(String type) {
    switch (type) {
      case itemAdded:       return 'إضافة قطعة';
      case itemDeleted:     return 'حذف قطعة';
      case itemRestored:    return 'استعادة قطعة';
      case itemEdited:      return 'تعديل قطعة';
      case itemMoved:       return 'نقل قطعة';
      case userCreated:     return 'إنشاء مستخدم';
      case adminCreated:    return 'إنشاء Admin';
      case userActivated:   return 'تفعيل حساب';
      case userDeactivated: return 'إيقاف حساب';
      case userLogin:       return 'تسجيل دخول';
      case userLogout:      return 'تسجيل خروج';
      default:              return type;
    }
  }
}

class LogService {
  static final LogService instance = LogService._();
  LogService._();

  final _db = FirebaseFirestore.instance;

  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  CollectionReference _eventsRef(String dateKey) =>
      _db.collection('activity_logs').doc(dateKey).collection('events');

  // ============================================================
  // ✅ سجّل حدث
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

      await _db.collection('activity_logs').doc(dateKey).set({
        'date': dateKey,
        'count': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

    } catch (_) {}
  }

  // ============================================================
  // ✅ جيب كل أيام اللي عندها logs
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
  // ✅ جيب events يوم معين — بدون composite index
  // ============================================================
  Future<List<Map<String, dynamic>>> getEventsByDate(String dateKey) async {
    try {
      final snap = await _eventsRef(dateKey).get();
      final items = snap.docs.map((doc) {
        final d = Map<String, dynamic>.from(doc.data() as Map);
        d['id'] = doc.id;
        return d;
      }).toList();

      // رتّب في Dart باستخدام createdAtIso
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
  // ✅ حذف logs قديمة
  // ============================================================
  Future<int> deleteOldLogs({int olderThanDays = 365}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: olderThanDays));
      final cutoffKey =
          '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';
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