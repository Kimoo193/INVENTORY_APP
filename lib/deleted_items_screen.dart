import 'package:flutter/material.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'database.dart';

class DeletedItemsScreen extends StatefulWidget {
  const DeletedItemsScreen({super.key});

  @override
  State<DeletedItemsScreen> createState() => _DeletedItemsScreenState();
}

class _DeletedItemsScreenState extends State<DeletedItemsScreen> {
  List<Map<String, dynamic>> _deletedItems = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDeletedItems();
  }

  Future<void> _loadDeletedItems() async {
    setState(() => _loading = true);
    final db = await DatabaseHelper.instance.database;
    final results = await db.query('deleted_items', orderBy: 'deleted_at DESC');
    setState(() {
      _deletedItems = results;
      _loading = false;
    });
  }

  // ============================================================
  // استعادة - يرجع للمخزن بس يفضل في السجل
  // ============================================================
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

    final db = await DatabaseHelper.instance.database;

    // يرجع للمخزن
    await db.insert('inventory', {
      'warehouse_name': item['warehouse_name'],
      'product_name': item['product_name'],
      'serial': item['serial'],
      'condition': item['condition'],
      'expiry_date': item['expiry_date'],
      'notes': 'مستعاد - ${item['delete_reason'] ?? ''}',
      'inventory_date': item['inventory_date'] ?? InventoryItem.today(),
    });

    // يحدّث السجل بوقت الاستعادة بس مش بيحذفه
    await db.update(
      'deleted_items',
      {'delete_notes': '${item['delete_notes'] ?? ''} | مستعاد: ${DateTime.now().toString().substring(0, 16)}'},
      where: 'id = ?',
      whereArgs: [item['id']],
    );

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

  // ============================================================
  // حذف نهائي من السجل
  // ============================================================
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

    final db = await DatabaseHelper.instance.database;
    await db.delete('deleted_items', where: 'id = ?', whereArgs: [item['id']]);
    await _loadDeletedItems();
  }

  // ============================================================
  // تصدير Excel للمحذوفات
  // ============================================================
  Future<void> _exportToExcel() async {
    if (_deletedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد بيانات للتصدير')),
      );
      return;
    }

    try {
      final excel = Excel.createExcel();
      final sheet = excel['سجل الحذف'];
      excel.delete('Sheet1');

      // ستايل الهيدر
      CellStyle headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#1A237E'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: HorizontalAlign.Center,
      );

      // الهيدر
      final headers = [
        '#', 'المنتج', 'المخزن', 'السريال', 'الحالة',
        'تاريخ الصلاحية', 'سبب الحذف', 'ملاحظات', 'تاريخ الحذف',
      ];

      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }

      // البيانات
      for (int i = 0; i < _deletedItems.length; i++) {
        final item = _deletedItems[i];
        final row = i + 1;

        // لون الصف حسب السبب
        final reason = item['delete_reason']?.toString() ?? '';
        String rowColor = '#FFFFFF';
        if (reason.contains('مباع')) rowColor = '#E3F2FD';
        else if (reason.contains('تالف') || reason.contains('عاطل')) rowColor = '#FFEBEE';
        else if (reason.contains('مرتجع')) rowColor = '#FFF3E0';
        else if (reason.contains('نقل')) rowColor = '#F3E5F5';

        CellStyle rowStyle = CellStyle(
          backgroundColorHex: ExcelColor.fromHexString(rowColor),
          horizontalAlign: HorizontalAlign.Right,
        );

        void setCell(int col, String val) {
          final cell = sheet.cell(
              CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
          cell.value = TextCellValue(val);
          cell.cellStyle = rowStyle;
        }

        setCell(0, (i + 1).toString());
        setCell(1, item['product_name']?.toString() ?? '');
        setCell(2, item['warehouse_name']?.toString() ?? '');
        setCell(3, item['serial']?.toString() ?? '-');
        setCell(4, item['condition']?.toString() ?? '');
        setCell(5, item['expiry_date']?.toString() ?? '-');
        setCell(6, reason.isEmpty ? '-' : reason);
        setCell(7, item['delete_notes']?.toString() ?? '-');
        setCell(8, _formatDate(item['deleted_at']?.toString()));
      }

      // عرض الأعمدة
      sheet.setColumnWidth(0, 5);
      sheet.setColumnWidth(1, 35);
      sheet.setColumnWidth(2, 25);
      sheet.setColumnWidth(3, 22);
      sheet.setColumnWidth(4, 12);
      sheet.setColumnWidth(5, 15);
      sheet.setColumnWidth(6, 18);
      sheet.setColumnWidth(7, 25);
      sheet.setColumnWidth(8, 20);

      // حفظ الملف
      final now = DateTime.now();
      final fileName =
          'KaramStock_Deleted_${now.day}-${now.month}-${now.year}.xlsx';

      Directory? dir;
      try {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          dir = await getExternalStorageDirectory();
        }
      } catch (_) {
        dir = await getApplicationDocumentsDirectory();
      }

      final filePath = '${dir!.path}/$fileName';
      final fileBytes = excel.encode();
      if (fileBytes == null) throw Exception('فشل التصدير');

      final file = File(filePath);
      await file.writeAsBytes(fileBytes);

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'سجل المحذوفات - Karam Stock',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم التصدير: $fileName ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في التصدير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  Color _reasonColor(String? reason) {
    if (reason == null) return Colors.grey;
    if (reason.contains('مباع') || reason.contains('بيع')) return Colors.blue;
    if (reason.contains('تالف') || reason.contains('عاطل')) return Colors.red;
    if (reason.contains('مرتجع') || reason.contains('إرجاع')) return Colors.orange;
    if (reason.contains('نقل')) return Colors.purple;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('سجل الحذف (${_deletedItems.length})'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.table_chart),
              onPressed: _exportToExcel,
              tooltip: 'تصدير Excel',
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF1A237E)))
            : _deletedItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('لا يوجد عناصر محذوفة',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 16)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _deletedItems.length,
                    itemBuilder: (_, i) {
                      final item = _deletedItems[i];
                      final reason = item['delete_reason'] as String?;
                      final reasonColor = _reasonColor(reason);
                      final isRestored = item['delete_notes']
                              ?.toString()
                              .contains('مستعاد') ??
                          false;

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
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item['product_name'] ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                    ),
                                  ),
                                  if (isRestored)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text('مستعاد ✓',
                                          style: TextStyle(
                                              color: Colors.green,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                  if (reason != null && reason.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: reasonColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(reason,
                                          style: TextStyle(
                                              color: reasonColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item['serial'] ?? '-'} • ${item['warehouse_name'] ?? ''}',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                              ),
                              Text(
                                'حُذف: ${_formatDate(item['deleted_at'])}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.red.shade400),
                              ),
                              if (item['delete_notes'] != null &&
                                  item['delete_notes'].toString().isNotEmpty)
                                Text(
                                  'ملاحظة: ${item['delete_notes']}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange.shade700),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _restoreItem(item),
                                    icon: const Icon(Icons.restore,
                                        size: 18, color: Color(0xFF1A237E)),
                                    label: const Text('استعادة',
                                        style: TextStyle(
                                            color: Color(0xFF1A237E))),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _permanentDelete(item),
                                    icon: Icon(Icons.delete_forever,
                                        size: 18, color: Colors.red.shade400),
                                    label: Text('حذف نهائي',
                                        style: TextStyle(
                                            color: Colors.red.shade400)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}