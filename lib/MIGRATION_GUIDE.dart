// ============================================================
// DIFF: main.dart — replace only the main() function
// Everything else (InventoryApp, HomeScreen, etc.) stays the same
// ============================================================

// ADD these imports at the top of main.dart:
//   import 'hive_service.dart';
//   import 'sync_engine.dart';
//   import 'inventory_repository.dart';
//   import 'package:connectivity_plus/connectivity_plus.dart';

// REPLACE your current main() with this:

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();

//   // 1. Firebase (same as before)
//   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

//   // 2. Hive — must come before any read/write
//   await HiveService.instance.init();

//   // 3. Notifications (same as before)
//   await NotificationService.instance.initialize();

//   runApp(const InventoryApp());
// }

// ============================================================
// AuthWrapper changes — after login, seed Hive + start SyncEngine
// ============================================================
//
// In auth_wrapper.dart, inside the block where you detect
// a logged-in user (after Firebase Auth confirms the user),
// add:
//
//   await SyncEngine.instance.start();
//   await SyncEngine.instance.seedIfNeeded();
//
// On logout, add:
//   SyncEngine.instance.stop();
//   await HiveService.instance.clearAll();
//
// ============================================================
// HomeScreen changes — load data from Repository, not FirestoreService
// ============================================================
//
// BEFORE:
//   final stats = await FirestoreService.instance.getStats(date: _selectedDate);
//   final dates = await FirestoreService.instance.getInventoryDates();
//
// AFTER (synchronous — no await needed):
//   final repo = InventoryRepository.instance;
//   final stats = repo.getStats(date: _selectedDate);
//   final dates = repo.getInventoryDates();
//
// For pull-to-refresh:
//   await InventoryRepository.instance.refresh();
//   setState(() { /* re-read from repo */ });
//
// ============================================================
// InventoryScreen changes
// ============================================================
//
// BEFORE:
//   _items = await FirestoreService.instance.getAllItems();
//   _items = await FirestoreService.instance.getItemsByDate(_selectedDate);
//   await FirestoreService.instance.insertItem(item);
//   await FirestoreService.instance.updateItem(item);
//   await FirestoreService.instance.deleteWithReason(item, reason: r);
//
// AFTER:
//   _items = InventoryRepository.instance.getAllItems();        // sync
//   _items = InventoryRepository.instance.getItemsByDate(d);   // sync
//   await InventoryRepository.instance.insertItem(item);       // returns instantly
//   await InventoryRepository.instance.updateItem(item);
//   await InventoryRepository.instance.deleteWithReason(item, reason: r);
//
// ============================================================
// ScannerScreen / AddItemScreen changes
// ============================================================
//
// BEFORE:
//   final warehouses = await FirestoreService.instance.getWarehouses();
//   final products   = await FirestoreService.instance.getProducts();
//   await FirestoreService.instance.insertItem(item);
//
// AFTER:
//   final warehouses = InventoryRepository.instance.getWarehouses(); // sync
//   final products   = InventoryRepository.instance.getProducts();   // sync
//   await InventoryRepository.instance.insertItem(item);
//
// ============================================================
// Sync status indicator (optional — add to HomeScreen AppBar)
// ============================================================
//
// StreamBuilder<SyncStatus>(
//   stream: SyncEngine.instance.statusStream,
//   builder: (context, snap) {
//     final status = snap.data ?? SyncStatus.idle;
//     return switch (status) {
//       SyncStatus.syncing => const SizedBox(
//           width: 16, height: 16,
//           child: CircularProgressIndicator(
//             strokeWidth: 2, color: Colors.white70,
//           ),
//         ),
//       SyncStatus.offline => const Icon(Icons.cloud_off, size: 18, color: Colors.white60),
//       SyncStatus.error   => const Icon(Icons.sync_problem, size: 18, color: Colors.orangeAccent),
//       SyncStatus.idle    => const SizedBox.shrink(),
//     };
//   },
// )
//
// ============================================================
// pubspec.yaml — add these dependencies
// ============================================================
//
// dependencies:
//   hive: ^2.2.3
//   hive_flutter: ^1.1.0
//   connectivity_plus: ^6.0.3
//
// No build_runner needed — we store Map<dynamic,dynamic> directly,
// no TypeAdapter code generation required.