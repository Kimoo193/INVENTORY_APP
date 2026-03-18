import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'auth_service.dart';
import 'inventory_repository.dart';
import 'app_localizations.dart';

class DeletedItemsScreen extends StatefulWidget {
  const DeletedItemsScreen({super.key});
  @override
  State<DeletedItemsScreen> createState() => _DeletedItemsScreenState();
}

class _DeletedItemsScreenState extends State<DeletedItemsScreen> {
  List<Map<String, dynamic>> _deletedItems = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  AppUser? _currentUser;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  static const Color _primary = Color(0xFF16324F);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _currentUser = await AuthService.instance.getCurrentUser();
    await _loadDeletedItems();
  }

  Future<void> _loadDeletedItems() async {
    setState(() => _loading = true);
    // Read from Hive — sync, no await needed
    final results = InventoryRepository.instance.getDeletedItems();
    if (!mounted) return;
    setState(() {
      _deletedItems = results;
      _filtered     = results;
      _loading      = false;
    });
  }

  void _onSearch(String q) {
    setState(() {
      _searchQuery = q;
      if (q.isEmpty) {
        _filtered = _deletedItems;
      } else {
        final lower = q.toLowerCase();
        _filtered = _deletedItems.where((item) {
          final product   = (item['product_name'] ?? '').toString().toLowerCase();
          final warehouse = (item['warehouse_name'] ?? '').toString().toLowerCase();
          final serial    = (item['serial'] ?? '').toString().toLowerCase();
          final reason    = (item['delete_reason'] ?? '').toString().toLowerCase();
          return product.contains(lower) || warehouse.contains(lower) ||
                 serial.contains(lower)  || reason.contains(lower);
        }).toList();
      }
    });
  }

  // ──────────────────── Actions ─────────────────────────────
  Future<void> _restoreItem(Map<String, dynamic> item) async {
    final confirm = await _showConfirmDialog(
      title: AppLocalizations.restore,
      message: AppLocalizations.isArabic
          ? 'هتستعيد "${item['product_name']}" للمخزن؟\n\nهيفضل في سجل الحذف كمرجع.'
          : 'Restore "${item['product_name']}" to inventory?\n\nIt will remain in the log for reference.',
      confirmLabel: AppLocalizations.restore,
      confirmColor: _primary,
      icon: Icons.restore_rounded,
    );
    if (confirm != true) return;

    await InventoryRepository.instance.restoreItem(item);
    await _loadDeletedItems();

    if (mounted) {
      _showSnack(AppLocalizations.restoredSuccess, Colors.green);
    }
  }

  Future<void> _permanentDelete(Map<String, dynamic> item) async {
    final confirm = await _showConfirmDialog(
      title: AppLocalizations.permanentDelete,
      message: AppLocalizations.isArabic
          ? 'هتحذف "${item['product_name']}" نهائياً من سجل الحذف؟\n\n⚠️ لن تتمكن من استعادته!'
          : 'Permanently delete "${item['product_name']}" from the log?\n\n⚠️ This cannot be undone!',
      confirmLabel: AppLocalizations.permanentDelete,
      confirmColor: Colors.red.shade700,
      icon: Icons.delete_forever_rounded,
      isDangerous: true,
    );
    if (confirm != true) return;

    // FIX: use InventoryRepository which:
    //  1. Resolves ID from '_id' OR 'id' key (Hive uses '_id')
    //  2. Removes from Hive first → UI updates instantly
    //  3. Then calls Firestore (graceful if offline)
    await InventoryRepository.instance.permanentDeleteItem(item);
    await _loadDeletedItems();
  }

  Future<void> _exportToExcel() async {
    if (_deletedItems.isEmpty) {
      _showSnack(AppLocalizations.noDataExport, Colors.orange);
      return;
    }
    try {
      final excel = Excel.createExcel();
      final sheet = excel[AppLocalizations.isArabic ? 'سجل الحذف' : 'Delete Log'];
      excel.delete('Sheet1');

      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#16324F'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );
      final headers = AppLocalizations.isArabic
          ? ['#', 'المنتج', 'المخزن', 'السريال', 'الحالة', 'سبب الحذف', 'ملاحظات', 'تاريخ الحذف']
          : ['#', 'Product', 'Warehouse', 'Serial', 'Condition', 'Delete Reason', 'Notes', 'Deleted At'];

      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      for (int i = 0; i < _deletedItems.length; i++) {
        final item   = _deletedItems[i];
        final reason = item['delete_reason']?.toString() ?? '';
        String rowColor = '#FFFFFF';
        if (reason.contains('مباع') || reason.contains('Sold')) {
          rowColor = '#E3F2FD';
        } else if (reason.contains('تالف') || reason.contains('Damage')) {
          rowColor = '#FFEBEE';
        } else if (reason.contains('مرتجع') || reason.contains('Return')) {
          rowColor = '#FFF3E0';
        }

        final rowStyle = CellStyle(
          backgroundColorHex: ExcelColor.fromHexString(rowColor),
          horizontalAlign: HorizontalAlign.Right,
        );

        void setCell(int col, String val) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: i + 1));
          cell.value = TextCellValue(val);
          cell.cellStyle = rowStyle;
        }

        setCell(0, (i + 1).toString());
        setCell(1, item['product_name']?.toString() ?? '');
        setCell(2, item['warehouse_name']?.toString() ?? '');
        setCell(3, item['serial']?.toString() ?? '-');
        setCell(4, item['condition']?.toString() ?? '');
        setCell(5, reason.isEmpty ? '-' : reason);
        setCell(6, item['delete_notes']?.toString() ?? '-');
        setCell(7, _formatDate(item['deleted_at']?.toString()));
      }

      sheet.setColumnWidth(0, 5);  sheet.setColumnWidth(1, 35);
      sheet.setColumnWidth(2, 25); sheet.setColumnWidth(3, 18);
      sheet.setColumnWidth(4, 12); sheet.setColumnWidth(5, 18);
      sheet.setColumnWidth(6, 25); sheet.setColumnWidth(7, 22);

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/KaramStock_DeleteLog.xlsx');
      await file.writeAsBytes(excel.encode()!);
      await Share.shareXFiles([XFile(file.path)],
          text: '${AppLocalizations.deleteLog2} — Karam Stock');
    } catch (e) {
      if (mounted) _showSnack('${AppLocalizations.error}: $e', Colors.red);
    }
  }

  // ──────────────────── Helpers ─────────────────────────────
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

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required IconData icon,
    bool isDangerous = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isDangerous ? Colors.red : _primary).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: isDangerous ? Colors.red.shade600 : _primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          ]),
          content: Text(message,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.cancel,
                  style: TextStyle(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(confirmLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  Color _reasonColor(String? reason) {
    if (reason == null) return Colors.grey;
    if (reason.contains('مباع') || reason.contains('Sold'))     return Colors.blue.shade600;
    if (reason.contains('تالف') || reason.contains('Damage'))   return Colors.red.shade600;
    if (reason.contains('مرتجع') || reason.contains('Return'))  return Colors.orange.shade600;
    if (reason.contains('نقل') || reason.contains('Transfer'))  return Colors.purple.shade500;
    if (reason.contains('مفقود') || reason.contains('Lost'))    return Colors.brown.shade400;
    if (reason.contains('مسح المخزون'))                         return Colors.indigo.shade500;
    return Colors.grey.shade600;
  }

  IconData _reasonIcon(String? reason) {
    if (reason == null) return Icons.help_outline_rounded;
    if (reason.contains('مباع') || reason.contains('Sold'))     return Icons.shopping_bag_rounded;
    if (reason.contains('تالف') || reason.contains('Damage'))   return Icons.broken_image_rounded;
    if (reason.contains('مرتجع') || reason.contains('Return'))  return Icons.undo_rounded;
    if (reason.contains('نقل') || reason.contains('Transfer'))  return Icons.local_shipping_rounded;
    if (reason.contains('مفقود') || reason.contains('Lost'))    return Icons.location_off_rounded;
    if (reason.contains('مسح المخزون'))                         return Icons.delete_sweep_rounded;
    return Icons.info_outline_rounded;
  }

  // ──────────────────── Item Card ───────────────────────────
  Widget _buildItemCard(Map<String, dynamic> item, bool isAdmin) {
    final reason     = item['delete_reason'] as String?;
    final reasonColor = _reasonColor(reason);
    final isRestored = item['delete_notes']?.toString().contains('مستعاد') ?? false;
    final canRestore = !isRestored && (isAdmin || (_currentUser?.canRestore == true));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header row ──────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            decoration: BoxDecoration(
              color: reasonColor.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                bottom: BorderSide(color: reasonColor.withValues(alpha: 0.12)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: reasonColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(_reasonIcon(reason), size: 16, color: reasonColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item['product_name'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFF1A1A2E)),
                  ),
                ),
                if (isRestored)
                  _pill(AppLocalizations.restored, Colors.green.shade600),
                if (reason != null && reason.isNotEmpty)
                  _pill(reason, reasonColor),
              ],
            ),
          ),
          // ── Body ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              children: [
                _metaRow(Icons.warehouse_outlined,
                    item['warehouse_name'] ?? '',
                    item['serial']?.toString() ?? '-'),
                const SizedBox(height: 6),
                _metaRow(Icons.access_time_rounded,
                    _formatDate(item['deleted_at']?.toString()),
                    item['condition']?.toString() ?? ''),
                if (item['delete_notes'] != null &&
                    item['delete_notes'].toString().isNotEmpty &&
                    !isRestored) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.notes_rounded,
                          size: 14, color: Colors.orange.shade600),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item['delete_notes'].toString(),
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade700,
                              height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ],
                // ── Actions ─────────────────────────────
                if (canRestore || isAdmin) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, thickness: 0.5),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (canRestore)
                        _outlineBtn(
                          label: AppLocalizations.restore,
                          icon: Icons.restore_rounded,
                          color: _primary,
                          onTap: () => _restoreItem(item),
                        ),
                      if (canRestore && isAdmin) const SizedBox(width: 8),
                      // Fix: filled red with ⚠️ icon — clearly more destructive than restore
                      if (isAdmin)
                        Material(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () { HapticFeedback.heavyImpact(); _permanentDelete(item); },
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.delete_forever_rounded, size: 15, color: Colors.white),
                                const SizedBox(width: 5),
                                Text(AppLocalizations.permanentDelete,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Text(label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  Widget _metaRow(IconData icon, String left, String right) => Row(
    children: [
      Icon(icon, size: 13, color: Colors.grey.shade500),
      const SizedBox(width: 5),
      Expanded(
        child: Text(left,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ),
      Text(right,
          style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600)),
    ],
  );

  Widget _outlineBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () { HapticFeedback.selectionClick(); onTap(); },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────── Build ───────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isAdmin = _currentUser?.isAdmin ?? false;

    return Directionality(
      textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.deleteLog2,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              Text(
                '${_deletedItems.length} ${AppLocalizations.pieces}',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
          actions: [
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.table_chart_rounded),
                onPressed: _exportToExcel,
                tooltip: AppLocalizations.exportLabel,
              ),
          ],
        ),
        body: Column(
          children: [
            // ── Search Bar ──────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearch,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: AppLocalizations.searchHint,
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Colors.grey.shade400, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: Colors.grey.shade400, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearch('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _primary, width: 1.5),
                  ),
                ),
              ),
            ),
            // ── List ────────────────────────────────────
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                              color: _primary, strokeWidth: 2.5),
                          const SizedBox(height: 12),
                          Text(AppLocalizations.loading,
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 14)),
                        ],
                      ),
                    )
                  : _filtered.isEmpty
                      ? Center(
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
                                child: Icon(Icons.delete_outline_rounded,
                                    size: 36,
                                    color: _primary.withValues(alpha: 0.3)),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? AppLocalizations.noResults
                                    : AppLocalizations.noDeletedItems,
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600),
                              ),
                              if (_searchQuery.isEmpty && !isAdmin) ...[
                                const SizedBox(height: 6),
                                Text(AppLocalizations.deleteLogHint,
                                    style: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 13),
                                    textAlign: TextAlign.center),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) =>
                              _buildItemCard(_filtered[i], isAdmin),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}