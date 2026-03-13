import 'package:hive_flutter/hive_flutter.dart';
import 'firestore_service.dart'; // InventoryItem model

// ============================================================
// HiveService — Local-first cache
// All reads come from here. Firestore is write-back only.
// ============================================================

// Box names — single source of truth
const _kItems    = 'items';
const _kDeleted  = 'deleted_items';
const _kMeta     = 'meta';
const _kQueue    = 'sync_queue';
const _kWarehouses = 'warehouses';
const _kProducts   = 'products';

// Meta keys
const _kLastSyncKey    = 'last_sync';
const _kAdminUidKey    = 'admin_uid';
const _kCacheSeedKey   = 'cache_seeded'; // true after first Firestore pull

class HiveService {
  static final HiveService instance = HiveService._();
  HiveService._();

  late Box<Map> _itemsBox;
  late Box<Map> _deletedBox;
  late Box<Map> _queueBox;
  late Box<String> _warehousesBox;
  late Box<String> _productsBox;
  late Box _metaBox;

  // ----------------------------------------------------------------
  // Init — call once in main() before runApp
  // ----------------------------------------------------------------

  Future<void> init() async {
    await Hive.initFlutter();
    _itemsBox      = await Hive.openBox<Map>(_kItems);
    _deletedBox    = await Hive.openBox<Map>(_kDeleted);
    _queueBox      = await Hive.openBox<Map>(_kQueue);
    _warehousesBox = await Hive.openBox<String>(_kWarehouses);
    _productsBox   = await Hive.openBox<String>(_kProducts);
    _metaBox       = await Hive.openBox(_kMeta);
  }

  // ----------------------------------------------------------------
  // Meta helpers
  // ----------------------------------------------------------------

  bool get isCacheSeeded    => _metaBox.get(_kCacheSeedKey, defaultValue: false) as bool;
  String? get cachedAdminUid => _metaBox.get(_kAdminUidKey) as String?;
  DateTime? get lastSyncTime {
    final ms = _metaBox.get(_kLastSyncKey) as int?;
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> markCacheSeeded(String adminUid) async {
    await _metaBox.put(_kCacheSeedKey, true);
    await _metaBox.put(_kAdminUidKey, adminUid);
  }

  Future<void> markSynced() async {
    await _metaBox.put(_kLastSyncKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Call on logout — clears ALL local data for the tenant
  Future<void> clearAll() async {
    await Future.wait([
      _itemsBox.clear(),
      _deletedBox.clear(),
      _queueBox.clear(),
      _warehousesBox.clear(),
      _productsBox.clear(),
      _metaBox.clear(),
    ]);
  }

  // ----------------------------------------------------------------
  // Items — local CRUD
  // ----------------------------------------------------------------

  List<InventoryItem> getAllItems() {
    return _itemsBox.values
        .map((m) => InventoryItem.fromMap(Map<String, dynamic>.from(m), m['_id'] as String? ?? ''))
        .toList()
      ..sort((a, b) => (b.inventoryDate).compareTo(a.inventoryDate));
  }

  List<InventoryItem> getItemsByDate(String date) {
    return getAllItems().where((i) => i.inventoryDate == date).toList();
  }

  List<String> getInventoryDates() {
    return getAllItems()
        .map((i) => i.inventoryDate)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  Map<String, int> getStats({String? date}) {
    final items = date != null ? getItemsByDate(date) : getAllItems();
    return {
      'total':   items.length,
      'good':    items.where((i) => i.condition == 'جديد').length,
      'used':    items.where((i) => i.condition == 'مستخدم').length,
      'damaged': items.where((i) => i.condition == 'تالف').length,
      'deleted': _deletedBox.length,
    };
  }

  /// Returns the local key (= Firestore doc ID or a temp UUID)
  Future<String> insertItem(InventoryItem item) async {
    final key = item.id ?? _tempId();
    final map = _itemToMap(item, key);
    await _itemsBox.put(key, map);
    return key;
  }

  Future<void> updateItem(InventoryItem item) async {
    if (item.id == null) return;
    final map = _itemToMap(item, item.id!);
    await _itemsBox.put(item.id!, map);
  }

  Future<void> deleteItem(String id) async {
    await _itemsBox.delete(id);
  }

  Future<void> moveToDeleted(InventoryItem item, {
    required String reason,
    String? extraNotes,
    String? deletedByUid,
  }) async {
    if (item.id == null) return;
    final key = item.id!;
    await _itemsBox.delete(key);
    await _deletedBox.put(key, {
      '_id':           key,
      'warehouseName': item.warehouseName,
      'productName':   item.productName,
      'serial':        item.serial,
      'condition':     item.condition,
      'expiryDate':    item.expiryDate,
      'notes':         item.notes,
      'inventoryDate': item.inventoryDate,
      'deleteReason':  reason,
      'deleteNotes':   extraNotes ?? '',
      'deletedAt':     DateTime.now().toIso8601String(),
      'deletedByUid':  deletedByUid,
      'addedByUid':    item.addedByUid,
      'adminUid':      item.adminUid,
    });
  }

  // ----------------------------------------------------------------
  // Deleted Items — local reads
  // ----------------------------------------------------------------

  List<Map<String, dynamic>> getDeletedItems() {
    return _deletedBox.values
        .map((m) => Map<String, dynamic>.from(m))
        .toList()
      ..sort((a, b) {
          final aD = a['deletedAt'] as String? ?? '';
          final bD = b['deletedAt'] as String? ?? '';
          return bD.compareTo(aD);
        });
  }

  Future<void> removeFromDeleted(String id) async {
    await _deletedBox.delete(id);
  }

  // ----------------------------------------------------------------
  // Warehouses & Products
  // ----------------------------------------------------------------

  List<String> getWarehouses() => _warehousesBox.values.toList()..sort();
  List<String> getProducts()   => _productsBox.values.toList()..sort();

  Future<void> seedWarehouses(List<String> names) async {
    await _warehousesBox.clear();
    for (final n in names) await _warehousesBox.put(n, n);
  }

  Future<void> seedProducts(List<String> names) async {
    await _productsBox.clear();
    for (final n in names) await _productsBox.put(n, n);
  }

  Future<void> addWarehouse(String name) async => _warehousesBox.put(name, name);
  Future<void> addProduct(String name)   async => _productsBox.put(name, name);
  Future<void> removeWarehouse(String name) async => _warehousesBox.delete(name);
  Future<void> removeProduct(String name)   async => _productsBox.delete(name);

  // ----------------------------------------------------------------
  // Bulk seed — called once after first Firestore pull
  // ----------------------------------------------------------------

  Future<void> seedItems(List<InventoryItem> items) async {
    await _itemsBox.clear();
    final entries = {
      for (final item in items)
        (item.id ?? _tempId()): _itemToMap(item, item.id ?? _tempId())
    };
    await _itemsBox.putAll(entries);
  }

  Future<void> seedDeletedItems(List<Map<String, dynamic>> items) async {
    await _deletedBox.clear();
    final entries = <String, Map>{};
    for (final item in items) {
      final key = item['id'] as String? ?? _tempId();
      entries[key] = {...item, '_id': key};
    }
    await _deletedBox.putAll(entries);
  }

  // ----------------------------------------------------------------
  // Sync Queue — pending Firestore operations
  // ----------------------------------------------------------------

  List<SyncOperation> getPendingOps() {
    return _queueBox.values
        .map((m) => SyncOperation.fromMap(Map<String, dynamic>.from(m)))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<String> enqueue(SyncOperation op) async {
    final key = op.id;
    await _queueBox.put(key, op.toMap());
    return key;
  }

  Future<void> dequeue(String opId) async {
    await _queueBox.delete(opId);
  }

  Future<int> cancelPendingOpsForItem(String itemId) async {
    final toRemove = getPendingOps()
        .where((op) => op.itemId == itemId || op.id.endsWith('_$itemId'))
        .map((op) => op.id)
        .toList();

    for (final opId in toRemove) {
      await _queueBox.delete(opId);
    }

    return toRemove.length;
  }

  bool get hasPendingOps => _queueBox.isNotEmpty;
  int  get pendingOpsCount => _queueBox.length;

  // ----------------------------------------------------------------
  // Private helpers
  // ----------------------------------------------------------------

  Map _itemToMap(InventoryItem item, String key) => {
    '_id':           key,
    'warehouseName': item.warehouseName,
    'productName':   item.productName,
    'serial':        item.serial,
    'condition':     item.condition,
    'expiryDate':    item.expiryDate,
    'notes':         item.notes,
    'inventoryDate': item.inventoryDate,
    'addedByUid':    item.addedByUid,
    'adminUid':      item.adminUid,
    if (item.importBatchId != null) 'importBatchId': item.importBatchId,
  };

  String _tempId() =>
      'tmp_${DateTime.now().millisecondsSinceEpoch}_${_rnd()}';

  int _rnd() => DateTime.now().microsecond;

  
}

// ============================================================
// SyncOperation — a pending write that hasn't reached Firestore
// ============================================================

enum SyncOpType { insert, update, delete, deleteWithReason, batchInsert }

class SyncOperation {
  final String     id;
  final SyncOpType type;
  final String?    itemId;        // local Hive key
  final Map<String, dynamic>? payload;  // full item map for insert/update
  final String?    reason;        // for deleteWithReason
  final String?    extraNotes;
  final String?    actorUid;
  final String     createdAt;

  SyncOperation({
    required this.id,
    required this.type,
    this.itemId,
    this.payload,
    this.reason,
    this.extraNotes,
    this.actorUid,
    String? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toIso8601String();

  factory SyncOperation.insert(InventoryItem item, String localId) =>
      SyncOperation(
        id:      'ins_$localId',
        type:    SyncOpType.insert,
        itemId:  localId,
        payload: {
          'warehouseName': item.warehouseName,
          'productName':   item.productName,
          'serial':        item.serial,
          'condition':     item.condition,
          'expiryDate':    item.expiryDate,
          'notes':         item.notes,
          'inventoryDate': item.inventoryDate,
          'addedByUid':    item.addedByUid,
          'adminUid':      item.adminUid,
          if (item.importBatchId != null) 'importBatchId': item.importBatchId,
        },
      );

  factory SyncOperation.update(InventoryItem item) =>
      SyncOperation(
        id:      'upd_${item.id}',
        type:    SyncOpType.update,
        itemId:  item.id,
        payload: {
          'warehouseName': item.warehouseName,
          'productName':   item.productName,
          'serial':        item.serial,
          'condition':     item.condition,
          'expiryDate':    item.expiryDate,
          'notes':         item.notes,
          'inventoryDate': item.inventoryDate,
        },
      );

  factory SyncOperation.deleteWithReason(
    InventoryItem item, {
    required String reason,
    String? extraNotes,
    String? actorUid,
  }) =>
      SyncOperation(
        id:         'del_${item.id}',
        type:       SyncOpType.deleteWithReason,
        itemId:     item.id,
        reason:     reason,
        extraNotes: extraNotes,
        actorUid:   actorUid,
        payload: {
          'warehouseName': item.warehouseName,
          'productName':   item.productName,
          'serial':        item.serial,
          'condition':     item.condition,
          'expiryDate':    item.expiryDate,
          'notes':         item.notes,
          'inventoryDate': item.inventoryDate,
          'addedByUid':    item.addedByUid,
          'adminUid':      item.adminUid,
        },
      );

  Map<String, dynamic> toMap() => {
    'id':         id,
    'type':       type.name,
    'itemId':     itemId,
    'payload':    payload,
    'reason':     reason,
    'extraNotes': extraNotes,
    'actorUid':   actorUid,
    'createdAt':  createdAt,
  };

  factory SyncOperation.fromMap(Map<String, dynamic> m) => SyncOperation(
    id:         m['id'] as String,
    type:       SyncOpType.values.firstWhere(
                  (e) => e.name == m['type'],
                  orElse: () => SyncOpType.insert,
                ),
    itemId:     m['itemId'] as String?,
    payload:    m['payload'] != null
                  ? Map<String, dynamic>.from(m['payload'] as Map)
                  : null,
    reason:     m['reason'] as String?,
    extraNotes: m['extraNotes'] as String?,
    actorUid:   m['actorUid'] as String?,
    createdAt:  m['createdAt'] as String? ?? '',
  );
}