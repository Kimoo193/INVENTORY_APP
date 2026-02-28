import 'package:flutter/material.dart';
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

  // ✅ Cache للـ currentUser — بيتصفّى عند الحاجة
  AppUser? _cachedUser;
  DateTime? _cacheTime;

  Future<AppUser?> _getCachedUser() async {
    final now = DateTime.now();
    if (_cachedUser != null &&
        _cacheTime != null &&
        now.difference(_cacheTime!).inSeconds < 30) {
      return _cachedUser;
    }
    _cachedUser = await AuthService.instance.getCurrentUser();
    _cacheTime = now;
    return _cachedUser;
  }

  void clearCache() {
    _cachedUser = null;
    _cacheTime = null;
  }

  // ✅ Helper: جيب adminUid الخاص بالـ user الحالي
  // لو Admin → uid بتاعه
  // لو User → adminUid المحفوظ في بياناته
  Future<String?> _getAdminUid() async {
    final user = await _getCachedUser();
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

      final user = await _getCachedUser();
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

      final user = await _getCachedUser();
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

      final user = await _getCachedUser();
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

      final user = await _getCachedUser();
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

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool _loading = true;
  List<AppUser> _users = [];
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    final currentUser = await AuthService.instance.getCurrentUser();
    List<AppUser> users = [];
    if (currentUser != null) {
      users = currentUser.isSuperAdmin
          ? await AuthService.instance.getAllUsers()
          : await AuthService.instance.getUsersByAdmin(currentUser.uid);
    }
    if (!mounted) return;
    setState(() {
      _currentUser = currentUser;
      _users = users;
      _loading = false;
    });
  }

  Future<void> _toggleActive(AppUser user, bool value) async {
    await AuthService.instance.toggleUserActive(user.uid, value);
    await _loadUsers();
  }

  Future<void> _togglePermission(AppUser user, String key, bool value) async {
    await AuthService.instance.updateUserPermissions(user.uid, {key: value});
    await _loadUsers();
  }

  // ============================================================
  // ✅ Dialog إضافة مستخدم جديد
  // ============================================================
  Future<void> _showAddUserDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String? selectedWarehouse;
    List<String> warehouses = [];
    bool isAdmin = false;
    bool obscure = true;

    Map<String, bool> permissions = {
      'canAdd': true,
      'canEdit': false,
      'canDelete': false,
      'canRestore': false,
      'canExport': false,
      'canImport': false,
      'canManage': false,
    };

    // جيب المخازن للـ dropdown
    try {
      // نستورد FirestoreService هنا بشكل dynamic
      final fs = await _getWarehouses();
      warehouses = fs;
    } catch (_) {}

    final permLabels = {
      'canAdd': 'إضافة',
      'canEdit': 'تعديل',
      'canDelete': 'حذف',
      'canRestore': 'استعادة من الحذف',
      'canExport': 'تصدير Excel',
      'canImport': 'استيراد',
      'canManage': 'إدارة القوائم',
    };

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A237E).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_add, color: Color(0xFF1A237E)),
                      ),
                      const SizedBox(width: 12),
                      const Text('إضافة مستخدم جديد',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 20),

                    // الاسم
                    TextField(
                      controller: nameCtrl,
                      textDirection: TextDirection.rtl,
                      decoration: InputDecoration(
                        labelText: 'الاسم',
                        prefixIcon: const Icon(Icons.person_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // البريد
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'البريد الإلكتروني',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // كلمة السر
                    StatefulBuilder(builder: (_, setSub) => TextField(
                      controller: passCtrl,
                      obscureText: obscure,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'كلمة السر',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setSub(() => obscure = !obscure),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    )),
                    const SizedBox(height: 16),

                    // نوع الحساب (User / Admin) - للـ SuperAdmin بس
                    if (_currentUser?.isSuperAdmin == true) ...[
                      Row(children: [
                        const Text('نوع الحساب:', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('🔑 مدير'),
                          selected: isAdmin,
                          onSelected: (v) => setS(() => isAdmin = v),
                          selectedColor: const Color(0xFF1A237E).withOpacity(0.15),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('👤 مستخدم'),
                          selected: !isAdmin,
                          onSelected: (v) => setS(() => isAdmin = !v),
                          selectedColor: const Color(0xFF1A237E).withOpacity(0.15),
                        ),
                      ]),
                      const SizedBox(height: 12),
                    ],

                    // المخزن المخصص (للـ User فقط)
                    if (!isAdmin) ...[
                      const Text('المخزن المخصص:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedWarehouse,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        hint: const Text('بدون تقييد (كل المخازن)'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('بدون تقييد (كل المخازن)')),
                          ...warehouses.map((w) => DropdownMenuItem(value: w, child: Text(w))),
                        ],
                        onChanged: (v) => setS(() => selectedWarehouse = v),
                      ),
                      const SizedBox(height: 16),

                      // الصلاحيات
                      const Text('الصلاحيات:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ...permLabels.entries.map((e) => SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value, style: const TextStyle(fontSize: 14)),
                        value: permissions[e.key] ?? false,
                        activeColor: const Color(0xFF1A237E),
                        onChanged: (v) => setS(() => permissions[e.key] = v),
                      )),
                    ],

                    const SizedBox(height: 20),

                    // Buttons
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A237E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('إنشاء', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (result != true) return;

    // Validate
    if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ارجاء ملء كل الحقول المطلوبة')));
      return;
    }

    // Show loading
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final adminUid = _currentUser!.isSuperAdmin
          ? (_currentUser!.uid) // لو super admin بيضيف admin
          : _currentUser!.uid;

      if (isAdmin && _currentUser?.isSuperAdmin == true) {
        // ✅ إنشاء Admin
        await AuthService.instance.createAdmin(
          email: emailCtrl.text.trim(),
          password: passCtrl.text,
          name: nameCtrl.text.trim(),
          createdBy: _currentUser!.uid,
        );
      } else {
        // ✅ إنشاء User عادي
        await AuthService.instance.createUser(
          email: emailCtrl.text.trim(),
          password: passCtrl.text,
          name: nameCtrl.text.trim(),
          permissions: permissions,
          assignedWarehouse: selectedWarehouse,
          adminUid: _currentUser!.isAdmin ? _currentUser!.uid : _currentUser!.adminUid,
          createdBy: _currentUser!.uid,
        );
      }

      if (mounted) {
        Navigator.pop(context); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء الحساب بنجاح ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // جيب المخازن من Firestore
  Future<List<String>> _getWarehouses() async {
    try {
      final db = FirebaseFirestore.instance;
      final currentUser = _currentUser;
      if (currentUser == null) return [];
      
      // جيب adminUid
      String? adminUid;
      if (currentUser.isAdmin) {
        adminUid = currentUser.uid;
      } else {
        adminUid = currentUser.adminUid;
      }
      if (adminUid == null) return [];

      final snap = await db
          .collection('inventory')
          .doc(adminUid)
          .collection('warehouses')
          .get();
      return snap.docs.map((d) => d.data()['name'] as String? ?? d.id).toList();
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // Build
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isAdmin = _currentUser?.isAdmin ?? false;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('المستخدمون (${_users.length})'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadUsers,
                child: _users.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.people_outline, size: 60, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text('لا يوجد مستخدمون',
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                                const SizedBox(height: 8),
                                if (isAdmin)
                                  Text('اضغط + لإضافة مستخدم جديد',
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                        itemCount: _users.length,
                        itemBuilder: (_, i) {
                          final user = _users[i];
                          final canManage = _currentUser?.isAdmin == true &&
                              !user.isSuperAdmin &&
                              user.uid != _currentUser?.uid;

                          // أيقونة الدور
                          final roleIcon = user.isSuperAdmin
                              ? '👑'
                              : user.isAdmin
                                  ? '🔑'
                                  : '👤';
                          final roleLabel = user.isSuperAdmin
                              ? 'Super Admin'
                              : user.isAdmin
                                  ? 'مدير'
                                  : 'مستخدم';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 1.5,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: user.isActive
                                    ? const Color(0xFF1A237E).withOpacity(0.1)
                                    : Colors.grey.shade200,
                                child: Text(roleIcon,
                                    style: const TextStyle(fontSize: 18)),
                              ),
                              title: Text(user.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.email,
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey.shade600)),
                                  Row(children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 3),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: user.isAdmin
                                            ? Colors.blue.withOpacity(0.1)
                                            : Colors.green.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(roleLabel,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: user.isAdmin
                                                  ? Colors.blue.shade700
                                                  : Colors.green.shade700,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    if (user.assignedWarehouse != null) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        margin: const EdgeInsets.only(top: 3),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text('📦 ${user.assignedWarehouse}',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange.shade700)),
                                      ),
                                    ],
                                  ]),
                                ],
                              ),
                              trailing: canManage
                                  ? Switch(
                                      value: user.isActive,
                                      activeColor: const Color(0xFF1A237E),
                                      onChanged: (v) => _toggleActive(user, v),
                                    )
                                  : null,
                              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              children: [
                                if (!user.isAdmin) ...[
                                  const Divider(),
                                  const Align(
                                    alignment: Alignment.centerRight,
                                    child: Text('الصلاحيات:',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Colors.grey)),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _permChip(user, 'canAdd', 'إضافة', user.canAdd, canManage),
                                      _permChip(user, 'canEdit', 'تعديل', user.canEdit, canManage),
                                      _permChip(user, 'canDelete', 'حذف', user.canDelete, canManage),
                                      _permChip(user, 'canRestore', 'استعادة', user.canRestore, canManage),
                                      _permChip(user, 'canExport', 'تصدير', user.canExport, canManage),
                                      _permChip(user, 'canImport', 'استيراد', user.canImport, canManage),
                                      _permChip(user, 'canManage', 'إدارة', user.canManage, canManage),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
        // ✅ FAB إضافة مستخدم — للـ Admin و SuperAdmin فقط
        floatingActionButton: isAdmin
            ? FloatingActionButton.extended(
                onPressed: _showAddUserDialog,
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                icon: const Icon(Icons.person_add),
                label: const Text('مستخدم جديد',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              )
            : null,
      ),
    );
  }

  Widget _permChip(
      AppUser user, String key, String label, bool value, bool canManage) {
    return FilterChip(
      selected: value,
      selectedColor: const Color(0xFF1A237E).withOpacity(0.15),
      checkmarkColor: const Color(0xFF1A237E),
      onSelected: canManage ? (v) => _togglePermission(user, key, v) : null,
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}