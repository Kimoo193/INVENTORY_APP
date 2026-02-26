import 'package:flutter/material.dart';
import 'database.dart';

class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key});

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<String> _warehouses = [];
  List<String> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final warehouses = await DatabaseHelper.instance.getWarehouses();
    final products = await DatabaseHelper.instance.getProducts();
    setState(() {
      _warehouses = warehouses;
      _products = products;
      _loading = false;
    });
  }

  Future<void> _deleteWarehouse(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المخزن'),
        content: Text('هتحذف "$name"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('warehouses', where: 'name = ?', whereArgs: [name]);
      await _loadData();
    }
  }

  Future<void> _deleteProduct(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المنتج'),
        content: Text('هتحذف "$name"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete('products', where: 'name = ?', whereArgs: [name]);
      await _loadData();
    }
  }

  Future<void> _editWarehouse(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل المخزن'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'اسم المخزن'),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != oldName) {
      final db = await DatabaseHelper.instance.database;
      await db.update('warehouses', {'name': result},
          where: 'name = ?', whereArgs: [oldName]);
      await _loadData();
    }
  }

  Future<void> _editProduct(String oldName) async {
    final controller = TextEditingController(text: oldName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل المنتج'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'اسم المنتج'),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != oldName) {
      final db = await DatabaseHelper.instance.database;
      await db.update('products', {'name': result},
          where: 'name = ?', whereArgs: [oldName]);
      await _loadData();
    }
  }

  Future<void> _addWarehouse() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مخزن جديد'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'اسم المخزن'),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('إضافة')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await DatabaseHelper.instance.addWarehouse(result);
      await _loadData();
    }
  }

  Future<void> _addProduct() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة منتج جديد'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'اسم المنتج'),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('إضافة')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await DatabaseHelper.instance.addProduct(result);
      await _loadData();
    }
  }

  Widget _buildList(List<String> items, bool isWarehouse) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isWarehouse ? Icons.warehouse_outlined : Icons.inventory_2_outlined,
              size: 56,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              isWarehouse ? 'لا توجد مخازن' : 'لا توجد منتجات',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
              child: Icon(
                isWarehouse ? Icons.warehouse : Icons.inventory_2,
                color: const Color(0xFF1A237E),
                size: 20,
              ),
            ),
            title: Text(
              item,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontSize: 14),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Color(0xFF1A237E), size: 20),
                  onPressed: () => isWarehouse
                      ? _editWarehouse(item)
                      : _editProduct(item),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red.shade400, size: 20),
                  onPressed: () => isWarehouse
                      ? _deleteWarehouse(item)
                      : _deleteProduct(item),
                  tooltip: 'حذف',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة القوائم'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(
                icon: const Icon(Icons.warehouse),
                text: 'المخازن (${_warehouses.length})',
              ),
              Tab(
                icon: const Icon(Icons.inventory_2),
                text: 'المنتجات (${_products.length})',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildList(_warehouses, true),
            _buildList(_products, false),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            if (_tabController.index == 0) {
              _addWarehouse();
            } else {
              _addProduct();
            }
          },
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add),
          label: Text(
            _tabController.index == 0 ? 'إضافة مخزن' : 'إضافة منتج',
          ),
        ),
      ),
    );
  }
}