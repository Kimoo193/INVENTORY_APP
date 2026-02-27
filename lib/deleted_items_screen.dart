import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'firestore_service.dart';
import 'auth_service.dart';

class DeletedItemsScreen extends StatefulWidget {
  const DeletedItemsScreen({super.key});

  @override
  State<DeletedItemsScreen> createState() => _DeletedItemsScreenState();
}

class _DeletedItemsScreenState extends State<DeletedItemsScreen> {
  List<Map<String, dynamic>> _deletedItems = [];
  bool _loading = true;
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _currentUser = await AuthService.instance.getCurrentUser();
    await _loadDeletedItems();
  }

  Future<void> _loadDeletedItems() async {
    setState(() => _loading = true);
    List<Map<String, dynamic>> results;

    if (_currentUser != null && !_currentUser!.isAdmin) {
      // ✅ User: يشوف بس اللي هو حذفه
      results = await FirestoreService.instance
          .getDeletedItemsByUser(_currentUser!.uid);
    } else {
      // Admin: يشوف كل السجل
      results = await FirestoreService.instance.getDeletedItems();
    }

    setState(() {
      _deletedItems = results;
      _loading = false;
    });
  }

  Future<void> _restoreItem(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('استعادة العنصر'),
          content: Text(
              'هتستعيد "${item['product_name']}" للمخزن؟\n\nهيفضل في سجل الحذف كمرجع.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white),
              child: const Text('استعادة'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    await FirestoreService.instance.restoreItem(item);
    await _loadDeletedItems();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم الاستعادة للمخزن ✅ (السجل محفوظ)'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ✅ حذف نهائي للـ Admin فقط
  Future<void> _permanentDelete(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف نهائي من السجل'),
          content: Text(
              'هتحذف "${item['product_name']}" من سجل الحذف نهائياً؟\nمش هتقدر ترجعه!'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('حذف نهائي'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    await FirestoreService.instance.permanentDeleteItem(item['id']);
    await _loadDeletedItems();
  }

  Future<void> _exportToExcel() async {
    if (_deletedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد بيانات للتصدير')));
      return;
    }
    try {
      final excel = Excel.createExcel();
      final sheet = excel['سجل الحذف'];
      excel.delete('Sheet1');

      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1A237E'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );
      final headers = ['#','المنتج','المخزن','السريال','الحالة',
        'سبب الحذف','ملاحظات','تاريخ الحذف'];
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }
      for (int i = 0; i < _deletedItems.length; i++) {
        final item = _deletedItems[i];
        final reason = item['delete_reason']?.toString() ?? '';
        String rowColor = '#FFFFFF';
        if (reason.contains('مباع')) rowColor = '#E3F2FD';
        else if (reason.contains('تالف')) rowColor = '#FFEBEE';
        else if (reason.contains('مرتجع')) rowColor = '#FFF3E0';
        final rowStyle = CellStyle(
          backgroundColorHex: ExcelColor.fromHexString(rowColor),
          horizontalAlign: HorizontalAlign.Right,
        );
        void setCell(int col, String val) {
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: i+1));
          cell.value = TextCellValue(val);
          cell.cellStyle = rowStyle;
        }
        setCell(0, (i+1).toString());
        setCell(1, item['product_name']?.toString() ?? '');
        setCell(2, item['warehouse_name']?.toString() ?? '');
        setCell(3, item['serial']?.toString() ?? '-');
        setCell(4, item['condition']?.toString() ?? '');
        setCell(5, reason.isEmpty ? '-' : reason);
        setCell(6, item['delete_notes']?.toString() ?? '-');
        setCell(7, _formatDate(item['deleted_at']?.toString()));
      }
      sheet.setColumnWidth(0, 5); sheet.setColumnWidth(1, 35);
      sheet.setColumnWidth(2, 25); sheet.setColumnWidth(3, 18);
      sheet.setColumnWidth(4, 12); sheet.setColumnWidth(5, 18);
      sheet.setColumnWidth(6, 25); sheet.setColumnWidth(7, 22);

      final dir = await getTemporaryDirectory();
      final fileName = 'KaramStock_Deleted.xlsx';
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(excel.encode()!);
      await Share.shareXFiles([XFile(file.path)], text: 'سجل المحذوفات - Karam Stock');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) { return dateStr; }
  }

  Color _reasonColor(String? reason) {
    if (reason == null) return Colors.grey;
    if (reason.contains('مباع')) return Colors.blue;
    if (reason.contains('تالف') || reason.contains('عاطل')) return Colors.red;
    if (reason.contains('مرتجع')) return Colors.orange;
    if (reason.contains('نقل')) return Colors.purple;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _currentUser?.isAdmin ?? false;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('سجل الحذف (${_deletedItems.length})'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          actions: [
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.table_chart),
                onPressed: _exportToExcel,
                tooltip: 'تصدير Excel',
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
            : _deletedItems.isEmpty
                ? Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('لا يوجد عناصر محذوفة',
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                      if (!isAdmin) ...[
                        const SizedBox(height: 8),
                        Text('ستظهر هنا القطع اللي قمت بحذفها',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                      ]
                    ]))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _deletedItems.length,
                    itemBuilder: (_, i) {
                      final item = _deletedItems[i];
                      final reason = item['delete_reason'] as String?;
                      final reasonColor = _reasonColor(reason);
                      final isRestored =
                          item['delete_notes']?.toString().contains('مستعاد') ?? false;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text(item['product_name'] ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 14)),
                                ),
                                if (isRestored)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: const Text('مستعاد ✓',
                                        style: TextStyle(color: Colors.green,
                                            fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                if (reason != null && reason.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: reasonColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text(reason,
                                        style: TextStyle(color: reasonColor,
                                            fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                              ]),
                              const SizedBox(height: 4),
                              Text('${item['serial'] ?? '-'} • ${item['warehouse_name'] ?? ''}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Text('حُذف: ${_formatDate(item['deleted_at'])}',
                                  style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
                              if (item['delete_notes'] != null &&
                                  item['delete_notes'].toString().isNotEmpty)
                                Text('ملاحظة: ${item['delete_notes']}',
                                    style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  // ✅ استعادة: للجميع (user + admin)
                                  if (!isRestored)
                                    TextButton.icon(
                                      onPressed: () => _restoreItem(item),
                                      icon: const Icon(Icons.restore, size: 18, color: Color(0xFF1A237E)),
                                      label: const Text('استعادة',
                                          style: TextStyle(color: Color(0xFF1A237E))),
                                    ),
                                  // ✅ حذف نهائي: Admin فقط
                                  if (isAdmin)
                                    TextButton.icon(
                                      onPressed: () => _permanentDelete(item),
                                      icon: Icon(Icons.delete_forever, size: 18, color: Colors.red.shade400),
                                      label: Text('حذف نهائي',
                                          style: TextStyle(color: Colors.red.shade400)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
      ),
    );
  }
}