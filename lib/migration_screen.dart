import 'package:flutter/material.dart';
import 'database.dart' as sqlite;
import 'firestore_service.dart';
import 'auth_service.dart';

class MigrationScreen extends StatefulWidget {
  const MigrationScreen({super.key});

  @override
  State<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends State<MigrationScreen> {
  bool _migrating = false;
  bool _done = false;
  String _status = '';
  MigrationResult? _result;

  Future<void> _startMigration() async {
    setState(() {
      _migrating = true;
      _status = 'جاري قراءة البيانات من الجهاز...';
    });

    try {
      final currentUser = await AuthService.instance.getCurrentUser();
      if (currentUser == null || !currentUser.isAdmin) {
        setState(() {
          _migrating = false;
          _status = 'خطأ: يجب أن تكون Admin لنقل البيانات';
        });
        return;
      }

      // ✅ اقرأ كل البيانات من SQLite
      setState(() => _status = 'جاري قراءة المخزون...');
      final items = await sqlite.DatabaseHelper.instance.getAllItems();

      setState(() => _status = 'جاري قراءة المخازن...');
      final warehouses = await sqlite.DatabaseHelper.instance.getWarehouses();

      setState(() => _status = 'جاري قراءة المنتجات...');
      final products = await sqlite.DatabaseHelper.instance.getProducts();

      setState(() => _status = 'جاري قراءة سجل الحذف...');
      final deletedItems = await sqlite.DatabaseHelper.instance.getDeletedItems();

      setState(() => _status =
          'جاري رفع ${items.length} قطعة، ${warehouses.length} مخزن، ${products.length} منتج...');

      // ✅ تحويل SQLite InventoryItem → Firestore InventoryItem
      final firestoreItems = items.map((i) => InventoryItem(
        warehouseName: i.warehouseName,
        productName: i.productName,
        serial: i.serial,
        condition: i.condition,
        expiryDate: i.expiryDate,
        notes: i.notes,
        inventoryDate: i.inventoryDate,
        addedByUid: i.addedByUid,
        adminUid: currentUser.uid,
      )).toList();

      // ✅ ابدأ الـ Migration
      final result = await FirestoreService.instance.migrateFromSQLite(
        firestoreItems,
        warehouses,
        products,
        deletedItems,
        currentUser.uid,
      );

      setState(() {
        _migrating = false;
        _done = result.success;
        _result = result;
        _status = result.success ? 'تم النقل بنجاح ✅' : 'خطأ: ${result.error}';
      });
    } catch (e) {
      setState(() {
        _migrating = false;
        _status = 'خطأ غير متوقع: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF16324F),
        // Fix: add AppBar with back button — screen was unreachable without it
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.pop(context),
            tooltip: 'رجوع',
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // أيقونة
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    _done ? Icons.cloud_done : Icons.cloud_upload,
                    size: 45,
                    color: const Color(0xFF16324F),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'نقل البيانات للسحابة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'هننقل كل بياناتك من الجهاز لـ Firestore\nعشان تقدر تشاركها مع فريقك',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      if (!_migrating && !_done && _status.isEmpty) ...[
                        const Icon(Icons.info_outline,
                            color: Color(0xFF16324F), size: 40),
                        const SizedBox(height: 12),
                        const Text(
                          'هيتم نقل:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        _infoRow(Icons.inventory_2, 'كل قطع المخزون'),
                        _infoRow(Icons.warehouse, 'المخازن'),
                        _infoRow(Icons.category, 'المنتجات'),
                        _infoRow(Icons.delete_outline, 'سجل المحذوفات'),
                        const SizedBox(height: 16),
                        const Text(
                          'ملاحظة: البيانات القديمة على الجهاز هتفضل موجودة كـ backup',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      if (_migrating) ...[
                        // Fix: step-based progress — more informative than bare spinner
                        const CircularProgressIndicator(
                            color: Color(0xFF16324F), strokeWidth: 3),
                        const SizedBox(height: 16),
                        Text(
                          _status,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation(Color(0xFF16324F)),
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],

                      if (_done && _result != null) ...[
                        const Icon(Icons.check_circle,
                            color: Colors.green, size: 50),
                        const SizedBox(height: 12),
                        const Text('تم النقل بنجاح! 🎉',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.green)),
                        const SizedBox(height: 12),
                        _resultRow('قطع المخزون', _result!.itemsMigrated),
                        _resultRow('مخازن', _result!.warehousesMigrated),
                        _resultRow('منتجات', _result!.productsMigrated),
                        _resultRow('سجل المحذوفات', _result!.deletedMigrated),
                      ],

                      if (!_migrating && !_done && _status.isNotEmpty) ...[
                        Icon(Icons.error_outline,
                            color: Colors.red.shade400, size: 40),
                        const SizedBox(height: 8),
                        Text(_status,
                            style: TextStyle(color: Colors.red.shade700),
                            textAlign: TextAlign.center),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Buttons
                if (!_migrating && !_done)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _startMigration,
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text('ابدأ النقل',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF16324F),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                if (_done) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.check),
                      label: const Text('متابعة',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF16324F)),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _resultRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text('$count ✓',
              style: const TextStyle(
                  fontSize: 13,
                  color: Colors.green,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}