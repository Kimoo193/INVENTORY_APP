import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:io';
import 'database.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _loading = false;
  String _status = '';
  List<Map<String, String>> _previewItems = [];
  bool _showPreview = false;
  String? _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = InventoryItem.today();
  }

  Future<void> _importFromExcel() async {
    setState(() { _loading = true; _status = 'جاري اختيار الملف...'; });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result == null) {
        setState(() { _loading = false; _status = ''; });
        return;
      }

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      final items = <Map<String, String>>[];

      for (final sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName]!;
        for (int i = 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;

          String getCellValue(int index) {
            if (index >= row.length) return '';
            final cell = row[index];
            if (cell == null) return '';
            return cell.value?.toString().trim() ?? '';
          }

          final product = getCellValue(1);
          final warehouse = getCellValue(2);
          final serial = getCellValue(3);
          final condition = getCellValue(4);
          final expiry = getCellValue(5);
          final notes = getCellValue(6);

          if (product.isEmpty) continue;

          items.add({
            'product': product,
            'warehouse': warehouse.isEmpty ? 'WH32/مخزن محمد مرسي' : warehouse,
            'serial': serial,
            'condition': ['جديد', 'مستخدم', 'تالف'].contains(condition) ? condition : 'جديد',
            'expiry': expiry,
            'notes': notes,
          });
        }
      }

      setState(() {
        _loading = false;
        _previewItems = items;
        _showPreview = true;
        _status = 'تم قراءة ${items.length} عنصر من Excel';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = 'خطأ: $e';
      });
    }
  }

  Future<void> _importFromPdf() async {
    setState(() { _loading = true; _status = 'جاري اختيار الملف...'; });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null) {
        setState(() { _loading = false; _status = ''; });
        return;
      }

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);

      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText();
      document.dispose();

      final items = _parsePdfText(text);

      setState(() {
        _loading = false;
        _previewItems = items;
        _showPreview = true;
        _status = 'تم قراءة ${items.length} عنصر من PDF';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = 'خطأ في قراءة PDF: $e';
      });
    }
  }

  List<Map<String, String>> _parsePdfText(String text) {
    final items = <Map<String, String>>[];
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    // قراءة الـ PDF بتاعك - كل سطر فيه: منتج + مخزن + serial + ملاحظات + كمية
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // تجاهل الهيدر والسطور الفارغة
      if (line.contains('الموقع') || line.contains('المنتج') ||
          line.contains('ملاحظات') || line.contains('الكمية')) continue;

      // ابحث عن السيريال (أرقام أو حروف وأرقام)
      final serialPattern = RegExp(r'\b([A-Za-z0-9]{5,25})\b');
      final serialMatches = serialPattern.allMatches(line);

      // ابحث عن اسم المنتج (نص عربي أو إنجليزي)
      String product = '';
      String serial = '';
      String notes = '';
      String warehouse = 'WH32/مخزن محمد مرسي';

      // استخرج المخزن
      if (line.contains('مخزن')) {
        final whMatch = RegExp(r'(WH\d+/[^\d]+)').firstMatch(line);
        if (whMatch != null) warehouse = whMatch.group(1)?.trim() ?? warehouse;
      }

      // استخرج السيريال
      if (serialMatches.isNotEmpty) {
        serial = serialMatches.first.group(1) ?? '';
      }

      // استخرج الملاحظات الشائعة
      if (line.contains('مستخدم')) notes = 'مستخدم';
      else if (line.contains('مباع') || line.contains('باع')) notes = 'مباع';
      else if (line.contains('عاطل')) notes = 'عاطل';

      // حدد المنتج من السطر السابق لو مش في نفس السطر
      if (i > 0) {
        final prevLine = lines[i - 1];
        if (prevLine.contains('/') && !prevLine.contains('مخزن')) {
          product = prevLine.split('/').first.trim();
        }
      }

      // لو في السطر نفسه منتج وسيريال
      final productMatch = RegExp(r'^([A-Za-z\s\-]+(?:/[^\d]+)?)\s').firstMatch(line);
      if (productMatch != null && product.isEmpty) {
        product = productMatch.group(1)?.trim() ?? '';
      }

      if (product.isEmpty && serial.isEmpty) continue;
      if (serial.isEmpty) continue;

      items.add({
        'product': product.isEmpty ? 'غير محدد' : product,
        'warehouse': warehouse,
        'serial': serial,
        'condition': notes.contains('عاطل') ? 'تالف' :
                     notes.contains('مستخدم') ? 'مستخدم' : 'جديد',
        'expiry': '',
        'notes': notes,
      });
    }

    return items;
  }

  Future<void> _saveAllItems() async {
    setState(() { _loading = true; _status = 'جاري الحفظ...'; });

    int saved = 0;
    for (final item in _previewItems) {
      try {
        await DatabaseHelper.instance.insertItem(InventoryItem(
          warehouseName: item['warehouse'] ?? 'WH32/مخزن محمد مرسي',
          productName: item['product'] ?? 'غير محدد',
          serial: item['serial']?.isEmpty == true ? null : item['serial'],
          condition: item['condition'] ?? 'جديد',
          expiryDate: item['expiry']?.isEmpty == true ? null : item['expiry'],
          notes: item['notes']?.isEmpty == true ? null : item['notes'],
          inventoryDate: _selectedDate,
        ));
        saved++;
      } catch (_) {}
    }

    setState(() {
      _loading = false;
      _showPreview = false;
      _previewItems = [];
      _status = 'تم حفظ $saved عنصر بنجاح ✅';
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date != null) {
      setState(() {
        _selectedDate =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      });
    }
  }

  String _formatDate(String date) {
    final parts = date.split('-');
    if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    return date;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('استيراد بيانات'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        body: _loading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF1A237E)),
                    const SizedBox(height: 16),
                    Text(_status, style: const TextStyle(fontSize: 16)),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // تاريخ الجرد
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.calendar_today,
                            color: Color(0xFF1A237E)),
                        title: const Text('تاريخ الجرد'),
                        subtitle: Text(_formatDate(_selectedDate!)),
                        trailing: const Icon(Icons.edit,
                            color: Color(0xFF1A237E), size: 18),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // استيراد من Excel
                    ElevatedButton.icon(
                      onPressed: _importFromExcel,
                      icon: const Icon(Icons.table_chart),
                      label: const Text('استيراد من Excel',
                          style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // استيراد من PDF
                    ElevatedButton.icon(
                      onPressed: _importFromPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('استيراد من PDF',
                          style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),

                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _status.contains('✅')
                              ? Colors.green.shade50
                              : _status.contains('خطأ')
                                  ? Colors.red.shade50
                                  : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _status.contains('✅')
                                ? Colors.green
                                : _status.contains('خطأ')
                                    ? Colors.red
                                    : Colors.blue,
                          ),
                        ),
                        child: Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: _status.contains('✅')
                                ? Colors.green.shade700
                                : _status.contains('خطأ')
                                    ? Colors.red.shade700
                                    : Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],

                    // Preview
                    if (_showPreview && _previewItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(
                            'معاينة (${_previewItems.length} عنصر)',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _showPreview = false;
                              _previewItems = [];
                              _status = '';
                            }),
                            icon: const Icon(Icons.clear, size: 18),
                            label: const Text('إلغاء'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _previewItems.length > 50
                            ? 50
                            : _previewItems.length,
                        itemBuilder: (_, i) {
                          final item = _previewItems[i];
                          final condColor = item['condition'] == 'جديد'
                              ? Colors.green
                              : item['condition'] == 'مستخدم'
                                  ? Colors.orange
                                  : Colors.red;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 6),
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: condColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(item['product'] ?? '',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13)),
                                        Text(
                                            '${item['serial']} • ${item['warehouse']}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600)),
                                        if (item['notes']?.isNotEmpty == true)
                                          Text(item['notes']!,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.orange.shade700)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: condColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item['condition'] ?? 'جديد',
                                      style: TextStyle(
                                          color: condColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      if (_previewItems.length > 50)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '... و ${_previewItems.length - 50} عنصر إضافي',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _saveAllItems,
                        icon: const Icon(Icons.save),
                        label: Text(
                            'حفظ كل العناصر (${_previewItems.length})',
                            style: const TextStyle(fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}