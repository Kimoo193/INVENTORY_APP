import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firestore_service.dart';   // InventoryItem model only
import 'inventory_repository.dart';
import 'scanner_screen.dart';
import 'delete_dialog.dart';
import 'auth_service.dart';
import 'app_localizations.dart';

// ============================================================
// Filter Model
// ============================================================
class InventoryFilter {
  final String? warehouse;
  final String? condition;
  final String sortBy;

  const InventoryFilter({this.warehouse, this.condition, this.sortBy = 'date'});

  bool get isActive => warehouse != null || condition != null || sortBy != 'date';

  InventoryFilter copyWith({
    String? warehouse, String? condition, String? sortBy,
    bool clearWarehouse = false, bool clearCondition = false,
  }) {
    return InventoryFilter(
      warehouse: clearWarehouse ? null : (warehouse ?? this.warehouse),
      condition: clearCondition ? null : (condition ?? this.condition),
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

// ============================================================
// InventoryScreen
// ============================================================
class InventoryScreen extends StatefulWidget {
  final String? selectedDate;
  final VoidCallback? onRefresh;
  final AppUser? currentUser;

  const InventoryScreen({
    super.key,
    this.selectedDate,
    this.onRefresh,
    this.currentUser,
  });

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<InventoryItem> _items    = [];
  List<InventoryItem> _filtered = [];
  List<String>        _warehouses = [];
  final _searchController = TextEditingController();
  bool _loading = true;
  InventoryFilter _filter = const InventoryFilter();

  // ✅ cache user من الـ parent — مش بنعمل Firestore call في كل عملية
  AppUser? _user;

  @override
  void initState() {
    super.initState();
    _user = widget.currentUser;
    _loadItems();
  }

  @override
  void didUpdateWidget(InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentUser != null) _user = widget.currentUser;
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.currentUser?.uid != widget.currentUser?.uid) {
      _loadItems();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------
  // Load — ✅ FIX: قرأ من Hive (sync) مش Firestore
  // ----------------------------------------------------------------
  Future<void> _loadItems() async {
    if (!mounted) return;
    setState(() => _loading = true);

    // ✅ Synchronous reads from Hive — zero network, zero await
    final repo  = InventoryRepository.instance;
    final items = widget.selectedDate != null
        ? repo.getItemsByDate(widget.selectedDate!)
        : repo.getAllItems();
    final warehouses = repo.getWarehouses();

    if (!mounted) return;
    setState(() {
      _items      = items;
      _warehouses = warehouses;
      _loading    = false;
    });
    _applyFilterNoState();
    if (mounted) setState(() {});
  }

  // ✅ Pull-to-refresh — يجيب من Firestore ويحدّث Hive ثم يعيد القراءة
  Future<void> _onRefresh() async {
    await InventoryRepository.instance.refresh();
    await _loadItems();
    widget.onRefresh?.call();
  }

  // ----------------------------------------------------------------
  // Filter — بدون setState زيادة
  // ----------------------------------------------------------------
  void _applyFilterNoState() {
    var r = List<InventoryItem>.from(_items);
    final q = _searchController.text.toLowerCase().trim();

    if (q.isNotEmpty) {
      r = r.where((i) =>
          i.productName.toLowerCase().contains(q) ||
          (i.serial?.toLowerCase().contains(q) ?? false) ||
          i.warehouseName.toLowerCase().contains(q)).toList();
    }
    if (_filter.warehouse != null) {
      r = r.where((i) => i.warehouseName == _filter.warehouse).toList();
    }
    if (_filter.condition != null) {
      r = r.where((i) => i.condition == _filter.condition).toList();
    }
    switch (_filter.sortBy) {
      case 'product':
        r.sort((a, b) => a.productName.compareTo(b.productName));
        break;
      case 'serial':
        r.sort((a, b) {
          final sa = (a.serial ?? '').trim().toLowerCase();
          final sb = (b.serial ?? '').trim().toLowerCase();
          if (sa.isEmpty && sb.isNotEmpty) return 1;
          if (sa.isNotEmpty && sb.isEmpty) return -1;

          final bySerial = sa.compareTo(sb);
          if (bySerial != 0) return bySerial;
          return a.productName.compareTo(b.productName);
        });
        break;
      case 'warehouse':
        r.sort((a, b) => a.warehouseName.compareTo(b.warehouseName));
        break;
      default:
        r.sort((a, b) => b.inventoryDate.compareTo(a.inventoryDate));
    }
    _filtered = r;
  }

  void _applyFilter() {
    _applyFilterNoState();
    if (mounted) setState(() {});
  }

  // ----------------------------------------------------------------
  // Filter Sheet
  // ----------------------------------------------------------------
  void _showFilterSheet() async {
    InventoryFilter tmp = _filter;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Directionality(
          textDirection: AppLocalizations.isArabic
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 16),

                Row(children: [
                  const Icon(Icons.tune_rounded,
                      color: Color(0xFF1A237E), size: 22),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.filterTitle,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E))),
                  const Spacer(),
                  if (tmp.isActive)
                    TextButton.icon(
                      onPressed: () =>
                          set(() => tmp = const InventoryFilter()),
                      icon: const Icon(Icons.clear, size: 14),
                      label: Text(AppLocalizations.resetFilter,
                          style: const TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.red),
                    ),
                ]),
                const SizedBox(height: 20),

                // Warehouse
                _filterSectionLabel(
                    AppLocalizations.filterByWarehouse,
                    Icons.warehouse_rounded),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _filterChip(
                        AppLocalizations.allWarehouses,
                        tmp.warehouse == null,
                        () => set(() => tmp =
                            tmp.copyWith(clearWarehouse: true))),
                    ..._warehouses.map((w) => _filterChip(
                        w,
                        tmp.warehouse == w,
                        () => set(
                            () => tmp = tmp.copyWith(warehouse: w)))),
                  ]),
                ),
                const SizedBox(height: 20),

                // Condition
                _filterSectionLabel(
                    AppLocalizations.filterByCondition,
                    Icons.info_outline_rounded),
                const SizedBox(height: 8),
                Row(children: [
                  _filterChip(
                      AppLocalizations.allConditions,
                      tmp.condition == null,
                      () => set(() => tmp =
                          tmp.copyWith(clearCondition: true))),
                  const SizedBox(width: 8),
                  _condChip(
                      AppLocalizations.newCond,
                      'جديد',
                      tmp.condition,
                      const Color(0xFF2E7D32),
                      Icons.check_circle_rounded,
                      () => set(() =>
                          tmp = tmp.copyWith(condition: 'جديد'))),
                  const SizedBox(width: 8),
                  _condChip(
                      AppLocalizations.used,
                      'مستخدم',
                      tmp.condition,
                      const Color(0xFFE65100),
                      Icons.loop_rounded,
                      () => set(() =>
                          tmp = tmp.copyWith(condition: 'مستخدم'))),
                  const SizedBox(width: 8),
                  _condChip(
                      AppLocalizations.damaged,
                      'تالف',
                      tmp.condition,
                      const Color(0xFFC62828),
                      Icons.warning_rounded,
                      () => set(() =>
                          tmp = tmp.copyWith(condition: 'تالف'))),
                ]),
                const SizedBox(height: 20),

                // Sort
                _filterSectionLabel(
                    AppLocalizations.sortBy, Icons.sort_rounded),
                const SizedBox(height: 8),
                Row(children: [
                  _sortChip(AppLocalizations.sortDate, 'date',
                      tmp.sortBy,
                      () => set(
                          () => tmp = tmp.copyWith(sortBy: 'date'))),
                  const SizedBox(width: 8),
                  _sortChip(AppLocalizations.sortProduct, 'product',
                      tmp.sortBy,
                      () => set(() =>
                          tmp = tmp.copyWith(sortBy: 'product'))),
                  const SizedBox(width: 8),
                  _sortChip(AppLocalizations.sortSerial, 'serial',
                    tmp.sortBy,
                    () => set(() =>
                      tmp = tmp.copyWith(sortBy: 'serial'))),
                  const SizedBox(width: 8),
                  _sortChip(AppLocalizations.sortWarehouse,
                      'warehouse', tmp.sortBy,
                      () => set(() =>
                          tmp = tmp.copyWith(sortBy: 'warehouse'))),
                ]),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A237E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding:
                            const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _filter = tmp);
                      _applyFilter();
                    },
                    child: Text(AppLocalizations.applyFilter,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Delete — ✅ FIX: حذف محلي فوري ثم sync في الخلفية
  // ----------------------------------------------------------------
  Future<void> _deleteItem(InventoryItem item) async {
    // ✅ استخدم الـ cached user — مش Firestore call جديدة
    if (_user == null || !_user!.canDelete) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.noPermissionDelete)));
      }
      return;
    }
    final deleted = await showDeleteWithReasonDialog(context, item);
    if (deleted) {
      // ✅ حدّث الـ UI فوراً من Hive (اللي اتحدث في delete_dialog)
      setState(() {
        _items.removeWhere((i) => i.id == item.id);
        _filtered.removeWhere((i) => i.id == item.id);
      });
      widget.onRefresh?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${AppLocalizations.isArabic ? "تم حذف" : "Deleted"} "${item.productName}"'),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  // ----------------------------------------------------------------
  // Move — ✅ FIX: استخدم Hive warehouses مش Firestore
  // ----------------------------------------------------------------
  Future<void> _moveItem(InventoryItem item) async {
    // ✅ من Hive — zero network
    final other =
        _warehouses.where((w) => w != item.warehouseName).toList();
    if (other.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.noOtherWarehouses)));
      }
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: AppLocalizations.isArabic
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: AlertDialog(
          title: Text(AppLocalizations.moveTo),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${AppLocalizations.from} ${item.warehouseName}',
                style: TextStyle(
                    color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 12),
            ...other.map((w) => ListTile(
                title: Text(w),
                leading: const Icon(Icons.warehouse_rounded,
                    color: Color(0xFF1A237E)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                onTap: () => Navigator.pop(ctx, w))),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.cancel))
          ],
        ),
      ),
    );

    if (selected != null && item.id != null) {
      // ✅ Repository يكتب على Hive فوراً ويقيّل Firestore في الخلفية
      await InventoryRepository.instance
          .updateItem(item.copyWith(warehouseName: selected));

      // ✅ حدّث UI محلياً فوراً
      setState(() {
        final idx = _items.indexWhere((i) => i.id == item.id);
        if (idx != -1) {
          _items[idx] = item.copyWith(warehouseName: selected);
        }
        _applyFilterNoState();
      });

      widget.onRefresh?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${AppLocalizations.isArabic ? "تم النقل إلى:" : "Moved to:"} $selected ✅'),
          backgroundColor: Colors.green,
        ));
      }
    }
  }

  // ----------------------------------------------------------------
  // Helpers
  // ----------------------------------------------------------------
  Color _condColor(String c) {
    switch (c) {
      case 'جديد':    return const Color(0xFF2E7D32);
      case 'مستخدم':  return const Color(0xFFE65100);
      case 'تالف':    return const Color(0xFFC62828);
      default:        return Colors.grey;
    }
  }

  String _localCond(String c) {
    if (AppLocalizations.isArabic) return c;
    switch (c) {
      case 'جديد':   return 'New';
      case 'مستخدم': return 'Used';
      case 'تالف':   return 'Damaged';
      default:       return c;
    }
  }

  Widget _filterSectionLabel(String label, IconData icon) {
    return Row(children: [
      Icon(icon, size: 16, color: const Color(0xFF1A237E)),
      const SizedBox(width: 6),
      Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF1A237E))),
    ]);
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(left: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1A237E)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : Colors.grey.shade700,
                fontSize: 13,
                fontWeight: selected
                    ? FontWeight.bold
                    : FontWeight.normal)),
      ),
    );
  }

  Widget _condChip(String label, String value, String? selected,
      Color color, IconData icon, VoidCallback onTap) {
    final isSel = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isSel ? color.withOpacity(0.15) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSel ? color : Colors.grey.shade200),
          ),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Icon(icon, size: 14, color: isSel ? color : Colors.grey),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: isSel ? color : Colors.grey.shade600,
                    fontWeight: isSel
                        ? FontWeight.bold
                        : FontWeight.normal)),
          ]),
        ),
      ),
    );
  }

  Widget _sortChip(String label, String value, String current,
      VoidCallback onTap) {
    final isSel = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: isSel
                ? const Color(0xFF1A237E)
                : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSel
                    ? const Color(0xFF1A237E)
                    : Colors.grey.shade200),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: isSel ? Colors.white : Colors.grey.shade600,
                  fontWeight: isSel
                      ? FontWeight.bold
                      : FontWeight.normal)),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isAdmin = _user?.isAdmin ?? true;

    return Directionality(
      textDirection: AppLocalizations.isArabic
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Column(children: [
        // ── Search + Filter ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (_) => _applyFilter(),
                decoration: InputDecoration(
                  hintText: AppLocalizations.search,
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 20, color: Colors.grey),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _applyFilter();
                          })
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          BorderSide(color: Colors.grey.shade200)),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _showFilterSheet();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: _filter.isActive
                      ? const Color(0xFF1A237E)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _filter.isActive
                          ? const Color(0xFF1A237E)
                          : Colors.grey.shade200),
                ),
                child: Icon(Icons.tune_rounded,
                    size: 22,
                    color: _filter.isActive
                        ? Colors.white
                        : Colors.grey.shade600),
              ),
            ),
          ]),
        ),

        // ── Count + Active Filters ──
        if (_filtered.isNotEmpty ||
            _filter.isActive ||
            _user?.assignedWarehouse != null)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Row(children: [
              Text('${_filtered.length} ${AppLocalizations.pieces}',
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 12)),
              if (!isAdmin && _user?.assignedWarehouse != null) ...[
                const SizedBox(width: 6),
                _activePill('📦 ${_user!.assignedWarehouse}',
                    const Color(0xFF1A237E), null),
              ],
              if (_filter.warehouse != null) ...[
                const SizedBox(width: 6),
                _activePill('🏢 ${_filter.warehouse}', Colors.indigo,
                    () {
                  setState(() => _filter =
                      _filter.copyWith(clearWarehouse: true));
                  _applyFilter();
                }),
              ],
              if (_filter.condition != null) ...[
                const SizedBox(width: 6),
                _activePill(
                    '● ${_localCond(_filter.condition!)}',
                    _condColor(_filter.condition!), () {
                  setState(() => _filter =
                      _filter.copyWith(clearCondition: true));
                  _applyFilter();
                }),
              ],
            ]),
          ),

        // ── List ──
        Expanded(
          child: _loading
              ? _buildSkeleton()
              : _filtered.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: _onRefresh, // ✅ يجيب من Firestore ويحدث Hive
                      color: const Color(0xFF1A237E),
                      child: ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(12, 4, 12, 80),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) =>
                            _buildItemCard(_filtered[i], isAdmin),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _activePill(
      String label, Color color, VoidCallback? onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.bold)),
        if (onRemove != null) ...[
          const SizedBox(width: 3),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close, size: 12, color: color),
          ),
        ],
      ]),
    );
  }

  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        height: 80,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(
              width: 4, height: 80,
              decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4)))),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shimmer(width: 160, height: 12),
              const SizedBox(height: 8),
              _shimmer(width: 100, height: 10),
              const SizedBox(height: 6),
              _shimmer(width: 80, height: 10),
            ],
          )),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _shimmer(width: 48, height: 24),
          ),
        ]),
      ),
    );
  }

  Widget _shimmer({required double width, required double height}) {
    return Container(
        width: width, height: height,
        decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(6)));
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.isNotEmpty;
    final hasFilter = _filter.isActive;
    return Center(
      child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
        Icon(
          hasSearch
              ? Icons.search_off_rounded
              : Icons.inventory_2_outlined,
          size: 72,
          color: Colors.grey.shade300,
        ),
        const SizedBox(height: 16),
        Text(
          hasSearch
              ? (AppLocalizations.isArabic
                  ? 'لا نتائج للبحث'
                  : 'No search results')
              : hasFilter
                  ? (AppLocalizations.isArabic
                      ? 'لا يوجد عناصر بهذا الفلتر'
                      : 'No items match filter')
                  : AppLocalizations.noItems,
          style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 16,
              fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        if (hasSearch || hasFilter)
          TextButton.icon(
            onPressed: () {
              _searchController.clear();
              setState(() => _filter = const InventoryFilter());
              _applyFilter();
            },
            icon: const Icon(Icons.clear_all),
            label: Text(AppLocalizations.isArabic
                ? 'مسح الفلاتر'
                : 'Clear Filters'),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF1A237E)),
          ),
      ]),
    );
  }

  Widget _buildItemCard(InventoryItem item, bool isAdmin) {
    final cc       = _condColor(item.condition);
    final canEdit   = _user?.canEdit   == true || isAdmin;
    final canDelete = _user?.canDelete == true || isAdmin;

    return Dismissible(
      key: Key(item.id ?? item.serial ?? item.productName),
      direction: canDelete
          ? DismissDirection.endToStart
          : DismissDirection.none,
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        return true;
      },
      onDismissed: (_) => _deleteItem(item),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
          const Icon(Icons.delete_outline,
              color: Colors.white, size: 26),
          const SizedBox(height: 4),
          Text(AppLocalizations.delete,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.shade100)),
        color: Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: canEdit
              ? () async {
                  final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              AddItemScreen(itemToEdit: item)));
                  if (result == true) {
                    // ✅ Reload من Hive — فوري
                    await _loadItems();
                    widget.onRefresh?.call();
                  }
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 4, height: 60,
                decoration: BoxDecoration(
                    color: cc,
                    borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(item.productName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.warehouse_rounded,
                        size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 3),
                    Flexible(
                        child: Text(item.warehouseName,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600),
                            overflow: TextOverflow.ellipsis)),
                  ]),
                  if (item.serial != null)
                    Row(children: [
                      Icon(Icons.qr_code_rounded,
                          size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Text(item.serial!,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600)),
                    ]),
                  if (item.expiryDate != null &&
                      item.expiryDate!.isNotEmpty)
                    Row(children: [
                      Icon(Icons.event_rounded,
                          size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 3),
                      Text(
                          '${AppLocalizations.expiry} ${item.expiryDate}',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600)),
                    ]),
                ]),
              ),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: cc.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(_localCond(item.condition),
                      style: TextStyle(
                          color: cc,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (isAdmin)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _moveItem(item);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(
                            Icons.drive_file_move_outlined,
                            color: Colors.blue.shade400,
                            size: 18),
                      ),
                    ),
                  if (isAdmin) const SizedBox(width: 6),
                  if (canDelete)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _deleteItem(item);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.delete_outline_rounded,
                            color: Colors.red.shade400, size: 18),
                      ),
                    ),
                ]),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}