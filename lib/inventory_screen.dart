import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firestore_service.dart';
import 'scanner_screen.dart';
import 'delete_dialog.dart';
import 'auth_service.dart';
import 'app_localizations.dart';
import 'inventory_repository.dart';

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

  const InventoryScreen({super.key, this.selectedDate, this.onRefresh, this.currentUser});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<InventoryItem> _items = [];
  List<InventoryItem> _filtered = [];
  final _searchController = TextEditingController();
  bool _loading = true;
  bool _deleteDialogOpen = false;
  InventoryFilter _filter = const InventoryFilter();
  List<String> _warehouses = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void didUpdateWidget(InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate ||
        oldWidget.currentUser?.uid != widget.currentUser?.uid) {
      _loadItems();
    }
  }

  /// Called from parent when a new item is added — forces fresh reload
  void refreshFromParent() {
    _loadItems();
  }

  Future<void> _loadItems() async {
    if (mounted) setState(() => _loading = true);
    // Small delay to let Hive writes complete before reading
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final repo = InventoryRepository.instance;
    final items = widget.selectedDate != null
        ? repo.getItemsByDate(widget.selectedDate!)
        : repo.getAllItems();
    final warehouses = repo.getWarehouses();
    if (!mounted) return;
    setState(() {
      _items = items;
      _warehouses = warehouses;
      _loading = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
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
      case 'product': r.sort((a, b) => a.productName.compareTo(b.productName)); break;
      case 'warehouse': r.sort((a, b) => a.warehouseName.compareTo(b.warehouseName)); break;
      default: r.sort((a, b) => b.inventoryDate.compareTo(a.inventoryDate));
    }
    setState(() => _filtered = r);
  }

  // ============================================================
  // Filter Bottom Sheet — Advanced
  // ============================================================
  void _showFilterSheet() async {
    InventoryFilter tmp = _filter;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Directionality(
          textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
                )),
                const SizedBox(height: 16),

                // Header
                Row(children: [
                  const Icon(Icons.tune_rounded, color: Color(0xFF16324F), size: 22),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.filterTitle,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold,
                          color: Color(0xFF16324F))),
                  const Spacer(),
                  if (tmp.isActive)
                    TextButton.icon(
                      onPressed: () => set(() => tmp = const InventoryFilter()),
                      icon: const Icon(Icons.clear, size: 14),
                      label: Text(AppLocalizations.resetFilter,
                          style: const TextStyle(fontSize: 13)),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                ]),
                const SizedBox(height: 20),

                // ── Warehouse Filter ──
                _filterSectionLabel(AppLocalizations.filterByWarehouse, Icons.warehouse_rounded),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _filterChip(AppLocalizations.allWarehouses, tmp.warehouse == null,
                        () => set(() => tmp = tmp.copyWith(clearWarehouse: true))),
                    ..._warehouses.map((w) => _filterChip(w, tmp.warehouse == w,
                        () => set(() => tmp = tmp.copyWith(warehouse: w)))),
                  ]),
                ),
                const SizedBox(height: 20),

                // ── Condition Filter ──
                _filterSectionLabel(AppLocalizations.filterByCondition, Icons.info_outline_rounded),
                const SizedBox(height: 8),
                Row(children: [
                  _filterChip(AppLocalizations.allConditions, tmp.condition == null,
                      () => set(() => tmp = tmp.copyWith(clearCondition: true))),
                  const SizedBox(width: 8),
                  _condChip(AppLocalizations.newCond, 'جديد', tmp.condition,
                      const Color(0xFF2E7D32), Icons.check_circle_rounded,
                      () => set(() => tmp = tmp.copyWith(condition: 'جديد'))),
                  const SizedBox(width: 8),
                  _condChip(AppLocalizations.used, 'مستخدم', tmp.condition,
                      const Color(0xFFE65100), Icons.loop_rounded,
                      () => set(() => tmp = tmp.copyWith(condition: 'مستخدم'))),
                  const SizedBox(width: 8),
                  _condChip(AppLocalizations.damaged, 'تالف', tmp.condition,
                      const Color(0xFFC62828), Icons.warning_rounded,
                      () => set(() => tmp = tmp.copyWith(condition: 'تالف'))),
                ]),
                const SizedBox(height: 20),

                // ── Sort ──
                _filterSectionLabel(AppLocalizations.sortBy, Icons.sort_rounded),
                const SizedBox(height: 8),
                Row(children: [
                  _sortChip(AppLocalizations.sortDate, 'date', tmp.sortBy,
                      Icons.calendar_today_rounded,
                      () => set(() => tmp = tmp.copyWith(sortBy: 'date'))),
                  const SizedBox(width: 8),
                  _sortChip(AppLocalizations.sortProduct, 'product', tmp.sortBy,
                      Icons.sort_by_alpha_rounded,
                      () => set(() => tmp = tmp.copyWith(sortBy: 'product'))),
                  const SizedBox(width: 8),
                  _sortChip(AppLocalizations.sortWarehouse, 'warehouse', tmp.sortBy,
                      Icons.warehouse_rounded,
                      () => set(() => tmp = tmp.copyWith(sortBy: 'warehouse'))),
                ]),
                const SizedBox(height: 24),

                // Apply Button
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _filter = tmp);
                      _applyFilter();
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: Text(AppLocalizations.applyFilter,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16324F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterSectionLabel(String text, IconData icon) {
    return Row(children: [
      Icon(icon, size: 15, color: Colors.grey.shade500),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(
          fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey.shade600,
          letterSpacing: 0.5)),
    ]);
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF16324F) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0xFF16324F) : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(
            fontSize: 13,
            color: selected ? Colors.white : Colors.grey.shade700,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _condChip(String label, String value, String? selected, Color color,
      IconData icon, VoidCallback onTap) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.2)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : color),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white : color,
                fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  Widget _sortChip(String label, String value, String current, IconData icon,
      VoidCallback onTap) {
    final isSelected = current == value;
    return Expanded(
      child: GestureDetector(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF16324F).withValues(alpha: 0.08) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isSelected ? const Color(0xFF16324F) : Colors.transparent),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16,
                color: isSelected ? const Color(0xFF16324F) : Colors.grey),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
                fontSize: 11,
                color: isSelected ? const Color(0xFF16324F) : Colors.grey.shade600,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                textAlign: TextAlign.center),
          ]),
        ),
      ),
    );
  }

  // ============================================================
  // Delete — single mechanism: swipe OR button, never both
  // confirmDismiss shows dialog — only removes if confirmed
  // ============================================================
  Future<bool> _confirmDeleteSwipe(InventoryItem item) async {
    if (_deleteDialogOpen) return false;
    _deleteDialogOpen = true;
    try {
    final u = widget.currentUser ?? await AuthService.instance.getCurrentUser();
    if (u == null || !u.canDelete) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.noPermissionDelete)));
      return false;
    }
    if (!mounted) return false;
    final deleted = await showDeleteWithReasonDialog(context, item);
    if (deleted && mounted) {
      _loadItems();
      widget.onRefresh?.call();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${AppLocalizations.isArabic ? "تم حذف" : "Deleted"} "${item.productName}"'),
        backgroundColor: Colors.red.shade700,
        action: SnackBarAction(
          label: AppLocalizations.isArabic ? 'تراجع' : 'Undo',
          textColor: Colors.white,
          onPressed: () async {
            // Restore from Hive deleted list
            final deletedItems = InventoryRepository.instance.getDeletedItems();
            final match = deletedItems.where((d) =>
              (d['productName'] ?? d['product_name']) == item.productName).firstOrNull;
            if (match != null) {
              await InventoryRepository.instance.restoreItem(match);
              _loadItems();
              widget.onRefresh?.call();
            }
          },
        ),
      ));
    }
    return deleted;
    } finally {
      _deleteDialogOpen = false;
    }
  }

  Future<void> _moveItem(InventoryItem item) async {
    final warehouses = InventoryRepository.instance.getWarehouses();
    if (!mounted) return;
    final other = warehouses.where((w) => w != item.warehouseName).toList();
    if (other.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.noOtherWarehouses)));
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(AppLocalizations.moveTo),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${AppLocalizations.from} ${item.warehouseName}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 12),
            ...other.map((w) => ListTile(
                title: Text(w),
                leading: const Icon(Icons.warehouse_rounded, color: Color(0xFF16324F)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                onTap: () => Navigator.pop(ctx, w))),
          ]),
          actions: [TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.cancel))],
        ),
      ),
    );
    if (selected != null && item.id != null) {
      await InventoryRepository.instance.updateItem(item.copyWith(warehouseName: selected));
      _loadItems();
      widget.onRefresh?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${AppLocalizations.isArabic ? "تم النقل إلى:" : "Moved to:"} $selected ✅'),
          backgroundColor: Colors.green,
        ));
      }
    }
  }

  Color _condColor(String c) {
    switch (c) {
      case 'جديد': return const Color(0xFF2E7D32);
      case 'مستخدم': return const Color(0xFFE65100);
      case 'تالف': return const Color(0xFFC62828);
      default: return Colors.grey;
    }
  }

  String _localCond(String c) {
    if (AppLocalizations.isArabic) return c;
    switch (c) {
      case 'جديد': return 'New';
      case 'مستخدم': return 'Used';
      case 'تالف': return 'Damaged';
      default: return c;
    }
  }

  Widget _actionBtn({required IconData icon, required Color color, required VoidCallback onTap}) {
    return Material(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12), // fixed: was 7px → 12px (≥48px touch target)
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _metaLine(IconData icon, String text, {Color? iconColor}) {
    return Row(
      children: [
        Icon(icon, size: 12, color: iconColor ?? Colors.grey.shade400),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.currentUser?.isAdmin ?? true;
    final infoPills = <Widget>[];
    if (!isAdmin && widget.currentUser?.assignedWarehouse != null) {
      infoPills.add(_activePill(widget.currentUser!.assignedWarehouse!, const Color(0xFF16324F), null));
    }
    if (_filter.warehouse != null) {
      infoPills.add(_activePill(
        _filter.warehouse!,
        Colors.indigo,
        () {
          setState(() => _filter = _filter.copyWith(clearWarehouse: true));
          _applyFilter();
        },
      ));
    }
    if (_filter.condition != null) {
      infoPills.add(_activePill(
        _localCond(_filter.condition!),
        _condColor(_filter.condition!),
        () {
          setState(() => _filter = _filter.copyWith(clearCondition: true));
          _applyFilter();
        },
      ));
    }

    return Directionality(
      textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16324F).withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => _applyFilter(),
                          decoration: InputDecoration(
                            hintText: AppLocalizations.search,
                            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF16324F)),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      _applyFilter();
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF6F4EE),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: Color(0xFF16324F), width: 1.2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _showFilterSheet();
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: _filter.isActive ? const Color(0xFF16324F) : const Color(0xFFF6F4EE),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 18,
                                color: _filter.isActive ? Colors.white : const Color(0xFF16324F),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                AppLocalizations.filter,
                                style: TextStyle(
                                  color: _filter.isActive ? Colors.white : const Color(0xFF16324F),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '${_filtered.length} ${AppLocalizations.pieces}',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (_filter.sortBy != 'date')
                        Text(
                          '${AppLocalizations.sortBy}: ${_filter.sortBy == 'product' ? AppLocalizations.sortProduct : AppLocalizations.sortWarehouse}',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
                        ),
                    ],
                  ),
                  if (infoPills.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: infoPills,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? _buildSkeleton()
                : _filtered.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadItems,
                        color: const Color(0xFF16324F),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 2, 12, 110),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) => _buildItemCard(_filtered[i], isAdmin),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _activePill(String label, Color color, VoidCallback? onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: Icon(Icons.close_rounded, size: 14, color: color),
            ),
          ],
        ],
      ),
    );
  }

  // ── Skeleton Loading ──
  Widget _buildSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Container(width: 4, height: 80,
              decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)))),
          const SizedBox(width: 14),
          Expanded(child: Column(
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
          color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
    );
  }

  // ── Empty State ──
  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.isNotEmpty;
    final hasFilter = _filter.isActive;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 110),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 20),
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                // removed boxShadow — was making it look like a floating popup
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFF16324F).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      hasSearch ? Icons.search_off_rounded : Icons.inventory_2_outlined,
                      size: 34,
                      color: const Color(0xFF16324F),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    hasSearch
                        ? (AppLocalizations.isArabic ? 'لا نتائج مطابقة' : 'No matching results')
                        : hasFilter
                            ? (AppLocalizations.isArabic ? 'لا يوجد عناصر بهذا الفلتر' : 'No items match this filter')
                            : AppLocalizations.noItems,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasSearch || hasFilter
                        ? (AppLocalizations.isArabic ? 'جرّب إزالة الفلاتر أو تعديل كلمات البحث.' : 'Try clearing filters or adjusting your search.')
                        : (AppLocalizations.isArabic ? 'أضف أول قطعة أو اسحب القائمة للتحديث.' : 'Add your first item or pull to refresh.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                  ),
                  if (hasSearch || hasFilter) ...[
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _filter = const InventoryFilter());
                        _applyFilter();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF16324F),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.clear_all_rounded),
                      label: Text(AppLocalizations.isArabic ? 'مسح البحث والفلاتر' : 'Clear search and filters'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Item Card ──
  // Dismissible removed — caused app freeze when dialog shown inside confirmDismiss.
  // Delete is now triggered by long-press on the card (shows delete button row).
  Widget _buildItemCard(InventoryItem item, bool isAdmin) {
    final cc = _condColor(item.condition);
    final canEdit = widget.currentUser?.canEdit == true || isAdmin;
    final canDelete = widget.currentUser?.canDelete == true || isAdmin;

    return _SwipeToDeleteCard(
      key: ValueKey('item_${item.id ?? item.serial ?? item.productName}'),
      canDelete: canDelete,
      onDelete: () => _confirmDeleteSwipe(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: cc.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: canEdit
                ? () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AddItemScreen(itemToEdit: item)),
                    );
                    // Always reload when returning — item may have been edited
                    if (mounted) {
                      await _loadItems();
                      widget.onRefresh?.call();
                    }
                  }
                : () {
                    // Fix: show feedback for read-only cards instead of silent null
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(AppLocalizations.isArabic
                          ? 'ليس لديك صلاحية تعديل هذه القطعة'
                          : 'You don\'t have permission to edit this item'),
                      duration: const Duration(seconds: 2),
                    ));
                  },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [cc, cc.withValues(alpha: 0.50)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.productName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Fix: lock icon for read-only items
                                if (!canEdit)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4, top: 2),
                                    child: Icon(Icons.lock_outline_rounded,
                                        size: 13, color: Colors.grey.shade400),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: cc.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _localCond(item.condition),
                                    style: TextStyle(
                                        color: cc, fontWeight: FontWeight.w800, fontSize: 10.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _metaLine(Icons.warehouse_rounded, item.warehouseName),
                            if (item.serial != null && item.serial!.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              _metaLine(Icons.qr_code_2_rounded, item.serial!),
                            ],
                            if (item.expiryDate != null && item.expiryDate!.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              _metaLine(Icons.event_available_rounded,
                                  '${AppLocalizations.expiry} ${item.expiryDate}'),
                            ],
                            if (item.notes != null && item.notes!.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF16324F).withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  item.notes!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.calendar_today_rounded, size: 11, color: Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text(item.inventoryDate,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600)),
                      ]),
                      const Spacer(),
                      // Fix: delete button removed — swipe-only to avoid double action
                      // Move button stays for admins
                      if (isAdmin)
                        _actionBtn(
                          icon: Icons.drive_file_move_outline,
                          color: const Color(0xFF16324F),
                          onTap: () { HapticFeedback.selectionClick(); _moveItem(item); },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Custom swipe-to-reveal-delete widget ──────────────────────────────────────
// Replaces Dismissible — no confirmDismiss deadlock, no full-screen red bg.
class _SwipeToDeleteCard extends StatefulWidget {
  final Widget child;
  final bool canDelete;
  final VoidCallback onDelete;

  const _SwipeToDeleteCard({
    super.key,
    required this.child,
    required this.canDelete,
    required this.onDelete,
  });

  @override
  State<_SwipeToDeleteCard> createState() => _SwipeToDeleteCardState();
}

class _SwipeToDeleteCardState extends State<_SwipeToDeleteCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  bool _revealed = false;

  static const _revealWidth = 80.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _slide = Tween<Offset>(begin: Offset.zero, end: const Offset(-_revealWidth, 0))
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!widget.canDelete) return;
    setState(() => _revealed = !_revealed);
    _revealed ? _ctrl.forward() : _ctrl.reverse();
  }

  void _close() {
    if (_revealed) {
      setState(() => _revealed = false);
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canDelete) return widget.child;

    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        if (!widget.canDelete) return;
        // سحب يسار يكشف زرار الحذف
        if (d.delta.dx < -4 && !_revealed) _toggle();
        // سحب يمين يخفيه
        if (d.delta.dx > 4 && _revealed) _toggle();
      },
      onTap: _close,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Delete button behind the card
          Positioned(
            top: 0, bottom: 8, right: 0,
            width: _revealWidth,
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
              child: GestureDetector(
                onTap: () {
                  _close();
                  widget.onDelete();
                },
                child: Container(
                  color: Colors.red.shade700,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline_rounded, color: Colors.white, size: 24),
                      SizedBox(height: 3),
                      Text('حذف',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The card itself slides left
          AnimatedBuilder(
            animation: _slide,
            builder: (_, child) => Transform.translate(
              offset: _slide.value,
              child: child,
            ),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}