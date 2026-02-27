import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'auth_service.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _db = FirebaseFirestore.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  StreamSubscription? _notifSubscription;
  String? _currentUserUid;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // ✅ بدون const هنا — objects خارجية مش compile-time constants
    final androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final initSettings =
        InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {},
    );

    // إنشاء Notification Channel لـ Android 8+
    final androidChannel = AndroidNotificationChannel(
      'karamstock_channel',
      'Karam Stock',
      description: 'إشعارات Karam Stock',
      importance: Importance.high,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> startListening(String uid) async {
    _currentUserUid = uid;
    await _notifSubscription?.cancel();

    _notifSubscription = _db
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .where('read', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;

          _showLocalNotification(
            title: data['title'] ?? 'Karam Stock',
            body: data['body'] ?? '',
            id: change.doc.id.hashCode,
          );

          change.doc.reference
              .update({'read': true}).catchError((_) {});
        }
      }
    }, onError: (_) {});
  }

  Future<void> stopListening() async {
    await _notifSubscription?.cancel();
    _notifSubscription = null;
    _currentUserUid = null;
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required int id,
  }) async {
    // ✅ بدون const
    final androidDetails = AndroidNotificationDetails(
      'karamstock_channel',
      'Karam Stock',
      channelDescription: 'إشعارات Karam Stock',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
    );

    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _notifyAdmins({
    required String title,
    required String body,
    required String type,
    Map<String, String>? extra,
  }) async {
    try {
      final snapshot = await _db
          .collection('users')
          .where('role', whereIn: ['admin', 'superadmin'])
          .where('isActive', isEqualTo: true)
          .get();

      if (snapshot.docs.isEmpty) return;

      final batch = _db.batch();

      for (final doc in snapshot.docs) {
        if (doc.id == _currentUserUid) continue;

        final notifRef = _db
            .collection('notifications')
            .doc(doc.id)
            .collection('items')
            .doc();

        batch.set(notifRef, {
          'title': title,
          'body': body,
          'type': type,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
          'extra': extra ?? {},
        });
      }

      await batch.commit();
    } catch (_) {}
  }

  Future<void> notifyItemAdded({
    required String productName,
    required String warehouseName,
    required String addedByName,
  }) async {
    await _notifyAdmins(
      title: '📦 قطعة جديدة أُضيفت',
      body: '$addedByName أضاف: $productName — المخزن: $warehouseName',
      type: 'item_added',
      extra: {'product': productName, 'warehouse': warehouseName},
    );
  }

  Future<void> notifyItemDeleted({
    required String productName,
    required String reason,
    required String deletedByName,
  }) async {
    await _notifyAdmins(
      title: '🗑️ قطعة محذوفة',
      body: '$deletedByName حذف: $productName — السبب: $reason',
      type: 'item_deleted',
      extra: {'product': productName, 'reason': reason},
    );
  }

  Future<void> notifyUserCreated({
    required String newUserName,
    required String newUserEmail,
    required String createdByName,
  }) async {
    await _notifyAdmins(
      title: '👤 مستخدم جديد',
      body: '$createdByName أنشأ حساب لـ: $newUserName',
      type: 'user_created',
      extra: {'name': newUserName, 'email': newUserEmail},
    );
  }
}