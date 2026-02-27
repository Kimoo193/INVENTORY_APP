import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

// ============================================================
// InventoryItem Model
// ============================================================

class InventoryItem {
  final String? id; // Firestore document ID
  final String warehouseName;
  final String productName;
  final String? serial;
  final String condition;
  final String? expiryDate;
  final String? notes;
  final String inventoryDate;
  final String? addedByUid;
  final String? adminUid; // ✅ Admin صاحب البيانات

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
    );
  }
}

// ============================================================
// FirestoreService
// ============================================================

class FirestoreService {
  static final FirestoreService instance = FirestoreService._();
  FirestoreService._();

  final _db = FirebaseFirestore.instance;

  // ✅ Helper: جيب adminUid الخاص بالـ user الحالي
  // لو Admin → uid بتاعه
  // لو User → adminUid المحفوظ في بياناته
  Future<String?> _getAdminUid() async {
    final user = await AuthService.instance.getCurrentUser();
    if (user == null) return null;
    if (user.isAdmin) return user.uid;
    return user.adminUid; // ✅ محفوظ في Firestore
  }

  // ✅ Shortcut للـ collection
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

      final docRef = await _itemsRef(adminUid).add({
        ...item.toMap(),
        'adminUid': adminUid,
      });

      // ✅ تأكد إن المخزن والمنتج محفوظين
      await addWarehouse(item.warehouseName);
      await addProduct(item.productName);

      return docRef.id;
    } catch (e) {
      return null;
    }
  }

  Future<List<InventoryItem>> getAllItems() async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final user = await AuthService.instance.getCurrentUser();
      Query query = _itemsRef(adminUid).orderBy('inventoryDate', descending: true);

      // ✅ User بيشوف بس مخزنه
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

      final user = await AuthService.instance.getCurrentUser();
      Query query = _itemsRef(adminUid).where('inventoryDate', isEqualTo: date);

      // ✅ User بيشوف بس مخزنه
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

  Future<List<String>> getInventoryDates() async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final user = await AuthService.instance.getCurrentUser();
      Query query = _itemsRef(adminUid);

      // ✅ User بيشوف بس مخزنه
      if (user != null && !user.isAdmin && user.assignedWarehouse != null) {
        query = query.where('warehouseName', isEqualTo: user.assignedWarehouse);
      }

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

      await _itemsRef(adminUid).doc(item.id).update({
        'warehouseName': item.warehouseName,
        'productName': item.productName,
        'serial': item.serial,
        'condition': item.condition,
        'expiryDate': item.expiryDate,
        'notes': item.notes,
        'inventoryDate': item.inventoryDate,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<bool> deleteWithReason(
    InventoryItem item, {
    required String reason,
    String? extraNotes,
    String? deletedByUid,
  }) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null || item.id == null) return false;

      // ✅ نقل للمحذوفات
      await _deletedRef(adminUid).add({
        'warehouseName': item.warehouseName,
        'productName': item.productName,
        'serial': item.serial,
        'condition': item.condition,
        'expiryDate': item.expiryDate,
        'notes': item.notes,
        'inventoryDate': item.inventoryDate,
        'deleteReason': reason,
        'deleteNotes': extraNotes ?? '',
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedByUid': deletedByUid,
        'addedByUid': item.addedByUid,
        'adminUid': adminUid,
      });

      // ✅ حذف من الـ items
      await _itemsRef(adminUid).doc(item.id).delete();
      return true;
    } catch (e) {
      return false;
    }
  }

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
      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final snapshot = await _deletedRef(adminUid)
          .where('deletedByUid', isEqualTo: uid)
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
          'expiry_date': data['expiryDate'],
          'inventory_date': data['inventoryDate'],
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> restoreItem(Map<String, dynamic> deletedItem) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;

      // ✅ رجّع للـ items
      await _itemsRef(adminUid).add({
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

      // ✅ حدّث سجل الحذف — إضافة ملاحظة الاستعادة
      final now = DateTime.now().toString().substring(0, 16);
      final oldNotes = deletedItem['delete_notes'] ?? '';
      await _deletedRef(adminUid).doc(deletedItem['id']).update({
        'deleteNotes': oldNotes.isEmpty
            ? 'مستعاد: $now'
            : '$oldNotes | مستعاد: $now',
      });
    } catch (_) {}
  }

  Future<void> permanentDeleteItem(String docId) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      await _deletedRef(adminUid).doc(docId).delete();
    } catch (_) {}
  }

  // ============================================================
  // Warehouses & Products
  // ============================================================

  Future<void> addWarehouse(String name) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;

      // ✅ استخدم اسم المخزن كـ document ID عشان نتجنب التكرار
      final docId = name.replaceAll(RegExp(r'[^\w]'), '_');
      await _warehousesRef(adminUid).doc(docId).set(
        {'name': name, 'createdAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<List<String>> getWarehouses() async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final snapshot = await _warehousesRef(adminUid).orderBy('name').get();
      return snapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteWarehouse(String name) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      final docId = name.replaceAll(RegExp(r'[^\w]'), '_');
      await _warehousesRef(adminUid).doc(docId).delete();
    } catch (_) {}
  }

  Future<void> updateWarehouse(String oldName, String newName) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      final oldDocId = oldName.replaceAll(RegExp(r'[^\w]'), '_');
      await _warehousesRef(adminUid).doc(oldDocId).delete();
      await addWarehouse(newName);
    } catch (_) {}
  }

  Future<void> addProduct(String name) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      final docId = name.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');
      await _productsRef(adminUid).doc(docId).set(
        {'name': name, 'createdAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<List<String>> getProducts() async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return [];

      final snapshot = await _productsRef(adminUid).orderBy('name').get();
      return snapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['name'] as String)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> deleteProduct(String name) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      final docId = name.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');
      await _productsRef(adminUid).doc(docId).delete();
    } catch (_) {}
  }

  Future<void> updateProduct(String oldName, String newName) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return;
      await deleteProduct(oldName);
      await addProduct(newName);
    } catch (_) {}
  }

  // ============================================================
  // Stats
  // ============================================================

  Future<Map<String, int>> getStats({String? date}) async {
    try {
      final adminUid = await _getAdminUid();
      if (adminUid == null) return _emptyStats();

      final user = await AuthService.instance.getCurrentUser();
      Query query = _itemsRef(adminUid);

      if (date != null) {
        query = query.where('inventoryDate', isEqualTo: date);
      }

      // ✅ User بيشوف بس مخزنه
      if (user != null && !user.isAdmin && user.assignedWarehouse != null) {
        query = query.where('warehouseName', isEqualTo: user.assignedWarehouse);
      }

      final snapshot = await query.get();
      final items = snapshot.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();

      final total = items.length;
      final good = items.where((i) => i['condition'] == 'جديد').length;
      final used = items.where((i) => i['condition'] == 'مستخدم').length;
      final damaged = items.where((i) => i['condition'] == 'تالف').length;

      // ✅ عدد المحذوفات
      Query deletedQuery = _deletedRef(adminUid);
      if (user != null && !user.isAdmin) {
        deletedQuery = deletedQuery.where('deletedByUid', isEqualTo: user.uid);
      }
      final deletedSnapshot = await deletedQuery.get();

      return {
        'total': total,
        'good': good,
        'used': used,
        'damaged': damaged,
        'deleted': deletedSnapshot.docs.length,
      };
    } catch (e) {
      return _emptyStats();
    }
  }

  Map<String, int> _emptyStats() =>
      {'total': 0, 'good': 0, 'used': 0, 'damaged': 0, 'deleted': 0};

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
      // ✅ مخازن
      for (final w in warehouses) {
        try {
          final docId = w.replaceAll(RegExp(r'[^\w]'), '_');
          await _warehousesRef(adminUid).doc(docId).set(
            {'name': w, 'createdAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
          warehousesMigrated++;
        } catch (_) {}
      }

      // ✅ منتجات
      for (final p in products) {
        try {
          final docId = p.replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '_');
          await _productsRef(adminUid).doc(docId).set(
            {'name': p, 'createdAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
          productsMigrated++;
        } catch (_) {}
      }

      // ✅ قطع المخزون — batch كل 400
      final batches = <WriteBatch>[];
      var currentBatch = _db.batch();
      int batchCount = 0;

      for (final item in sqliteItems) {
        final docRef = _itemsRef(adminUid).doc();
        currentBatch.set(docRef, {
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
        batchCount++;
        itemsMigrated++;

        if (batchCount == 400) {
          batches.add(currentBatch);
          currentBatch = _db.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) batches.add(currentBatch);
      for (final b in batches) await b.commit();

      // ✅ المحذوفات
      final deletedBatches = <WriteBatch>[];
      var deletedBatch = _db.batch();
      int deletedBatchCount = 0;

      for (final item in deletedItems) {
        final docRef = _deletedRef(adminUid).doc();
        deletedBatch.set(docRef, {
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
        deletedBatchCount++;
        deletedMigrated++;

        if (deletedBatchCount == 400) {
          deletedBatches.add(deletedBatch);
          deletedBatch = _db.batch();
          deletedBatchCount = 0;
        }
      }
      if (deletedBatchCount > 0) deletedBatches.add(deletedBatch);
      for (final b in deletedBatches) await b.commit();

      // ✅ علّم إن الـ migration اتعمل
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

  /// ✅ تحقق لو الـ migration اتعمل قبل كده
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