import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firestore_service.dart';   // للـ updateWarehouse/updateProduct فقط (rename)
import 'inventory_repository.dart';
import 'auth_service.dart';
import 'app_localizations.dart';
import 'log_service.dart';

class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key});
  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<String> _warehouses = [];
  List<String> _products   = [];
  bool _loading = true;

  static const Color _primary = Color(0xFF16324F);
  static const Color _gold    = Color(0xFFC69749);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ──────────────────── Data ────────────────────────────────
  // ✅ FIX: قرأ من Hive مباشرة (sync — zero network)
  Future<void> _loadData() async {
    final currentUser = await AuthService.instance.getCurrentUser();
    if (currentUser == null || !currentUser.canManage) {
      if (mounted) {
        _showSnack(AppLocalizations.noPermissionManage, Colors.red);
        Navigator.pop(context);
      }
      return;
    }
    final repo = InventoryRepository.instance;
    // ✅ Synchronous reads from Hive — no await needed
    if (mounted) {
      setState(() {
        _warehouses = repo.getWarehouses();
        _products   = repo.getProducts();
        _loading    = false;
      });
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      ),
    );
  }

  // ──────────────────── Warehouse CRUD ──────────────────────
  Future<void> _addWarehouse() async {
    final result = await _showInputDialog(
      title: AppLocalizations.addWarehouse,
      hint:  AppLocalizations.warehouseNameHint,
      icon:  Icons.warehouse_rounded,
    );
    if (result == null || result.isEmpty) return;

    // ✅ FIX: اكتب على Hive أولاً → UI يتحدث فوراً
    await InventoryRepository.instance.addWarehouse(result);
    // ✅ Push لـ Firestore في الخلفية (fire-and-forget)
    FirestoreService.instance.addWarehouse(result);

    _showSnack(AppLocalizations.warehouseAddedSuccess, Colors.green);
    // ✅ Reload من Hive — مش من Firestore
    setState(() {
      _warehouses = InventoryRepository.instance.getWarehouses();
    });
  }

  Future<void> _editWarehouse(String old) async {
    final result = await _showInputDialog(
      title:   AppLocalizations.editWarehouse,
      hint:    AppLocalizations.warehouseNameHint,
      icon:    Icons.edit_rounded,
      initial: old,
    );
    if (result == null || result.isEmpty || result == old) return;

    // ✅ Hive: حذف القديم وأضف الجديد
    await InventoryRepository.instance.removeWarehouse(old);
    await InventoryRepository.instance.addWarehouse(result);
    // ✅ Firestore في الخلفية
    FirestoreService.instance.updateWarehouse(old, result);

    setState(() {
      _warehouses = InventoryRepository.instance.getWarehouses();
    });
  }

  Future<void> _deleteWarehouse(String name) async {
    final confirm = await _showDeleteDialog(
      title: AppLocalizations.deleteWarehouseTitle,
      itemName: name,
    );
    if (confirm != true) return;

    // ✅ Hive أولاً
    await InventoryRepository.instance.removeWarehouse(name);
    // ✅ Firestore في الخلفية
    FirestoreService.instance.deleteWarehouse(name);

    LogService.instance.log(
      type: LogType.itemDeleted,
      warehouse: name,
      details: 'حذف مخزن: $name',
    );
    setState(() {
      _warehouses = InventoryRepository.instance.getWarehouses();
    });
  }

  // ──────────────────── Product CRUD ────────────────────────
  Future<void> _addProduct() async {
    final result = await _showInputDialog(
      title: AppLocalizations.addProduct,
      hint:  AppLocalizations.productNameHint,
      icon:  Icons.inventory_2_rounded,
    );
    if (result == null || result.isEmpty) return;

    await InventoryRepository.instance.addProduct(result);
    FirestoreService.instance.addProduct(result);

    _showSnack(AppLocalizations.productAddedSuccess, Colors.green);
    setState(() {
      _products = InventoryRepository.instance.getProducts();
    });
  }

  Future<void> _editProduct(String old) async {
    final result = await _showInputDialog(
      title:   AppLocalizations.editProduct,
      hint:    AppLocalizations.productNameHint,
      icon:    Icons.edit_rounded,
      initial: old,
    );
    if (result == null || result.isEmpty || result == old) return;

    await InventoryRepository.instance.removeProduct(old);
    await InventoryRepository.instance.addProduct(result);
    FirestoreService.instance.updateProduct(old, result);

    setState(() {
      _products = InventoryRepository.instance.getProducts();
    });
  }

  Future<void> _deleteProduct(String name) async {
    final confirm = await _showDeleteDialog(
      title: AppLocalizations.deleteProductTitle,
      itemName: name,
    );
    if (confirm != true) return;

    await InventoryRepository.instance.removeProduct(name);
    FirestoreService.instance.deleteProduct(name);

    LogService.instance.log(
      type: LogType.itemDeleted,
      product: name,
      details: 'حذف منتج: $name',
    );
    setState(() {
      _products = InventoryRepository.instance.getProducts();
    });
  }

  // ──────────────────── Dialogs ─────────────────────────────
  Future<String?> _showInputDialog({
    required String title,
    required String hint,
    required IconData icon,
    String? initial,
  }) async {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ]),
          content: Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: TextField(
              controller: ctrl,
              autofocus: true,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: hint,
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _primary, width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onSubmitted: (val) => Navigator.pop(ctx, val.trim()),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.cancel,
                  style: TextStyle(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: Text(
                initial != null ? AppLocalizations.save : AppLocalizations.add,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showDeleteDialog(
      {required String title, required String itemName}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection:
            AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.delete_outline_rounded,
                  color: Colors.red.shade600, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800))),
          ]),
          content: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Text(
              '"$itemName"',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Colors.red.shade700),
              textAlign: TextAlign.center,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.cancel,
                  style: TextStyle(color: Colors.grey.shade600)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: Text(AppLocalizations.delete,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────── List Widget ─────────────────────────
  Widget _buildList(List<String> items, bool isWarehouse) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
                color: _primary, strokeWidth: 2.5),
            const SizedBox(height: 12),
            Text(AppLocalizations.loading,
                style:
                    TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isWarehouse
                    ? Icons.warehouse_rounded
                    : Icons.inventory_2_rounded,
                size: 36,
                color: _primary.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isWarehouse
                  ? AppLocalizations.noWarehouses
                  : AppLocalizations.noProducts,
              style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              isWarehouse
                  ? (AppLocalizations.isArabic
                      ? 'اضغط + لإضافة مخزن جديد'
                      : 'Tap + to add a warehouse')
                  : (AppLocalizations.isArabic
                      ? 'اضغط + لإضافة منتج جديد'
                      : 'Tap + to add a product'),
              style:
                  TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _primary.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _primary.withValues(alpha: 0.12),
                    _primary.withValues(alpha: 0.06)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isWarehouse
                    ? Icons.warehouse_rounded
                    : Icons.inventory_2_rounded,
                color: _primary,
                size: 20,
              ),
            ),
            title: Text(
              item,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _actionBtn(
                  icon: Icons.edit_rounded,
                  color: _primary,
                  onTap: () => isWarehouse
                      ? _editWarehouse(item)
                      : _editProduct(item),
                  tooltip: AppLocalizations.edit,
                ),
                const SizedBox(width: 4),
                _actionBtn(
                  icon: Icons.delete_outline_rounded,
                  color: Colors.red.shade400,
                  onTap: () => isWarehouse
                      ? _deleteWarehouse(item)
                      : _deleteProduct(item),
                  tooltip: AppLocalizations.delete,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  // ──────────────────── Build ───────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isWarehouses = _tabController.index == 0;

    return Directionality(
      textDirection:
          AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            AppLocalizations.manageListsTitle,
            style:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: _primary,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                indicatorSize: TabBarIndicatorSize.tab,
                padding: const EdgeInsets.all(3),
                dividerColor: Colors.transparent,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warehouse_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text(
                            '${AppLocalizations.warehouses} (${_warehouses.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_rounded, size: 16),
                        const SizedBox(width: 6),
                        Text(
                            '${AppLocalizations.products} (${_products.length})'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
            HapticFeedback.mediumImpact();
            isWarehouses ? _addWarehouse() : _addProduct();
          },
          backgroundColor: _gold,
          foregroundColor: Colors.white,
          elevation: 4,
          icon: const Icon(Icons.add_rounded, size: 22),
          label: Text(
            isWarehouses
                ? AppLocalizations.addWarehouse
                : AppLocalizations.addProduct,
            style:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}