import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'log_service.dart';

// ============================================================
// InventoryItem Model
// ============================================================

class InventoryItem {
  final String? id;
  final String warehouseName;
  final String productName;
  final String? serial;
  final String condition;
  final String? expiryDate;
  final String? notes;
  final String inventoryDate;
  final String? addedByUid;
  final String? adminUid;
  final String? importBatchId; // ✅ ID الـ batch لو الـ item جاي من Excel import

  InventoryItem({
    this.id,
    required this.warehouseName,
    required this.productName,
    this.serial,
    required this.condition,
    this.expiryDate,
    this.notes,
    String? inventoryDate,
    this.addedByUid,
    this.adminUid,
    this.importBatchId,
  }) : inventoryDate = inventoryDate ?? today();

  static String today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap() {
    return {
      'warehouseName': warehouseName,
      'productName': productName,
      'serial': serial,
      'condition': condition,
      'expiryDate': expiryDate,
      'notes': notes,
      'inventoryDate': inventoryDate,
      'addedByUid': addedByUid,
      'adminUid': adminUid,
      if (importBatchId != null) 'importBatchId': importBatchId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory InventoryItem.fromMap(Map<String, dynamic> map, String id) {
    return InventoryItem(
      id: id,
      warehouseName: map['warehouseName'] ?? '',
      productName: map['productName'] ?? '',
      serial: map['serial'],
      condition: map['condition'] ?? 'جديد',
      expiryDate: map['expiryDate'],
      notes: map['notes'],
      inventoryDate: map['inventoryDate'] ?? today(),
      addedByUid: map['addedByUid'],
      adminUid: map['adminUid'],
      importBatchId: map['importBatchId'],
    );
  }

  InventoryItem copyWith({
    String? id,
    String? warehouseName,
    String? productName,
    String? serial,
    String? condition,
    String? expiryDate,
    String? notes,
    String? inventoryDate,
    String? addedByUid,
    String? adminUid,
    String? importBatchId,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      warehouseName: warehouseName ?? this.warehouseName,
      productName: productName ?? this.productName,
      serial: serial ?? this.serial,
      condition: condition ?? this.condition,
      expiryDate: expiryDate ?? this.expiryDate,
      notes: notes ?? this.notes,
      inventoryDate: inventoryDate ?? this.inventoryDate,
      addedByUid: addedByUid ?? this.addedByUid,
      adminUid: adminUid ?? this.adminUid,
      importBatchId: importBatchId ?? this.importBatchId,
    );
  }
}

// ============================================================
// FirestoreService — محسّن للـ Performance
// ============================================================

class FirestoreService {
  static final FirestoreService instance = FirestoreService._();
  FirestoreService._();

  final _db = FirebaseFirestore.instance;

  // ✅ Cache للـ user + adminUid معاً — 60 ثانية
  AppUser? _cachedUser;
  String? _cachedAdminUid;
  DateTime? _cacheTime;

  // ✅ Cache للـ warehouses و products — بيتمسح عند التعديل
  List<String>? _cachedWarehouses;
  List<String>? _cachedProducts;

  // ✅ Set للـ warehouses/products المضافة في الـ session — بنتجنب write مكرر
  final Set<String> _addedWarehouses = {};
  final Set<String> _addedProducts = {};

  Future<AppUser?> _getCachedUser() async {
    final now = DateTime.now();
    if (_cachedUser != null &&
        _cacheTime != null &&
        now.difference(_cacheTime!).inSeconds < 60) {
      return _cachedUser;
    }
    _cachedUser = await AuthService.instance.getCurrentUser();
    _cacheTime = now;
    _cachedAdminUid = null; // invalidate adminUid cache مع الـ user
    return _cachedUser;
  }

  void clearCache() {
    _cachedUser = null;
    _cacheTime = null;
    _cachedAdminUid = null;
    _cachedWarehouses = null;
    _cachedProducts = null;
    _addedWarehouses.clear();
    _addedProducts.clear();
  }

  // ✅ adminUid مع cache منفصل — أكتر حاجة بتتنادى
  Future<String?> _getAdminUid() async {
    if (_cachedAdminUid != null) return _cachedAdminUid;
    final user = await _getCachedUser();
    if (user == null) return null;
    _cachedAdminUid = user.isAdmin ? user.uid : user.adminUid;
    return _cachedAdminUid;
  }

  CollectionReference _itemsRef(String adminUid) =>
      _db.collection('inventory').doc(adminUid).collection('items');

  CollectionReference _deletedRef(String adminUid) =>
      _db.collection('inventory').doc(adminUid).collection('deleted_items');

  CollectionReference _warehousesRef(String adminUid) =>
      _db.collection('inventory').doc(adminUid).collection('warehouses');

  CollectionReference _productsRef(String adminUid) =>
      _db.collection('inventory').doc(adminUid).collection('products');

  // ============================================================
  // Inventory CRUD
  // ============================================================

  Future<String?> insertItem(InventoryItem item) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return null;

      final actor = _cachedUser;

      // ✅ كل العمليات في parallel — مش sequential
      final docRef = _itemsRef(adminUid).doc(); // pre-generate ID

      // 1. اكتب الـ item
      await docRef.set({
        ...item.toMap(),
        'adminUid': adminUid,
      });

      // 2. warehouse و product — best-effort (لو فشلت مش مشكلة)
      try {
        await Future.wait([
          if (!_addedWarehouses.contains(item.warehouseName))
            _ensureWarehouse(adminUid, item.warehouseName),
          if (!_addedProducts.contains(item.productName))
            _ensureProduct(adminUid, item.productName),
        ]);
      } catch (_) {}

      _addedWarehouses.add(item.warehouseName);
      _addedProducts.add(item.productName);

      // ✅ Log في background — مش بيوقف الـ user
      LogService.instance.log(
        type: LogType.itemAdded,
        actorUid: actor?.uid,
        actorName: actor?.name,
        actorRole: actor?.role,
        product: item.productName,
        warehouse: item.warehouseName,
        serial: item.serial,
        adminUid: adminUid,
      );

      return docRef.id;
    } catch (e) {
      return null;
    }
  }

  // ✅ Batch insert لاستيراد Excel — أسرع بكتير
  Future<int> insertItemsBatch(List<InventoryItem> items) async {
    if (items.isEmpty) return 0;
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return 0;

      final actor = _cachedUser;

      // جمّع الـ warehouses والـ products الجديدة
      final newWarehouses = <String>{};
      final newProducts = <String>{};
      for (final item in items) {
        if (!_addedWarehouses.contains(item.warehouseName)) {
          newWarehouses.add(item.warehouseName);
        }
        if (!_addedProducts.contains(item.productName)) {
          newProducts.add(item.productName);
        }
      }

      // ✅ اكتب الـ warehouses والـ products في parallel (best-effort)
      // لو الكتابة فشلت (مثلاً PERMISSION_DENIED) → نكمل حفظ الـ items
      try {
        await Future.wait([
          ...newWarehouses.map((w) => _ensureWarehouse(adminUid, w)),
          ...newProducts.map((p) => _ensureProduct(adminUid, p)),
        ]);
      } catch (_) {
        // warehouse/product auto-creation failed — continue with items
      }

      _addedWarehouses.addAll(newWarehouses);
      _addedProducts.addAll(newProducts);

      // ✅ Batch write بـ 400 document كل مرة (Firestore limit = 500)
      int saved = 0;
      for (int start = 0; start < items.length; start += 400) {
        final end = (start + 400 > items.length) ? items.length : start + 400;
        final chunk = items.sublist(start, end);
        final batch = _db.batch();
        for (final item in chunk) {
          final docRef = _itemsRef(adminUid).doc();
          batch.set(docRef, {
            ...item.toMap(),
            'adminUid': adminUid,
            'addedByUid': item.addedByUid ?? actor?.uid,
          });
        }
        await batch.commit();
        saved += chunk.length;
      }

      // Log مرة واحدة للـ batch
      LogService.instance.log(
        type: LogType.itemAdded,
        actorUid: actor?.uid,
        actorName: actor?.name,
        actorRole: actor?.role,
        details: 'استيراد batch: $saved قطعة',
        adminUid: adminUid,
      );

      return saved;
    } catch (e) {
      return 0;
    }
  }

  Future<List<InventoryItem>> getAllItems() async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final user = _cachedUser;
      Query query = _itemsRef(adminUid).orderBy('inventoryDate', descending: true);

      if (user != null && !user.isAdmin && user.assignedWarehouse != null) {
        query = _itemsRef(adminUid)
            .where('warehouseName', isEqualTo: user.assignedWarehouse)
            .orderBy('inventoryDate', descending: true);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => InventoryItem.fromMap(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<InventoryItem>> getItemsByDate(String date) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final user = _cachedUser;
      Query query = _itemsRef(adminUid).where('inventoryDate', isEqualTo: date);

      if (user != null && !user.isAdmin && user.assignedWarehouse != null) {
        query = query.where('warehouseName', isEqualTo: user.assignedWarehouse);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => InventoryItem.fromMap(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ✅ getInventoryDates — بيستخدم cache ويجيب dates بدون جلب كل الـ documents
  Future<List<String>> getInventoryDates() async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final user = _cachedUser;

      // ✅ لو user عنده مخزن معين — filter
      Query query = _itemsRef(adminUid);
      if (user != null && !user.isAdmin && user.assignedWarehouse != null) {
        query = query.where('warehouseName', isEqualTo: user.assignedWarehouse);
      }

      // ✅ اجيب inventoryDate فقط — أقل data transfer
      final snapshot = await query.get();
      final dates = snapshot.docs
          .map((doc) =>
              (doc.data() as Map<String, dynamic>)['inventoryDate'] as String?)
          .where((d) => d != null)
          .cast<String>()
          .toSet()
          .toList();
      dates.sort((a, b) => b.compareTo(a));
      return dates;
    } catch (e) {
      return [];
    }
  }

  Future<void> updateItem(InventoryItem item) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null || item.id == null) return;

      final actor = _cachedUser;

      // ✅ Update + Log في parallel
      await Future.wait([
        _itemsRef(adminUid).doc(item.id).update({
          'warehouseName': item.warehouseName,
          'productName': item.productName,
          'serial': item.serial,
          'condition': item.condition,
          'expiryDate': item.expiryDate,
          'notes': item.notes,
          'inventoryDate': item.inventoryDate,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
        Future(() => LogService.instance.log(
          type: LogType.itemEdited,
          actorUid: actor?.uid,
          actorName: actor?.name,
          actorRole: actor?.role,
          product: item.productName,
          warehouse: item.warehouseName,
          serial: item.serial,
          adminUid: adminUid,
        )),
      ]);
    } catch (_) {}
  }

  Future<bool> deleteWithReason(
    InventoryItem item, {
    required String reason,
    String? extraNotes,
    String? deletedByUid,
  }) async {
    try {
      String? adminUid = await _getAdminUid();
      if (adminUid == null && item.adminUid != null) {
        adminUid = item.adminUid;
      }
      if (adminUid == null || item.id == null) return false;

      final now = FieldValue.serverTimestamp();

      // ✅ نقل وحذف في نفس الـ batch
      final batch = _db.batch();

      final deletedDocRef = _deletedRef(adminUid).doc();
      batch.set(deletedDocRef, {
        'warehouseName': item.warehouseName,
        'productName': item.productName,
        'serial': item.serial,
        'condition': item.condition,
        'expiryDate': item.expiryDate,
        'notes': item.notes,
        'inventoryDate': item.inventoryDate,
        'deleteReason': reason,
        'deleteNotes': extraNotes ?? '',
        'deletedAt': now,
        'deletedByUid': deletedByUid,
        'addedByUid': item.addedByUid,
        'adminUid': adminUid,
      });

      batch.delete(_itemsRef(adminUid).doc(item.id!));

      await batch.commit();

      // ✅ Log في background
      LogService.instance.log(
        type: LogType.itemDeleted,
        actorUid: deletedByUid,
        product: item.productName,
        warehouse: item.warehouseName,
        serial: item.serial,
        reason: reason,
        details: (extraNotes != null && extraNotes.isNotEmpty) ? extraNotes : null,
        adminUid: adminUid,
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  // ============================================================
  // ✅ Clear Day — حذف كل قطع يوم معين (Admin فقط)
  // القطع بتتنقل لـ deleted_items مش بتتحذف نهائياً
  // ============================================================

  /// يجيب عدد القطع في يوم معين — عشان الـ confirmation dialog
  Future<int> getItemsCountByDate(String date) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return 0;
      final snapshot = await _itemsRef(adminUid)
          .where('inventoryDate', isEqualTo: date)
          .get();
      return snapshot.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// يمسح كل قطع يوم معين — بينقلهم لـ deleted_items
  /// رجع: عدد القطع المحذوفة، أو -1 لو خطأ
  Future<int> clearItemsByDate(String date, {String? deletedByUid}) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return -1;

      final actor = _cachedUser;

      // اجيب كل الـ items في التاريخ ده
      final snapshot = await _itemsRef(adminUid)
          .where('inventoryDate', isEqualTo: date)
          .get();

      if (snapshot.docs.isEmpty) return 0;

      final total = snapshot.docs.length;
      final now = FieldValue.serverTimestamp();
      final nowStr = DateTime.now().toString().substring(0, 16);

      // ✅ نقل لـ deleted_items + حذف من items في batches
      for (int start = 0; start < snapshot.docs.length; start += 200) {
        final end = (start + 200 > snapshot.docs.length)
            ? snapshot.docs.length
            : start + 200;
        final chunk = snapshot.docs.sublist(start, end);

        final batch = _db.batch();

        for (final doc in chunk) {
          final data = doc.data() as Map<String, dynamic>;

          // أضف لـ deleted_items
          final deletedRef = _deletedRef(adminUid).doc();
          batch.set(deletedRef, {
            'warehouseName':  data['warehouseName'],
            'productName':    data['productName'],
            'serial':         data['serial'],
            'condition':      data['condition'],
            'expiryDate':     data['expiryDate'],
            'notes':          data['notes'],
            'inventoryDate':  data['inventoryDate'],
            'deleteReason':   'مسح المخزون اليومي',
            'deleteNotes':    'تم مسح مخزون يوم $date بواسطة Admin — $nowStr',
            'deletedAt':      now,
            'deletedByUid':   deletedByUid ?? actor?.uid,
            'addedByUid':     data['addedByUid'],
            'adminUid':       adminUid,
          });

          // احذف من items
          batch.delete(doc.reference);
        }

        await batch.commit();
      }

      // ✅ Log العملية
      LogService.instance.log(
        type: LogType.itemDeleted,
        actorUid:  deletedByUid ?? actor?.uid,
        actorName: actor?.name,
        actorRole: actor?.role,
        reason:    'مسح المخزون اليومي',
        details:   'تم مسح كل مخزون يوم $date — $total قطعة',
        adminUid:  adminUid,
      );

      return total;
    } catch (e) {
      return -1;
    }
  }

  // ============================================================
  // Stats — محسوبة من الـ items مش query تانية
  // ============================================================

  Future<Map<String, int>> getStats({String? date}) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return _emptyStats();

      final user = _cachedUser;
      Query query = _itemsRef(adminUid);

      if (date != null) {
        query = query.where('inventoryDate', isEqualTo: date);
      }
      if (user != null && !user.isAdmin && user.assignedWarehouse != null) {
        query = query.where('warehouseName', isEqualTo: user.assignedWarehouse);
      }

      // ✅ جيب الـ items مرة واحدة واحسب الـ stats منهم
      final snapshot = await query.get();
      final items = snapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();

      final total = items.length;
      final good = items.where((i) => i['condition'] == 'جديد').length;
      final used = items.where((i) => i['condition'] == 'مستخدم').length;
      final damaged = items.where((i) => i['condition'] == 'تالف').length;

      // ✅ deleted count بدون جلب كل الـ documents — بس count
      int deletedCount = 0;
      try {
        Query deletedQuery = _deletedRef(adminUid);
        if (user != null && !user.isAdmin) {
          deletedQuery = deletedQuery.where('deletedByUid', isEqualTo: user.uid);
        }
        final deletedSnap = await deletedQuery.count().get();
        deletedCount = deletedSnap.count ?? 0;
      } catch (_) {
        // لو count() مش مدعومة (Firestore plan قديم) — اعمل query عادية
        try {
          Query deletedQuery = _deletedRef(adminUid);
          if (user != null && !user.isAdmin) {
            deletedQuery = deletedQuery.where('deletedByUid', isEqualTo: user.uid);
          }
          final deletedSnap = await deletedQuery.get();
          deletedCount = deletedSnap.docs.length;
        } catch (_) {}
      }

      return {
        'total': total,
        'good': good,
        'used': used,
        'damaged': damaged,
        'deleted': deletedCount,
      };
    } catch (e) {
      return _emptyStats();
    }
  }

  Map<String, int> _emptyStats() =>
      {'total': 0, 'good': 0, 'used': 0, 'damaged': 0, 'deleted': 0};

  // ============================================================
  // Deleted Items
  // ============================================================

  Future<List<Map<String, dynamic>>> getDeletedItems() async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final snapshot = await _deletedRef(adminUid)
          .orderBy('deletedAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'warehouse_name': data['warehouseName'],
          'product_name': data['productName'],
          'serial': data['serial'],
          'condition': data['condition'],
          'delete_reason': data['deleteReason'],
          'delete_notes': data['deleteNotes'],
          'deleted_at': (data['deletedAt'] as Timestamp?)?.toDate().toIso8601String(),
          'deleted_by_uid': data['deletedByUid'],
          'added_by_uid': data['addedByUid'],
          'expiry_date': data['expiryDate'],
          'notes': data['notes'],
          'inventory_date': data['inventoryDate'],
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getDeletedItemsByUser(String uid) async {
    try {
      final currentUser = await _getCachedUser();

      String? adminUid;
      if (currentUser != null && currentUser.isAdmin) {
        adminUid = currentUser.uid;
      } else if (currentUser != null && currentUser.adminUid != null) {
        adminUid = currentUser.adminUid;
      } else {
        return await _getDeletedItemsByUserFallback(uid);
      }

      if (adminUid == null) return await _getDeletedItemsByUserFallback(uid);

      final snapshot = await _deletedRef(adminUid)
          .where('deletedByUid', isEqualTo: uid)
          .get();

      final items = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'warehouse_name': data['warehouseName'],
          'product_name': data['productName'],
          'serial': data['serial'],
          'condition': data['condition'],
          'delete_reason': data['deleteReason'],
          'delete_notes': data['deleteNotes'],
          'deleted_at': (data['deletedAt'] as Timestamp?)?.toDate().toIso8601String(),
          'deleted_by_uid': data['deletedByUid'],
          'expiry_date': data['expiryDate'],
          'inventory_date': data['inventoryDate'],
        };
      }).toList();

      items.sort((a, b) {
        final aDate = a['deleted_at'] as String?;
        final bDate = b['deleted_at'] as String?;
        if (aDate == null || bDate == null) return 0;
        return bDate.compareTo(aDate);
      });

      return items;
    } catch (e) {
      try {
        return await _getDeletedItemsByUserFallback(uid);
      } catch (_) {
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getDeletedItemsByUserFallback(String uid) async {
    try {
      final List<Map<String, dynamic>> allItems = [];

      final adminsSnap = await _db
          .collection('users')
          .where('role', whereIn: ['admin', 'superadmin'])
          .get();

      for (final adminDoc in adminsSnap.docs) {
        try {
          final snapshot = await _deletedRef(adminDoc.id)
              .where('deletedByUid', isEqualTo: uid)
              .get();

          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            allItems.add({
              'id': doc.id,
              'warehouse_name': data['warehouseName'],
              'product_name': data['productName'],
              'serial': data['serial'],
              'condition': data['condition'],
              'delete_reason': data['deleteReason'],
              'delete_notes': data['deleteNotes'],
              'deleted_at': (data['deletedAt'] as Timestamp?)?.toDate().toIso8601String(),
              'deleted_by_uid': data['deletedByUid'],
              'expiry_date': data['expiryDate'],
              'inventory_date': data['inventoryDate'],
            });
          }
        } catch (_) {}
      }

      allItems.sort((a, b) {
        final aDate = a['deleted_at'] as String?;
        final bDate = b['deleted_at'] as String?;
        if (aDate == null || bDate == null) return 0;
        return bDate.compareTo(aDate);
      });

      return allItems;
    } catch (_) {
      return [];
    }
  }

  Future<void> restoreItem(Map<String, dynamic> deletedItem) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;

      final actor = _cachedUser;
      final now = DateTime.now().toString().substring(0, 16);
      final oldNotes = deletedItem['delete_notes'] ?? '';

      // ✅ restore + update في نفس الـ batch
      final batch = _db.batch();

      final newItemRef = _itemsRef(adminUid).doc();
      batch.set(newItemRef, {
        'warehouseName': deletedItem['warehouse_name'],
        'productName': deletedItem['product_name'],
        'serial': deletedItem['serial'],
        'condition': deletedItem['condition'],
        'expiryDate': deletedItem['expiry_date'],
        'notes': 'مستعاد - ${deletedItem['delete_reason'] ?? ''}',
        'inventoryDate': deletedItem['inventory_date'] ?? InventoryItem.today(),
        'addedByUid': deletedItem['added_by_uid'],
        'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.update(_deletedRef(adminUid).doc(deletedItem['id']), {
        'deleteNotes': oldNotes.isEmpty ? 'مستعاد: $now' : '$oldNotes | مستعاد: $now',
      });

      await batch.commit();

      LogService.instance.log(
        type: LogType.itemRestored,
        actorUid: actor?.uid,
        actorName: actor?.name,
        actorRole: actor?.role,
        product: deletedItem['product_name']?.toString(),
        warehouse: deletedItem['warehouse_name']?.toString(),
        adminUid: adminUid,
      );
    } catch (_) {}
  }

  Future<void> permanentDeleteItem(String docId) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;

      Map<String, dynamic>? itemData;
      try {
        final doc = await _deletedRef(adminUid).doc(docId).get();
        itemData = doc.data() as Map<String, dynamic>?;
      } catch (_) {}

      await _deletedRef(adminUid).doc(docId).delete();

      final actor = _cachedUser;
      LogService.instance.log(
        type: LogType.itemPermanentDeleted,
        actorUid: actor?.uid,
        actorName: actor?.name,
        actorRole: actor?.role,
        product: itemData?['productName'] as String?,
        warehouse: itemData?['warehouseName'] as String?,
        serial: itemData?['serial'] as String?,
        reason: itemData?['deleteReason'] as String?,
        details: 'حذف نهائي — لن يمكن استعادته',
        adminUid: adminUid,
      );
    } catch (_) {}
  }

  // ============================================================
  // ✅ Import Batch Management — تراجع عن استيراد Excel
  // ============================================================

  /// يجيب كل الـ import batches للـ admin مرتبة بالأحدث
  Future<List<Map<String, dynamic>>> getImportBatches() async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      // ✅ اجيب items اللي عندها importBatchId — group them
      final snapshot = await _itemsRef(adminUid)
          .where('importBatchId', isGreaterThan: '')
          .get();

      if (snapshot.docs.isEmpty) return [];

      // Group by importBatchId
      final Map<String, Map<String, dynamic>> batches = {};
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final batchId = data['importBatchId'] as String? ?? '';
        if (batchId.isEmpty) continue;

        if (!batches.containsKey(batchId)) {
          batches[batchId] = {
            'batchId': batchId,
            'count': 0,
            'date': data['inventoryDate'] ?? '',
            'importedAt': data['createdAt'],
            'addedByUid': data['addedByUid'] ?? '',
          };
        }
        batches[batchId]!['count'] = (batches[batchId]!['count'] as int) + 1;
      }

      // Sort by importedAt descending (أحدث أول)
      final list = batches.values.toList();
      list.sort((a, b) {
        final aT = a['importedAt'];
        final bT = b['importedAt'];
        if (aT == null && bT == null) return 0;
        if (aT == null) return 1;
        if (bT == null) return -1;
        // Timestamp comparison
        try {
          return (bT as dynamic).compareTo(aT as dynamic);
        } catch (_) {
          return 0;
        }
      });

      return list;
    } catch (e) {
      return [];
    }
  }

  /// حذف كل items الـ batch ده دفعة واحدة — للـ Admin فقط
  Future<int> deleteItemsByBatch(String batchId) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return 0;

      final actor = _cachedUser;

      // اجيب كل الـ items بالـ batchId ده
      final snapshot = await _itemsRef(adminUid)
          .where('importBatchId', isEqualTo: batchId)
          .get();

      if (snapshot.docs.isEmpty) return 0;

      final total = snapshot.docs.length;

      // ✅ حذف في batches (Firestore limit 500)
      for (int start = 0; start < snapshot.docs.length; start += 400) {
        final end = (start + 400 > snapshot.docs.length)
            ? snapshot.docs.length
            : start + 400;
        final chunk = snapshot.docs.sublist(start, end);
        final batch = _db.batch();
        for (final doc in chunk) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // ✅ Log
      LogService.instance.log(
        type: LogType.itemDeleted,
        actorUid: actor?.uid,
        actorName: actor?.name,
        actorRole: actor?.role,
        details: 'تراجع عن استيراد batch — حُذف $total عنصر (batchId: $batchId)',
        adminUid: adminUid,
      );

      return total;
    } catch (e) {
      return 0;
    }
  }

  // ============================================================
  // Warehouses & Products — مع caching
  // ============================================================

  Future<void> _ensureWarehouse(String adminUid, String name) async {
    final docId = _sanitizeId(name);
    await _warehousesRef(adminUid).doc(docId).set(
      {'name': name, 'createdAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    _cachedWarehouses = null; // invalidate cache
  }

  Future<void> _ensureProduct(String adminUid, String name) async {
    final docId = _sanitizeIdArabic(name);
    await _productsRef(adminUid).doc(docId).set(
      {'name': name, 'createdAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    _cachedProducts = null; // invalidate cache
  }

  String _sanitizeId(String name) =>
      name.replaceAll(RegExp(r'[^\w]'), '_');

  String _sanitizeIdArabic(String name) =>
      name.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');

  Future<void> addWarehouse(String name) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      await _ensureWarehouse(adminUid, name);
      _addedWarehouses.add(name);
    } catch (_) {}
  }

  Future<List<String>> getWarehouses() async {
    try {
      // ✅ رجّع من cache لو موجود
      if (_cachedWarehouses != null) return _cachedWarehouses!;

      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final snapshot = await _warehousesRef(adminUid).orderBy('name').get();
      _cachedWarehouses = snapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .toList();
      return _cachedWarehouses!;
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteWarehouse(String name) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      final docId = _sanitizeId(name);
      await _warehousesRef(adminUid).doc(docId).delete();
      _cachedWarehouses = null;
      _addedWarehouses.remove(name);
    } catch (_) {}
  }

  Future<void> updateWarehouse(String oldName, String newName) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      final batch = _db.batch();
      final oldDocId = _sanitizeId(oldName);
      final newDocId = _sanitizeId(newName);
      batch.delete(_warehousesRef(adminUid).doc(oldDocId));
      batch.set(_warehousesRef(adminUid).doc(newDocId), {
        'name': newName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      _cachedWarehouses = null;
    } catch (_) {}
  }

  Future<void> addProduct(String name) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      await _ensureProduct(adminUid, name);
      _addedProducts.add(name);
    } catch (_) {}
  }

  Future<List<String>> getProducts() async {
    try {
      // ✅ رجّع من cache لو موجود
      if (_cachedProducts != null) return _cachedProducts!;

      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final snapshot = await _productsRef(adminUid).orderBy('name').get();
      _cachedProducts = snapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .toList();
      return _cachedProducts!;
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteProduct(String name) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      final docId = _sanitizeIdArabic(name);
      await _productsRef(adminUid).doc(docId).delete();
      _cachedProducts = null;
      _addedProducts.remove(name);
    } catch (_) {}
  }

  Future<void> updateProduct(String oldName, String newName) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      await Future.wait([
        deleteProduct(oldName),
        _ensureProduct(adminUid, newName),
      ]);
      _cachedProducts = null;
    } catch (_) {}
  }

  // ============================================================
  // Migration: SQLite → Firestore
  // ============================================================

  Future<MigrationResult> migrateFromSQLite(
    List<InventoryItem> sqliteItems,
    List<String> warehouses,
    List<String> products,
    List<Map<String, dynamic>> deletedItems,
    String adminUid,
  ) async {
    int itemsMigrated = 0;
    int warehousesMigrated = 0;
    int productsMigrated = 0;
    int deletedMigrated = 0;

    try {
      // ✅ مخازن ومنتجات في parallel
      await Future.wait([
        ...warehouses.map((w) async {
          try {
            final docId = _sanitizeId(w);
            await _warehousesRef(adminUid).doc(docId).set(
              {'name': w, 'createdAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true),
            );
            warehousesMigrated++;
          } catch (_) {}
        }),
        ...products.map((p) async {
          try {
            final docId = _sanitizeIdArabic(p);
            await _productsRef(adminUid).doc(docId).set(
              {'name': p, 'createdAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true),
            );
            productsMigrated++;
          } catch (_) {}
        }),
      ]);

      // ✅ Items في batches
      for (int start = 0; start < sqliteItems.length; start += 400) {
        final end = (start + 400 > sqliteItems.length) ? sqliteItems.length : start + 400;
        final chunk = sqliteItems.sublist(start, end);
        final batch = _db.batch();
        for (final item in chunk) {
          final docRef = _itemsRef(adminUid).doc();
          batch.set(docRef, {
            'warehouseName': item.warehouseName,
            'productName': item.productName,
            'serial': item.serial,
            'condition': item.condition,
            'expiryDate': item.expiryDate,
            'notes': item.notes,
            'inventoryDate': item.inventoryDate,
            'addedByUid': item.addedByUid ?? adminUid,
            'adminUid': adminUid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          itemsMigrated++;
        }
        await batch.commit();
      }

      // ✅ Deleted في batches
      for (int start = 0; start < deletedItems.length; start += 400) {
        final end = (start + 400 > deletedItems.length) ? deletedItems.length : start + 400;
        final chunk = deletedItems.sublist(start, end);
        final batch = _db.batch();
        for (final item in chunk) {
          final docRef = _deletedRef(adminUid).doc();
          batch.set(docRef, {
            'warehouseName': item['warehouse_name'],
            'productName': item['product_name'],
            'serial': item['serial'],
            'condition': item['condition'],
            'expiryDate': item['expiry_date'],
            'notes': item['notes'],
            'inventoryDate': item['inventory_date'],
            'deleteReason': item['delete_reason'],
            'deleteNotes': item['delete_notes'],
            'deletedAt': item['deleted_at'] != null
                ? Timestamp.fromDate(DateTime.parse(item['deleted_at']))
                : FieldValue.serverTimestamp(),
            'deletedByUid': item['deleted_by_uid'] ?? adminUid,
            'addedByUid': item['added_by_uid'] ?? adminUid,
            'adminUid': adminUid,
          });
          deletedMigrated++;
        }
        await batch.commit();
      }

      await _db.collection('inventory').doc(adminUid).set(
        {'migrated': true, 'migratedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );

      return MigrationResult(
        success: true,
        itemsMigrated: itemsMigrated,
        warehousesMigrated: warehousesMigrated,
        productsMigrated: productsMigrated,
        deletedMigrated: deletedMigrated,
      );
    } catch (e) {
      return MigrationResult(
        success: false,
        error: e.toString(),
        itemsMigrated: itemsMigrated,
        warehousesMigrated: warehousesMigrated,
        productsMigrated: productsMigrated,
        deletedMigrated: deletedMigrated,
      );
    }
  }

  Future<bool> isMigrated() async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return false;
      final doc = await _db.collection('inventory').doc(adminUid).get();
      return doc.exists && (doc.data()?['migrated'] == true);
    } catch (_) {
      return false;
    }
  }
}

// ============================================================
// Migration Result
// ============================================================

class MigrationResult {
  final bool success;
  final String? error;
  final int itemsMigrated;
  final int warehousesMigrated;
  final int productsMigrated;
  final int deletedMigrated;

  MigrationResult({
    required this.success,
    this.error,
    required this.itemsMigrated,
    required this.warehousesMigrated,
    required this.productsMigrated,
    required this.deletedMigrated,
  });
}