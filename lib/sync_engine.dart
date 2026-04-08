import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'hive_service.dart';
import 'firestore_service.dart';
import 'auth_service.dart';

// ============================================================
// SyncEngine
// Responsibilities:
//   1. Seed Hive on first login (pull from Firestore once)
//   2. Watch connectivity — flush queue on reconnect
//   3. Periodic flush every 30 seconds while online
//   4. Expose sync status stream for UI indicators
// ============================================================

enum SyncStatus { idle, syncing, error, offline }

class SyncEngine {
  static final SyncEngine instance = SyncEngine._();
  SyncEngine._();

  final _db     = FirebaseFirestore.instance;
  final _hive   = HiveService.instance;
  final _fs     = FirestoreService.instance;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus _status = SyncStatus.idle;

  bool _isOnline  = false;
  bool _isSyncing = false;

  StreamSubscription? _connectivitySub;
  Timer?              _periodicTimer;

  // ----------------------------------------------------------------
  // Lifecycle
  // ----------------------------------------------------------------

  Future<void> start() async {
    // 1. Check current connectivity
    final result = await Connectivity().checkConnectivity();
    _isOnline = result != ConnectivityResult.none;

    // 2. Listen for changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      final wasOffline = !_isOnline;
      _isOnline = result != ConnectivityResult.none;

      if (_isOnline && wasOffline) {
        // Just came back online — flush immediately
        _flush();
      } else if (!_isOnline) {
        _setStatus(SyncStatus.offline);
      }
    });

    // 3. Periodic flush every 30 seconds while online
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isOnline) _flush();
    });

    // 4. Initial flush if online
    if (_isOnline && _hive.hasPendingOps) {
      _flush();
    }
  }

  void stop() {
    _connectivitySub?.cancel();
    _periodicTimer?.cancel();
    _statusController.close();
  }

  // ----------------------------------------------------------------
  // First-launch seed — pull Firestore → Hive once per tenant
  // ----------------------------------------------------------------

  Future<void> seedIfNeeded() async {
    if (_hive.isCacheSeeded) return;
    if (!_isOnline) return;

    _setStatus(SyncStatus.syncing);
    try {
      final user = await AuthService.instance.getCurrentUser();
      if (user == null) return;

      final adminUid = user.isAdmin ? user.uid : user.adminUid;
      if (adminUid == null) return;

      // Pull everything in parallel
      final results = await Future.wait([
        _fs.getAllItems(),
        _fs.getDeletedItems(),
        _fs.getWarehouses(),
        _fs.getProducts(),
      ]);

      final items        = results[0] as List<InventoryItem>;
      final deletedItems = results[1] as List<Map<String, dynamic>>;
      final warehouses   = results[2] as List<String>;
      final products     = results[3] as List<String>;

      await Future.wait([
        _hive.seedItems(items),
        _hive.seedDeletedItems(deletedItems),
        _hive.seedWarehouses(warehouses),
        _hive.seedProducts(products),
      ]);

      await _hive.markCacheSeeded(adminUid);
      await _hive.markSynced();
      _setStatus(SyncStatus.idle);
    } catch (e) {
      _setStatus(SyncStatus.error);
    }
  }

  // ----------------------------------------------------------------
  // Flush pending queue → Firestore
  // ----------------------------------------------------------------

  Future<void> _flush() async {
    if (_isSyncing || !_isOnline) return;
    if (!_hive.hasPendingOps) return;

    _isSyncing = true;
    _setStatus(SyncStatus.syncing);

    final ops = _hive.getPendingOps();

    // FIX: process inserts before deletes to guarantee items exist in Firestore
    // before any delete op tries to reference them. This prevents the race where
    // a clearDay delete arrives at Firestore before the item's insert op.
    final insertOps = ops.where((o) =>
        o.type == SyncOpType.insert || o.type == SyncOpType.batchInsert).toList();
    final deleteOps = ops.where((o) =>
        o.type == SyncOpType.deleteWithReason || o.type == SyncOpType.delete).toList();
    final otherOps  = ops.where((o) =>
        o.type == SyncOpType.update).toList();
    final ordered   = [...insertOps, ...otherOps, ...deleteOps];

    int failed = 0;

    for (final op in ordered) {
      try {
        await _executeOp(op);
        await _hive.dequeue(op.id);
      } catch (e) {
        failed++;
        // Don't dequeue — will retry next flush
      }
    }

    _isSyncing = false;
    await _hive.markSynced();
    _setStatus(failed > 0 ? SyncStatus.error : SyncStatus.idle);
  }

  /// Public trigger — call from UI after explicit user action
  Future<void> flushNow() => _flush();

  // ----------------------------------------------------------------
  // Execute a single SyncOperation against Firestore
  // ----------------------------------------------------------------

  Future<void> _executeOp(SyncOperation op) async {
    final user = await AuthService.instance.getCurrentUser();
    if (user == null) throw Exception('unauthenticated');

    final adminUid = user.isAdmin ? user.uid : user.adminUid;
    if (adminUid == null) throw Exception('no adminUid');

    final itemsRef = _db
        .collection('inventory')
        .doc(adminUid)
        .collection('items');

    final deletedRef = _db
        .collection('inventory')
        .doc(adminUid)
        .collection('deleted_items');

    switch (op.type) {
      case SyncOpType.insert:
        final payload = op.payload!;
        final docId = op.itemId!.startsWith('tmp_')
            ? itemsRef.doc().id   // let Firestore generate real ID
            : op.itemId!;

        await itemsRef.doc(docId).set({
          ...payload,
          'adminUid':  adminUid,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // If it was a temp ID → update Hive with real Firestore ID
        if (op.itemId!.startsWith('tmp_')) {
          final localData = _hive.getAllItems()
              .where((i) => i.id == op.itemId)
              .firstOrNull;

          if (localData != null) {
            await _hive.deleteItem(op.itemId!);
            await _hive.insertItem(localData.copyWith(id: docId));
          }
        }

      case SyncOpType.update:
        final payload = op.payload!;
        await itemsRef.doc(op.itemId!).update({
          ...payload,
          'updatedAt': FieldValue.serverTimestamp(),
        });

      case SyncOpType.deleteWithReason:
        final payload    = op.payload!;
        final firestoreId = op.itemId!;

        // FIX: skip tmp_ IDs — item was never written to Firestore
        if (firestoreId.startsWith('tmp_')) break;

        // FIX: check item exists before batching to avoid silent failures
        final docSnap = await itemsRef.doc(firestoreId).get();
        if (!docSnap.exists) {
          // Item already gone from Firestore — just write the deleted_items entry
          await deletedRef.doc().set({
            ...payload,
            'deleteReason': op.reason ?? '',
            'deleteNotes':  op.extraNotes ?? '',
            'deletedAt':    FieldValue.serverTimestamp(),
            'deletedByUid': op.actorUid,
            'adminUid':     adminUid,
          });
          break;
        }

        final batch     = _db.batch();
        final delDocRef = deletedRef.doc();
        batch.set(delDocRef, {
          ...payload,
          'deleteReason': op.reason ?? '',
          'deleteNotes':  op.extraNotes ?? '',
          'deletedAt':    FieldValue.serverTimestamp(),
          'deletedByUid': op.actorUid,
          'adminUid':     adminUid,
        });
        batch.delete(itemsRef.doc(firestoreId));
        await batch.commit();

      case SyncOpType.delete:
        // FIX: graceful skip if already deleted
        final delSnap = await itemsRef.doc(op.itemId!).get();
        if (delSnap.exists) {
          await itemsRef.doc(op.itemId!).delete();
        }

      case SyncOpType.batchInsert:
        // Handled separately by InventoryRepository.insertBatch
        break;
    }
  }

  // ----------------------------------------------------------------
  // Pull latest from Firestore → refresh Hive (manual / background)
  // Not called automatically — triggered by pull-to-refresh or app resume
  // ----------------------------------------------------------------

  Future<void> pullLatest() async {
    if (!_isOnline) return;
    _setStatus(SyncStatus.syncing);
    try {
      if (_hive.hasPendingOps) {
        await _flush();
      }

      if (_hive.hasPendingOps) {
        _setStatus(SyncStatus.error);
        return;
      }

      final items      = await _fs.getAllItems();
      final warehouses = await _fs.getWarehouses();
      final products   = await _fs.getProducts();

      await Future.wait([
        _hive.seedItems(items),
        _hive.seedWarehouses(warehouses),
        _hive.seedProducts(products),
      ]);

      await _hive.markSynced();
      _setStatus(SyncStatus.idle);
    } catch (_) {
      _setStatus(SyncStatus.error);
    }
  }

  // ----------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------

  void _setStatus(SyncStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  SyncStatus get currentStatus => _status;
  bool get isOnline => _isOnline;
}