import 'package:cloud_firestore/cloud_firestore.dart';
import 'hive_service.dart';
import 'sync_engine.dart';
import 'firestore_service.dart';
import 'auth_service.dart';
import 'log_service.dart';

// ============================================================
// InventoryRepository
//
// This is the ONLY class that screens should talk to.
//
// Write path:
//   1. Write to Hive immediately              → UI updates instantly
//   2. Enqueue SyncOperation                  → background push to Firestore
//   3. Return                                 → never awaits Firestore
//
// Read path:
//   Always from Hive — zero network latency
//
// FirestoreService is now called ONLY by SyncEngine.
// No screen should import FirestoreService directly.
// ============================================================

class InventoryRepository {
  static final InventoryRepository instance = InventoryRepository._();
  InventoryRepository._();

  final _hive   = HiveService.instance;
  final _sync   = SyncEngine.instance;

  // ----------------------------------------------------------------
  // Reads — all synchronous (Hive is in-memory)
  // ----------------------------------------------------------------

  List<InventoryItem> getAllItems({String? warehouseFilter}) {
    final items = _hive.getAllItems();
    if (warehouseFilter != null) {
      return items.where((i) => i.warehouseName == warehouseFilter).toList();
    }
    return items;
  }

  List<InventoryItem> getItemsByDate(String date, {String? warehouseFilter}) {
    final items = _hive.getItemsByDate(date);
    if (warehouseFilter != null) {
      return items.where((i) => i.warehouseName == warehouseFilter).toList();
    }
    return items;
  }

  List<String> getInventoryDates() => _hive.getInventoryDates();

  Map<String, int> getStats({String? date}) => _hive.getStats(date: date);

  List<String> getWarehouses() => _hive.getWarehouses();
  List<String> getProducts()   => _hive.getProducts();

  List<Map<String, dynamic>> getDeletedItems() => _hive.getDeletedItems();

  // ----------------------------------------------------------------
  // Insert single item
  // ----------------------------------------------------------------

  Future<String> insertItem(InventoryItem item) async {
    // 1. Write to Hive first
    final localId = await _hive.insertItem(item);

    // 2. Enqueue sync
    final op = SyncOperation.insert(item, localId);
    await _hive.enqueue(op);

    // 3. Push immediately when online so the new item survives refresh/reload.
    try {
      await _sync.flushNow();
    } catch (_) {}

    // 4. Ensure warehouse/product exist locally
    if (!_hive.getWarehouses().contains(item.warehouseName)) {
      await _hive.addWarehouse(item.warehouseName);
    }
    if (!_hive.getProducts().contains(item.productName)) {
      await _hive.addProduct(item.productName);
    }

    // 5. Log locally (fire-and-forget)
    _logInsert(item);

    return localId;
  }

  // ----------------------------------------------------------------
  // Insert batch (Excel import)
  // ----------------------------------------------------------------

  Future<int> insertItemsBatch(List<InventoryItem> items) async {
    if (items.isEmpty) return 0;

    // Write all to Hive
    for (final item in items) {
      final localId = await _hive.insertItem(item);
      await _hive.enqueue(SyncOperation.insert(item, localId));
    }

    // Seed new warehouses/products locally
    final warehouses = _hive.getWarehouses().toSet();
    final products   = _hive.getProducts().toSet();

    for (final item in items) {
      if (!warehouses.contains(item.warehouseName)) {
        await _hive.addWarehouse(item.warehouseName);
        warehouses.add(item.warehouseName);
      }
      if (!products.contains(item.productName)) {
        await _hive.addProduct(item.productName);
        products.add(item.productName);
      }
    }

    // Flush immediately so imported items survive refresh/reload.
    try {
      await _sync.flushNow();
    } catch (_) {}

    return items.length;
  }

  // ----------------------------------------------------------------
  // Update
  // ----------------------------------------------------------------

  Future<void> updateItem(InventoryItem item) async {
    await _hive.updateItem(item);
    await _hive.enqueue(SyncOperation.update(item));

    // Flush right away so edits are persisted before any screen refresh.
    try {
      await _sync.flushNow();
    } catch (_) {}

    _logUpdate(item);
  }

  // ----------------------------------------------------------------
  // Delete with reason (soft delete → moved to deleted_items)
  // ----------------------------------------------------------------

  Future<bool> deleteWithReason(
    InventoryItem item, {
    required String reason,
    String? extraNotes,
    String? deletedByUid,
  }) async {
    if (item.id == null) return false;

    // 1. Move in Hive
    await _hive.moveToDeleted(
      item,
      reason:       reason,
      extraNotes:   extraNotes,
      deletedByUid: deletedByUid,
    );

    // 2. Enqueue Firestore sync
    await _hive.enqueue(SyncOperation.deleteWithReason(
      item,
      reason:     reason,
      extraNotes: extraNotes,
      actorUid:   deletedByUid,
    ));

    // Flush immediately so the delete is persisted before any refresh/reload.
    try {
      await _sync.flushNow();
    } catch (_) {}

    _logDelete(item, reason: reason);
    return true;
  }

  // ----------------------------------------------------------------
  // Clear all items for a date (Admin only)
  // ----------------------------------------------------------------

  Future<int> clearItemsByDate(String date, {String? deletedByUid}) async {
    final items = _hive.getItemsByDate(date);
    if (items.isEmpty) return 0;

    // ── Step 1: flush pending inserts FIRST ─────────────────────────
    // Items added locally carry tmp_ IDs until flushed to Firestore.
    // Flushing now ensures every item that should exist in Firestore does.
    try { await _sync.flushNow(); } catch (_) {}

    // Re-read — tmp_ IDs may now be real Firestore IDs after flush
    final freshItems = _hive.getItemsByDate(date);

    // ── Step 2: cancel any queued ops for these items ────────────────
    // Prevents insert-then-delete race in the sync queue.
    for (final item in freshItems) {
      await _hive.cancelPendingOpsForItem(item.id!);
    }

    // ── Step 3: move all items to Hive deleted box ───────────────────
    for (final item in freshItems) {
      await _hive.moveToDeleted(
        item,
        reason:       'مسح المخزون اليومي',
        extraNotes:   'تم مسح مخزون يوم $date',
        deletedByUid: deletedByUid,
      );
    }

    // ── Step 4: bulk Firestore delete in batches of 500 ─────────────
    // Uses Firestore WriteBatch — far faster than 1 round-trip per item.
    // Items with tmp_ IDs were never in Firestore, skip them.
    final realItems = freshItems.where((i) => !i.id!.startsWith('tmp_')).toList();

    if (realItems.isNotEmpty) {
      try {
        final user     = await AuthService.instance.getCurrentUser();
        final adminUid = user != null
            ? (user.isAdmin ? user.uid : user.adminUid)
            : null;

        if (adminUid != null) {
          final db         = FirebaseFirestore.instance;
          final itemsRef   = db.collection('inventory').doc(adminUid).collection('items');
          final deletedRef = db.collection('inventory').doc(adminUid).collection('deleted_items');
          final now        = Timestamp.now();

          // Firestore WriteBatch max = 500 ops. Each item = 2 ops (set + delete).
          // So max 250 items per batch.
          const batchSize = 250;
          for (int offset = 0; offset < realItems.length; offset += batchSize) {
            final chunk = realItems.skip(offset).take(batchSize).toList();
            final batch = db.batch();
            for (final item in chunk) {
              // Write to deleted_items
              batch.set(deletedRef.doc(), {
                'warehouseName': item.warehouseName,
                'productName':   item.productName,
                'serial':        item.serial,
                'condition':     item.condition,
                'expiryDate':    item.expiryDate,
                'notes':         item.notes,
                'inventoryDate': item.inventoryDate,
                'addedByUid':    item.addedByUid,
                'adminUid':      adminUid,
                'deleteReason':  'مسح المخزون اليومي',
                'deleteNotes':   'تم مسح مخزون يوم $date',
                'deletedAt':     now,
                'deletedByUid':  deletedByUid,
              });
              // Delete from items
              batch.delete(itemsRef.doc(item.id!));
            }
            await batch.commit();
          }
          // Mark all synced — no need to enqueue individual ops
          return freshItems.length;
        }
      } catch (_) {
        // Firestore batch failed (offline?) — fall back to individual sync ops
        for (final item in realItems) {
          await _hive.enqueue(SyncOperation.deleteWithReason(
            item,
            reason:   'مسح المخزون اليومي',
            actorUid: deletedByUid,
          ));
        }
        // Flush will pick these up when online
        try { await _sync.flushNow(); } catch (_) {}
      }
    }

    return freshItems.length;
  }

  // ----------------------------------------------------------------
  // Restore deleted item
  // ----------------------------------------------------------------

  Future<void> restoreItem(Map<String, dynamic> deletedItem) async {
    final id = deletedItem['_id'] as String? ?? deletedItem['id'] as String?;
    if (id == null) return;

    final restored = InventoryItem(
      warehouseName: deletedItem['warehouseName'] as String? ??
                     deletedItem['warehouse_name'] as String? ?? '',
      productName:   deletedItem['productName'] as String? ??
                     deletedItem['product_name'] as String? ?? '',
      serial:        deletedItem['serial'] as String?,
      condition:     deletedItem['condition'] as String? ?? 'جيد',
      expiryDate:    deletedItem['expiryDate'] as String?,
      notes:         'مستعاد - ${deletedItem['deleteReason'] ?? ''}',
      inventoryDate: deletedItem['inventoryDate'] as String? ??
                     deletedItem['inventory_date'] as String? ??
                     InventoryItem.today(),
      addedByUid:    deletedItem['addedByUid'] as String?,
      adminUid:      deletedItem['adminUid'] as String?,
    );

    await _hive.insertItem(restored);
    await _hive.removeFromDeleted(id);
    // SyncEngine will pick up the insert op on next flush
  }

  // ----------------------------------------------------------------
  // Permanent delete — removes from Hive deleted box + Firestore
  // ----------------------------------------------------------------

  Future<void> permanentDeleteItem(Map<String, dynamic> item) async {
    // FIX: resolve ID from '_id' OR 'id' key — Hive uses '_id'
    final id = item['_id'] as String?
            ?? item['id']  as String?;
    if (id == null || id.isEmpty) return;

    // 1. Remove from Hive immediately → UI updates instantly
    await _hive.removeFromDeleted(id);

    // 2. Log the action
    try {
      LogService.instance.log(
        type:      LogType.itemPermanentDeleted,
        product:   item['productName']   as String?,
        warehouse: item['warehouseName'] as String?,
        serial:    item['serial']        as String?,
      );
    } catch (_) {}

    // 3. Delete from Firestore deleted_items collection
    // If offline, this will fail silently — the item is already gone from
    // Hive, so it won't reappear in the UI. On next pullLatest it won't
    // come back either (it was removed from Hive). Acceptable trade-off.
    try {
      await FirestoreService.instance.permanentDeleteItem(id);
    } catch (_) {}
  }

  // ----------------------------------------------------------------
  // Warehouse / Product management
  // ----------------------------------------------------------------

  Future<void> addWarehouse(String name) async {
    await _hive.addWarehouse(name);
    // FirestoreService.addWarehouse is called directly from manage_screen
    // for now — could be queued too, but warehouses are admin-only and
    // typically edited online.
  }

  Future<void> removeWarehouse(String name) async {
    await _hive.removeWarehouse(name);
  }

  Future<void> addProduct(String name) async {
    await _hive.addProduct(name);
  }

  Future<void> removeProduct(String name) async {
    await _hive.removeProduct(name);
  }

  // ----------------------------------------------------------------
  // Manual sync trigger (pull-to-refresh, app resume)
  // ----------------------------------------------------------------

  Future<void> refresh() => _sync.pullLatest();

  Future<void> flushNow() => _sync.flushNow();

  int get pendingOpsCount => _hive.pendingOpsCount;

  // ----------------------------------------------------------------
  // Private: fire-and-forget logging
  // ----------------------------------------------------------------

  void _logInsert(InventoryItem item) async {
    try {
      final user = await AuthService.instance.getCurrentUser();
      LogService.instance.log(
        type:      LogType.itemAdded,
        actorUid:  user?.uid,
        actorName: user?.name,
        actorRole: user?.role,
        product:   item.productName,
        warehouse: item.warehouseName,
        serial:    item.serial,
        adminUid:  item.adminUid,
      );
    } catch (_) {}
  }

  void _logUpdate(InventoryItem item) async {
    try {
      final user = await AuthService.instance.getCurrentUser();
      LogService.instance.log(
        type:      LogType.itemEdited,
        actorUid:  user?.uid,
        actorName: user?.name,
        actorRole: user?.role,
        product:   item.productName,
        warehouse: item.warehouseName,
        serial:    item.serial,
        adminUid:  item.adminUid,
      );
    } catch (_) {}
  }

  void _logDelete(InventoryItem item, {required String reason}) async {
    try {
      final user = await AuthService.instance.getCurrentUser();
      LogService.instance.log(
        type:      LogType.itemDeleted,
        actorUid:  user?.uid,
        actorName: user?.name,
        actorRole: user?.role,
        product:   item.productName,
        warehouse: item.warehouseName,
        serial:    item.serial,
        reason:    reason,
        adminUid:  item.adminUid,
      );
    } catch (_) {}
  }
}