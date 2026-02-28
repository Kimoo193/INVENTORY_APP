import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:io';
import 'firestore_service.dart';
import 'auth_service.dart';

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
  AppUser? _currentUser; // ✅ لتتبع addedByUid عند الاستيراد

  @override
  void initState() {
    super.initState();
    _selectedDate = InventoryItem.today();
    _loadUser();
  }

  Future<void> _loadUser() async {
    _currentUser = await AuthService.instance.getCurrentUser();
  }

  // ============================================================
  // استيراد Excel - يتعرف على 6 أشكال مختلفة
  // ============================================================
  Future<void> _importFromExcel() async {
    final currentUser = await AuthService.instance.getCurrentUser();
    if (currentUser == null || !currentUser.canImport) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية الاستيراد')),
      );
      return;
    }
    
    setState(() {
      _loading = true;
      _status = 'جاري اختيار الملف...';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result == null) {
        setState(() {
          _loading = false;
          _status = '';
        });
        return;
      }

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final items = <Map<String, String>>[];

      for (final sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName]!;
        if (sheet.rows.isEmpty) continue;

        // استخرج الهيدر
        final headerRow = sheet.rows[0];
        final headers = headerRow
            .map((c) => (c?.value?.toString() ?? '').trim())
            .toList();

        final sheetItems = _detectAndParseExcelSheet(sheet, headers);
        items.addAll(sheetItems);
      }

      setState(() {
        _loading = false;
        _previewItems = items;
        _showPreview = items.isNotEmpty;
        _status = items.isEmpty
            ? 'مش قادر يقرأ الملف - تأكد من الشكل'
            : 'تم قراءة ${items.length} عنصر من Excel';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = 'خطأ: $e';
      });
    }
  }

  List<Map<String, String>> _detectAndParseExcelSheet(
      Sheet sheet, List<String> headers) {
    final items = <Map<String, String>>[];

    String h(int i) => i < headers.length ? headers[i].toLowerCase() : '';
    String getCellStr(List<Data?> row, int i) {
      if (i >= row.length || row[i] == null) return '';
      return row[i]!.value?.toString().trim() ?? '';
    }

    // ============================================================
    // شكل 1: Product/Display Name | Cost | Qty | Location | Serial
    // مثال: شيت_المخازن_محمد_مرسي.xlsx
    // ============================================================
    if (headers.any((h) => h.contains('Product/Display Name') ||
        h.contains('product/display'))) {
      int productCol = headers.indexWhere((h) =>
          h.toLowerCase().contains('product'));
      int locationCol = headers.indexWhere((h) =>
          h.toLowerCase().contains('location'));
      int serialCol = headers.indexWhere((h) =>
          h.toLowerCase().contains('serial'));

      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final product = getCellStr(row, productCol == -1 ? 0 : productCol);
        final location = getCellStr(row, locationCol == -1 ? 3 : locationCol);
        String serial = getCellStr(row, serialCol == -1 ? 4 : serialCol);
        if (product.isEmpty) continue;
        // نظّف السيريال من prefix زي "206B:"
        serial = serial.replaceAll(RegExp(r'^[A-Z0-9]+:'), '');
        items.add({
          'product': _cleanName(product),
          'warehouse': location.isEmpty ? 'Stock 1' : location,
          'serial': serial,
          'condition': 'جديد',
          'expiry': '',
          'notes': '',
        });
      }
      return items;
    }

    // ============================================================
    // شكل 2: Product | Lot/Serial Number | Inventoried Quantity
    // مثال: جرد_على_رضا.xlsx
    // ============================================================
    if (headers.any((h) =>
        h.contains('Lot/Serial') || h.contains('lot/serial'))) {
      int productCol = 0;
      int serialCol = headers.indexWhere((h) =>
          h.toLowerCase().contains('lot') || h.toLowerCase().contains('serial'));

      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final product = getCellStr(row, productCol);
        final serial = getCellStr(row, serialCol == -1 ? 1 : serialCol);
        if (product.isEmpty && serial.isEmpty) continue;
        if (product.isEmpty) continue;
        items.add({
          'product': _cleanName(product),
          'warehouse': 'Stock 1',
          'serial': serial,
          'condition': 'جديد',
          'expiry': '',
          'notes': '',
        });
      }
      return items;
    }

    // ============================================================
    // شكل 3: المنتج | الموقع | السريال | حالة الجهاز | تاريخ صلاحية
    // يشمل: جرد_5-11، 1محمد_مرسي، والشكل المُصدَّر من التطبيق
    // مثال التطبيق: # | المنتج | المخزن | السريال | الحالة | تاريخ الصلاحية | ملاحظات
    // ============================================================
    if (headers.any((h) =>
        h.contains('المنتج') || h.contains('منتج'))) {
      int productCol = headers.indexWhere((h) =>
          h.contains('المنتج') || h.contains('منتج'));
      int locationCol = headers.indexWhere((h) =>
          h.contains('المخزن') || h.contains('الموقع') || h.contains('موقع'));
      int serialCol = headers.indexWhere((h) =>
          h.contains('السريال') || h.contains('سريال') || h.contains('السريل'));
      int conditionCol = headers.indexWhere((h) =>
          h.contains('الحالة') || h.contains('حالة'));
      int expiryCol = headers.indexWhere((h) =>
          h.contains('تاريخ') || h.contains('صلاحية'));
      int notesCol = headers.indexWhere((h) =>
          h.contains('ملاحظات') || h.contains('ملحظات'));

      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final product =
            getCellStr(row, productCol == -1 ? 0 : productCol);
        if (product.isEmpty) continue;
        // تجاهل سطور الحذف (بتبدأ بـ [محذوف])
        if (product.startsWith('[محذوف]')) continue;

        final location =
            getCellStr(row, locationCol == -1 ? 1 : locationCol);
        String serial =
            getCellStr(row, serialCol == -1 ? 2 : serialCol);
        final condRaw =
            getCellStr(row, conditionCol == -1 ? 3 : conditionCol);
        String expiry =
            getCellStr(row, expiryCol == -1 ? 4 : expiryCol);
        final notesRaw =
            getCellStr(row, notesCol == -1 ? 5 : notesCol);

        // تجاهل القيم الفارغة الوهمية
        if (expiry == '-') expiry = '';
        final notes = notesRaw == '-' ? '' : notesRaw;

        // نظّف السيريال
        serial = serial.replaceAll(RegExp(r'^[A-Z0-9]+:'), '');

        String condition = 'جديد';
        if (condRaw.contains('مستخدم')) condition = 'مستخدم';
        else if (condRaw.contains('تالف') || condRaw.contains('عاطل')) {
          condition = 'تالف';
        }

        items.add({
          'product': _cleanName(product),
          'warehouse': location.isEmpty ? 'WH32/Stock 1' : location,
          'serial': serial,
          'condition': condition,
          'expiry': expiry,
          'notes': notes,
        });
      }
      return items;
    }

    // ============================================================
    // شكل 4: أعمدة كل عمود منتج مختلف مع سيريالات
    // مثال: جرد_أ_محمدمرسي_2-9.xlsx, DVR_2-9_.xlsx
    // ============================================================
    if (headers.isNotEmpty &&
        !headers.any((h) => h.contains('المنتج')) &&
        headers.length >= 3) {
      // كل عمود هو منتج، والبيانات هي السيريالات
      for (int col = 0; col < headers.length; col++) {
        final productHeader = headers[col];
        if (productHeader.isEmpty) continue;

        // استخرج اسم المنتج والحالة من الهيدر
        String condition = 'جديد';
        if (productHeader.contains('مستخدم')) condition = 'مستخدم';
        else if (productHeader.contains('تالف') || productHeader.contains('عاطل')) {
          condition = 'تالف';
        }

        for (int row = 1; row < sheet.rows.length; row++) {
          final serial = getCellStr(sheet.rows[row], col);
          if (serial.isEmpty) continue;
          if (!RegExp(r'\d{5,}').hasMatch(serial)) continue;

          items.add({
            'product': _headerToProductName(productHeader),
            'warehouse': 'Stock 1',
            'serial': serial.replaceAll(RegExp(r'^[A-Z0-9]+:'), ''),
            'condition': condition,
            'expiry': '',
            'notes': '',
          });
        }
      }
      return items;
    }

    return items;
  }

  // تحويل هيدر العمود لاسم منتج نظيف
  String _headerToProductName(String header) {
    // إزالة كلمات الحالة
    String name = header
        .replaceAll('(جديد)', '')
        .replaceAll('(مستخدم)', '')
        .replaceAll('جديد', '')
        .replaceAll('مستخدم', '')
        .trim();

    // تحويل اختصارات معروفة
    final Map<String, String> knownProducts = {
      'dvr 2': 'Birdie DVR - 2 CAM',
      'dvr 3': 'Birdie DVR - 3 CAM',
      'مليسة m6': 'جهاز مليسة الإصدار السادس',
      'مليسة m5': 'جهاز مليسة الإصدار الخامس',
      'مس مون': 'Mismon/جهاز مس مون',
      '4g 3cam': 'G4 - مرآة بيردي الذكية CAM3',
      'تتبع 4g': 'GPS TRACKING - جهاز تتبع',
      'تتبع صيني': 'WETRACK 2/جهاز تتبع صينى',
      'شريحة': 'SIM CARD',
      'smart card': 'SMART CARD',
    };

    for (final entry in knownProducts.entries) {
      if (name.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    return name.isEmpty ? 'غير محدد' : name;
  }

  // ============================================================
  // استيراد PDF
  // ============================================================
  Future<void> _importFromPdf() async {
    final currentUser = await AuthService.instance.getCurrentUser();
    if (currentUser == null || !currentUser.canImport) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية الاستيراد')),
      );
      return;
    }
    
    setState(() {
      _loading = true;
      _status = 'جاري اختيار الملف...';
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null) {
        setState(() {
          _loading = false;
          _status = '';
        });
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
        _showPreview = items.isNotEmpty;
        _status = items.isEmpty
            ? 'مش قادر يقرأ الملف'
            : 'تم قراءة ${items.length} عنصر من PDF';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = 'خطأ في قراءة PDF: $e';
      });
    }
  }

  List<Map<String, String>> _parsePdfText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // ============================================================
    // نوع 1: Delivery Slip - فيه "Lot/Serial Number" أو "Shipping Date"
    // ============================================================
    if (lines.any((l) =>
        l.contains('Lot/Serial Number') ||
        l.contains('Shipping Date') ||
        RegExp(r'INT/\d+').hasMatch(l) ||
        RegExp(r'W\\H\d+/INT').hasMatch(l))) {
      return _parseDeliverySlip(lines);
    }

    // ============================================================
    // نوع 2: SMART CARD style - سطر أول اسم منتج + سيريالات فقط
    // ============================================================
    if (lines.length >= 2) {
      final firstLine = lines[0].trim();
      final restAreNumbers = lines
          .skip(1)
          .where((l) => l.isNotEmpty)
          .every((l) => RegExp(r'^\d[\d\s]*$').hasMatch(l));

      if (restAreNumbers &&
          firstLine.isNotEmpty &&
          !firstLine.contains('/') &&
          lines.length > 2) {
        return _parseSimpleSerialList(lines);
      }
    }

    // ============================================================
    // نوع 3: جرد المخزن - النوع القديم
    // ============================================================
    return _parseWarehouseInventory(lines);
  }

  // ============================================================
  // Parser: Delivery Slip
  // الشكل: Product | Lot/Serial Number | Quantity (1.000 Units)
  // ============================================================
  List<Map<String, String>> _parseDeliverySlip(List<String> lines) {
    final items = <Map<String, String>>[];

    // استخرج تاريخ الشحن
    String shippingDate = '';
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('Shipping Date') && i + 1 < lines.length) {
        final nextLine = lines[i + 1].trim();
        if (RegExp(r'\d{2}/\d{2}/\d{4}').hasMatch(nextLine)) {
          shippingDate = nextLine;
          break;
        }
      }
    }

    // استخرج رقم المخزن
    String warehouse = 'مخزن محمد مرسي';
    for (final l in lines) {
      if (RegExp(r'W\\?H42').hasMatch(l)) {
        warehouse = 'WH42/مخزن محمد مرسي';
        break;
      }
      if (RegExp(r'W\\?H32').hasMatch(l)) {
        warehouse = 'Stock 1';
        break;
      }
    }

    final serialPattern = RegExp(r'\b(\d{6,25})\b');
    final quantityPattern = RegExp(r'1\.000\s*Units', caseSensitive: false);
    final skipPatterns = [
      'Lot/Serial Number', 'Quantity', 'Product', 'Shipping Date',
      'مؤسسة', 'الطريق', 'Saudi Arabia', 'CR No', 'Vat No',
      'Page:', 'الرقم الضريبي', '13214', '1010535067', 'Riyadh',
    ];

    String currentProduct = '';

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // تجاهل الهيدر والفوتر
      if (skipPatterns.any((p) => line.contains(p))) continue;
      if (line.length < 3) continue;

      final serialMatches = serialPattern.allMatches(line).toList();

      if (serialMatches.isEmpty) {
        // سطر منتج فقط
        if (!quantityPattern.hasMatch(line) && line.length > 3) {
          final cleaned = _cleanName(line);
          if (cleaned.isNotEmpty) currentProduct = cleaned;
        }
        continue;
      }

      // استخرج اسم المنتج من السطر
      String productInLine = line
          .replaceAll(serialPattern, '')
          .replaceAll(quantityPattern, '')
          .replaceAll(RegExp(r'[\d\.\,]+'), '')
          .replaceAll('Units', '')
          .trim();
      productInLine = _cleanName(productInLine);
      if (productInLine.isNotEmpty) currentProduct = productInLine;

      final product =
          currentProduct.isEmpty ? 'غير محدد' : currentProduct;

      for (final match in serialMatches) {
        final serial = match.group(1)!;
        if (serial.length < 6) continue;

        items.add({
          'product': product,
          'warehouse': warehouse,
          'serial': serial,
          'condition': 'جديد',
          'expiry': '',
          'notes': shippingDate.isNotEmpty ? 'شحن: $shippingDate' : '',
        });
      }
    }

    return items;
  }

  // ============================================================
  // Parser: SMART CARD / Simple serial list
  // الشكل: اسم المنتج في أول سطر، باقي السطور سيريالات
  // ============================================================
  List<Map<String, String>> _parseSimpleSerialList(List<String> lines) {
    final items = <Map<String, String>>[];
    if (lines.isEmpty) return items;

    final productName = lines[0].trim();

    for (int i = 1; i < lines.length; i++) {
      final serial = lines[i].trim().replaceAll(' ', '');
      if (serial.isEmpty) continue;
      if (!RegExp(r'^\d{5,}$').hasMatch(serial)) continue;

      items.add({
        'product': productName,
        'warehouse': 'Stock 1',
        'serial': serial,
        'condition': 'جديد',
        'expiry': '',
        'notes': '',
      });
    }

    return items;
  }

  // ============================================================
  // Parser: Warehouse Inventory (جرد المخزن القديم)
  // ============================================================
  List<Map<String, String>> _parseWarehouseInventory(List<String> lines) {
    final items = <Map<String, String>>[];
    final serialPattern = RegExp(r'\b(\d{5,25})\b');
    final datePattern = RegExp(r'\d{1,2}/\d{1,2}/\d{4}');

    String currentProduct = '';
    String currentWarehouse = 'Stock 1';

    final conditionMap = {
      'مستخدم': 'مستخدم',
      'تالف': 'تالف',
      'عاطل': 'تالف',
      'مباع': 'مستخدم',
      'scrap': 'تالف',
    };

    final skipWords = [
      'الموقع', 'المنتج', 'ملاحظات', 'الكمية', 'الدليل',
      'رجاء', 'المراجعة', 'التوقيع', 'Product', 'Quantity',
      'Lot', 'Serial', 'Number', 'Units',
    ];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (skipWords.any((w) => line.contains(w))) continue;
      if (line.length < 3) continue;

      // استخرج المخزن
      final whMatch = RegExp(r'W[\\\/]?H(\d+)', caseSensitive: false)
          .firstMatch(line);
      if (whMatch != null) {
        currentWarehouse = 'WH${whMatch.group(1)}/مخزن محمد مرسي';
      }

      // استخرج الحالة
      String condition = 'جديد';
      String notes = '';
      for (final entry in conditionMap.entries) {
        if (line.toLowerCase().contains(entry.key)) {
          condition = entry.value;
          notes = entry.key;
          break;
        }
      }

      // استخرج تاريخ الصلاحية
      String expiry = '';
      final dateMatch = datePattern.firstMatch(line);
      if (dateMatch != null) expiry = dateMatch.group(0)!;

      // استخرج السيريال
      final serialMatches = serialPattern.allMatches(line).toList();
      if (serialMatches.isEmpty) {
        final cleaned = _cleanName(line);
        if (cleaned.length > 2) currentProduct = cleaned;
        continue;
      }

      // استخرج المنتج من السطر
      String productInLine = line
          .replaceAll(serialPattern, '')
          .replaceAll(datePattern, '')
          .replaceAll(RegExp(r'[\\\/\d\.\,]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      productInLine = _cleanName(productInLine);
      if (productInLine.length > 2) currentProduct = productInLine;

      for (final match in serialMatches) {
        final serial = match.group(1)!;
        if (serial.length < 5) continue;
        items.add({
          'product': currentProduct.isEmpty ? 'غير محدد' : currentProduct,
          'warehouse': currentWarehouse,
          'serial': serial,
          'condition': condition,
          'expiry': expiry,
          'notes': notes,
        });
      }
    }

    return items;
  }

  // تنظيف الأسماء
  String _cleanName(String name) {
    return name
        .replaceAll(RegExp(r'[\\\/\|\d]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s\-]+|[\s\-]+$'), '')
        .trim();
  }

  // ============================================================
  // حفظ البيانات
  // ============================================================
  Future<void> _saveAllItems() async {
    setState(() {
      _loading = true;
      _status = 'جاري الحفظ...';
    });
    int saved = 0;
    for (final item in _previewItems) {
      try {
        await FirestoreService.instance.insertItem(InventoryItem(
          warehouseName: item['warehouse'] ?? 'Stock 1',
          productName: item['product'] ?? 'غير محدد',
          serial: item['serial']?.isEmpty == true ? null : item['serial'],
          condition: item['condition'] ?? 'جديد',
          expiryDate: item['expiry']?.isEmpty == true ? null : item['expiry'],
          notes: item['notes']?.isEmpty == true ? null : item['notes'],
          inventoryDate: _selectedDate,
          addedByUid: _currentUser?.uid, // ✅ مين عمل الاستيراد
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

  void _deleteItem(int index) {
    setState(() {
      _previewItems.removeAt(index);
      _status = 'تم قراءة ${_previewItems.length} عنصر';
    });
  }

  Future<void> _deleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد'),
        content: const Text('هتحذف كل العناصر؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لأ')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white),
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() {
        _showPreview = false;
        _previewItems = [];
        _status = '';
      });
    }
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
                    const CircularProgressIndicator(
                        color: Color(0xFF1A237E)),
                    const SizedBox(height: 16),
                    Text(_status,
                        style: const TextStyle(fontSize: 16)),
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

                    // معلومة للمستخدم
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('📋 الأشكال المدعومة:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('Excel: شيت المخازن، جرد الجهاز، DVR، جرد محمد مرسي'),
                          Text('PDF: Delivery Slip، SMART CARD، جرد المخزن'),
                        ],
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
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
                              : _status.contains('خطأ') ||
                                      _status.contains('مش')
                                  ? Colors.red.shade50
                                  : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _status.contains('✅')
                                ? Colors.green
                                : _status.contains('خطأ') ||
                                        _status.contains('مش')
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
                                : _status.contains('خطأ') ||
                                        _status.contains('مش')
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
                          Expanded(
                            child: Text(
                              'معاينة (${_previewItems.length} عنصر)',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _deleteAll,
                            icon: const Icon(Icons.delete_sweep,
                                size: 18, color: Colors.red),
                            label: const Text('حذف الكل',
                                style: TextStyle(color: Colors.red)),
                          ),
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
                        itemCount: _previewItems.length > 100
                            ? 100
                            : _previewItems.length,
                        itemBuilder: (_, i) {
                          final item = _previewItems[i];
                          final condColor =
                              item['condition'] == 'جديد'
                                  ? Colors.green
                                  : item['condition'] == 'مستخدم'
                                      ? Colors.orange
                                      : Colors.red;
                          return Dismissible(
                            key: Key(
                                '${item['serial']}_${item['product']}_$i'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius:
                                    BorderRadius.circular(10),
                              ),
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.only(left: 20),
                              child: const Icon(Icons.delete,
                                  color: Colors.white, size: 28),
                            ),
                            onDismissed: (_) => _deleteItem(i),
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 4,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: condColor,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['product'] ?? '',
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.bold,
                                                fontSize: 13),
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            '${item['serial']} • ${item['warehouse']}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors
                                                    .grey.shade600),
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                          if (item['notes']
                                                  ?.isNotEmpty ==
                                              true)
                                            Text(
                                              item['notes']!,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors
                                                      .orange.shade700),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      children: [
                                        Container(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4),
                                          decoration: BoxDecoration(
                                            color: condColor
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            item['condition'] ?? 'جديد',
                                            style: TextStyle(
                                                color: condColor,
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.bold),
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                              Icons.delete_outline,
                                              color: Colors.red.shade300,
                                              size: 20),
                                          padding: EdgeInsets.zero,
                                          constraints:
                                              const BoxConstraints(),
                                          onPressed: () =>
                                              _deleteItem(i),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_previewItems.length > 100)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '... و ${_previewItems.length - 100} عنصر إضافي',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.grey.shade600),
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
                          padding: const EdgeInsets.symmetric(
                              vertical: 16),
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