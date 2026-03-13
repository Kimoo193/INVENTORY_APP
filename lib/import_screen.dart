import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:io';
import 'firestore_service.dart';
import 'auth_service.dart';
import 'inventory_repository.dart';

// ============================================================
// Smart Header Detector — بيتعرف على أي Excel بغض النظر عن
// اسم الـ column أو لغته أو ترتيبه
// ============================================================

class ColMap {
  final int? product;
  final int? serial;
  final int? warehouse;
  final int? condition;
  final int? expiry;
  final int? notes;

  const ColMap({
    this.product,
    this.serial,
    this.warehouse,
    this.condition,
    this.expiry,
    this.notes,
  });

  bool get hasProduct => product != null;
  bool get hasSerial => serial != null;
}

class SmartHeaderDetector {
  // ✅ كل الأسماء المحتملة لكل عمود — عربي وإنجليزي وهجين
  static const _productNames = [
    'product', 'product name', 'product/display name', 'display name',
    'item', 'item name', 'description', 'المنتج', 'اسم المنتج',
    'الصنف', 'البند', 'الجهاز', 'نوع الجهاز', 'نوع', 'الموديل',
    'model', 'device', 'name',
  ];

  static const _serialNames = [
    'serial', 'serial number', 'serial no', 'serial#', 's/n', 'sn',
    'lot', 'lot/serial', 'lot/serial number', 'lot number',
    'barcode', 'imei', 'mac', 'mac address',
    'السيريال', 'السريال', 'السريل', 'رقم السيريال', 'رقم التسلسل',
    'الباركود', 'الرقم التسلسلي', 'رقم الجهاز', 'كود',
  ];

  static const _warehouseNames = [
    'warehouse', 'location', 'store', 'stock', 'site', 'branch',
    'المخزن', 'الموقع', 'المستودع', 'الفرع', 'المكان', 'الموضع',
    'مكان التخزين', 'وحدة التخزين',
  ];

  static const _conditionNames = [
    'condition', 'status', 'state', 'quality', 'grade',
    'inventoried quantity',
    'inventoried qty',
    'quantity inventoried',
    'counted quantity',
    'qty counted',
    'الحالة', 'حالة الجهاز', 'الوضع', 'الجودة', 'نوع الحالة',
    'الكمية المجردة',
  ];

  static const _expiryNames = [
    'expiry', 'expiry date', 'expiration', 'expire', 'exp date', 'exp',
    'best before', 'valid until', 'validity',
    'تاريخ الصلاحية', 'الصلاحية', 'انتهاء', 'انتهاء الصلاحية',
    'تاريخ الانتهاء', 'صالح حتى',
  ];

  static const _notesNames = [
    'notes', 'note', 'remarks', 'comment', 'comments', 'description',
    'details', 'info', 'additional',
    'ملاحظات', 'ملاحظة', 'تعليقات', 'تفاصيل', 'بيانات إضافية',
  ];

  // ✅ score: كلما زاد → أقرب للـ column المقصود
  static int _score(String header, List<String> candidates) {
    final h = header.toLowerCase().trim();
    if (h.isEmpty) return 0;

    // exact match
    for (final c in candidates) {
      if (h == c) return 100;
    }
    // starts with
    for (final c in candidates) {
      if (h.startsWith(c) || c.startsWith(h)) return 80;
    }
    // contains
    for (final c in candidates) {
      if (h.contains(c) || c.contains(h)) return 60;
    }
    return 0;
  }

  static ColMap detect(List<String> headers) {
    int? productCol, serialCol, warehouseCol, conditionCol, expiryCol, notesCol;
    int productScore = 0, serialScore = 0, warehouseScore = 0,
        conditionScore = 0, expiryScore = 0, notesScore = 0;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];

      final ps = _score(h, _productNames);
      if (ps > productScore) { productScore = ps; productCol = i; }

      final ss = _score(h, _serialNames);
      if (ss > serialScore) { serialScore = ss; serialCol = i; }

      final ws = _score(h, _warehouseNames);
      if (ws > warehouseScore) { warehouseScore = ws; warehouseCol = i; }

      final cs = _score(h, _conditionNames);
      if (cs > conditionScore) { conditionScore = cs; conditionCol = i; }

      final es = _score(h, _expiryNames);
      if (es > expiryScore) { expiryScore = es; expiryCol = i; }

      final ns = _score(h, _notesNames);
      if (ns > notesScore) { notesScore = ns; notesCol = i; }
    }

    // ✅ لو مفيش header واضح → تجاهل العمود ده
    return ColMap(
      product:   productScore   >= 40 ? productCol   : null,
      serial:    serialScore    >= 40 ? serialCol     : null,
      warehouse: warehouseScore >= 40 ? warehouseCol  : null,
      condition: conditionScore >= 40 ? conditionCol  : null,
      expiry:    expiryScore    >= 40 ? expiryCol     : null,
      notes:     notesScore     >= 40 ? notesCol      : null,
    );
  }
}

// ============================================================
// ImportScreen
// ============================================================

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
  AppUser? _currentUser;

  // ✅ لو الـ import اكتشف مخزن افتراضي مختلف — يعرضه للـ user
  String _defaultWarehouse = 'Stock 1';
  String? _detectedFormat; // لإظهار نوع الملف اللي اتعرف عليه

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
  // استيراد Excel — Smart Detection
  // ============================================================
  Future<void> _importFromExcel() async {
    final currentUser = await AuthService.instance.getCurrentUser();
    if (!mounted) return;
    if (currentUser == null || !currentUser.canImport) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية الاستيراد')),
      );
      return;
    }

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

      setState(() => _status = 'جاري قراءة الملف...');

      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final items = <Map<String, String>>[];
      String detectedFormat = '';

      for (final sheetName in excel.tables.keys) {
        final sheet = excel.tables[sheetName]!;
        if (sheet.rows.isEmpty) continue;

        // ✅ تجاهل الشيتات الفارغة أو اللي فيها سطر واحد بس
        if (sheet.rows.length < 2) continue;

        // ✅ استخرج الهيدر — جرب أول 3 صفوف لو الأول فارغ أو عنوان
        List<String> headers = [];
        int dataStartRow = 1;

        for (int rowIdx = 0; rowIdx < min(3, sheet.rows.length); rowIdx++) {
          final row = sheet.rows[rowIdx];
          final rowHeaders = row
              .map((c) => (c?.value?.toString() ?? '').trim())
              .toList();

          // ✅ الهيدر الحقيقي بيكون فيه كلمات مش أرقام بس
          final hasText = rowHeaders.any((h) =>
              h.isNotEmpty && !RegExp(r'^\d+$').hasMatch(h));
          if (hasText) {
            headers = rowHeaders;
            dataStartRow = rowIdx + 1;
            break;
          }
        }

        if (headers.isEmpty) continue;

        // ✅ Smart Header Detection
        final colMap = SmartHeaderDetector.detect(headers);

        if (colMap.hasProduct || colMap.hasSerial) {
          // ✅ شيت بـ headers واضحة
          final sheetItems = _parseStructuredSheet(sheet, colMap, dataStartRow);
          items.addAll(sheetItems);
          detectedFormat = 'شيت منظّم (${sheetItems.length} قطعة)';
        } else {
          // ✅ شيت بدون headers واضحة — جرب كل عمود كمنتج
          final sheetItems = _parseColumnPerProductSheet(sheet, headers);
          items.addAll(sheetItems);
          if (sheetItems.isNotEmpty) {
            detectedFormat = 'شيت أعمدة (${sheetItems.length} قطعة)';
          }
        }
      }

      // ✅ إزالة duplicates بالسيريال
      final seen = <String>{};
      final unique = items.where((i) {
        final serial = i['serial'] ?? '';
        if (serial.isEmpty) return true;
        return seen.add(serial);
      }).toList();

      setState(() {
        _loading = false;
        _previewItems = unique;
        _showPreview = unique.isNotEmpty;
        _detectedFormat = detectedFormat;
        _status = unique.isEmpty
            ? 'مش قادر يقرأ الملف — تأكد من وجود header واضح'
            : 'تم قراءة ${unique.length} عنصر من Excel';
      });
    } catch (e) {
      setState(() { _loading = false; _status = 'خطأ: $e'; });
    }
  }

  int min(int a, int b) => a < b ? a : b;

  // ============================================================
  // Parser: شيت بـ headers — بيستخدم الـ ColMap
  // ============================================================
  List<Map<String, String>> _parseStructuredSheet(
      Sheet sheet, ColMap colMap, int dataStartRow) {
    final items = <Map<String, String>>[];

    String getCell(List<Data?> row, int? col) {
      if (col == null || col >= row.length || row[col] == null) return '';
      return row[col]!.value?.toString().trim() ?? '';
    }

    for (int i = dataStartRow; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.every((c) => c == null || c.value == null)) continue;

      final product = _cleanName(getCell(row, colMap.product));
      final serial = _cleanSerial(getCell(row, colMap.serial));
      final warehouse = getCell(row, colMap.warehouse);
      final condRaw = getCell(row, colMap.condition);
      var expiry = getCell(row, colMap.expiry);
      final notesRaw = getCell(row, colMap.notes);

      // ✅ لو مفيش منتج ولا سيريال → skip
      if (product.isEmpty && serial.isEmpty) continue;
      // ✅ تجاهل سطور المحذوفات
      if (product.startsWith('[محذوف]') || product.startsWith('[deleted]')) { continue; }
      // ✅ تجاهل سطور الـ totals
      if (product.toLowerCase().contains('total') ||
          product.toLowerCase().contains('إجمالي')) continue;

      if (expiry == '-' || expiry == 'N/A' || expiry == 'n/a') expiry = '';
        final baseNotes = (notesRaw == '-' || notesRaw == 'N/A' || notesRaw == 'n/a')
          ? ''
          : notesRaw;
        final quantityNotes = _extractNotesFromQuantity(condRaw);
        final notes = _mergeNotes(baseNotes, quantityNotes);

      items.add({
        'product': product.isEmpty ? 'غير محدد' : product,
        'warehouse': warehouse.isEmpty ? _defaultWarehouse : _normalizeWarehouse(warehouse),
        'serial': serial,
        'condition': _normalizeCondition(condRaw),
        'expiry': expiry,
        'notes': notes,
      });
    }

    return items;
  }

  // ============================================================
  // Parser: كل عمود = منتج، السطور = سيريالات
  // مثال: DVR_2-9_.xlsx, جرد_أ_محمدمرسي
  // ============================================================
  List<Map<String, String>> _parseColumnPerProductSheet(
      Sheet sheet, List<String> headers) {
    final items = <Map<String, String>>[];

    for (int col = 0; col < headers.length; col++) {
      final header = headers[col].trim();
      if (header.isEmpty) continue;

      // ✅ الهيدر هو اسم المنتج — استخرج الحالة منه لو موجودة
      final condition = _extractConditionFromHeader(header);
      final productName = _cleanProductNameFromHeader(header);
      if (productName.isEmpty) continue;

      for (int row = 1; row < sheet.rows.length; row++) {
        if (col >= sheet.rows[row].length) continue;
        final cell = sheet.rows[row][col];
        if (cell == null || cell.value == null) continue;

        final serial = _cleanSerial(cell.value!.toString().trim());
        if (serial.isEmpty) continue;
        // ✅ تأكد إن الـ serial فيه أرقام (مش نص عادي)
        if (!RegExp(r'\d{4,}').hasMatch(serial)) continue;

        items.add({
          'product': productName,
          'warehouse': _defaultWarehouse,
          'serial': serial,
          'condition': condition,
          'expiry': '',
          'notes': '',
        });
      }
    }

    return items;
  }

  // ============================================================
  // استيراد PDF — محسّن
  // ============================================================
  Future<void> _importFromPdf() async {
    final currentUser = await AuthService.instance.getCurrentUser();
    if (!mounted) return;
    if (currentUser == null || !currentUser.canImport) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية الاستيراد')),
      );
      return;
    }

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

      setState(() => _status = 'جاري قراءة PDF...');

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
      setState(() { _loading = false; _status = 'خطأ في قراءة PDF: $e'; });
    }
  }

  List<Map<String, String>> _parsePdfText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.any((l) =>
        l.contains('Lot/Serial Number') ||
        l.contains('Shipping Date') ||
        RegExp(r'INT/\d+').hasMatch(l))) {
      return _parseDeliverySlip(lines);
    }

    if (lines.length >= 2) {
      final firstLine = lines[0].trim();
      final restAreNumbers = lines
          .skip(1)
          .where((l) => l.isNotEmpty)
          .every((l) => RegExp(r'^\d[\d\s]*$').hasMatch(l));
      if (restAreNumbers && firstLine.isNotEmpty && lines.length > 2) {
        return _parseSimpleSerialList(lines);
      }
    }

    return _parseWarehouseInventory(lines);
  }

  List<Map<String, String>> _parseDeliverySlip(List<String> lines) {
    final items = <Map<String, String>>[];
    String shippingDate = '';
    String warehouse = _defaultWarehouse;

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('Shipping Date') && i + 1 < lines.length) {
        final nextLine = lines[i + 1].trim();
        if (RegExp(r'\d{2}/\d{2}/\d{4}').hasMatch(nextLine)) {
          shippingDate = nextLine;
          break;
        }
      }
    }

    for (final l in lines) {
      if (RegExp(r'WH42').hasMatch(l)) { warehouse = 'WH42/مخزن محمد مرسي'; break; }
      if (RegExp(r'WH32').hasMatch(l)) { warehouse = 'Stock 1'; break; }
    }

    final serialPattern = RegExp(r'\b(\d{6,25})\b');
    final quantityPattern = RegExp(r'1\.000\s*Units', caseSensitive: false);
    final skipPatterns = [
      'Lot/Serial Number', 'Quantity', 'Product', 'Shipping Date',
      'مؤسسة', 'Saudi Arabia', 'CR No', 'Vat No', 'Page:',
    ];

    String currentProduct = '';

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (skipPatterns.any((p) => line.contains(p))) continue;
      if (line.length < 3) continue;

      final serialMatches = serialPattern.allMatches(line).toList();

      if (serialMatches.isEmpty) {
        if (!quantityPattern.hasMatch(line) && line.length > 3) {
          final cleaned = _cleanName(line);
          if (cleaned.isNotEmpty) currentProduct = cleaned;
        }
        continue;
      }

      String productInLine = line
          .replaceAll(serialPattern, '')
          .replaceAll(quantityPattern, '')
          .replaceAll(RegExp(r'\b\d{4,}\b'), '') // شيل الأرقام الطويلة (سيريالات متبقية) بس مش أرقام قصيرة في الأسماء
          .replaceAll('Units', '')
          .trim();
      productInLine = _cleanName(productInLine);
      if (productInLine.isNotEmpty) currentProduct = productInLine;

      final product = currentProduct.isEmpty ? 'غير محدد' : currentProduct;

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
        'warehouse': _defaultWarehouse,
        'serial': serial,
        'condition': 'جديد',
        'expiry': '',
        'notes': '',
      });
    }

    return items;
  }

  List<Map<String, String>> _parseWarehouseInventory(List<String> lines) {
    final items = <Map<String, String>>[];
    final serialPattern = RegExp(r'\b(\d{5,25})\b');
    final datePattern = RegExp(r'\d{1,2}/\d{1,2}/\d{4}');

    String currentProduct = '';
    String currentWarehouse = _defaultWarehouse;

    final conditionMap = {
      'مستخدم': 'مستخدم',
      'تالف': 'تالف',
      'عاطل': 'تالف',
      'scrap': 'تالف',
    };

    final skipWords = [
      'الموقع', 'المنتج', 'ملاحظات', 'الكمية',
      'Product', 'Quantity', 'Lot', 'Serial', 'Number', 'Units',
    ];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (skipWords.any((w) => line.contains(w))) continue;
      if (line.length < 3) continue;

      final whMatch = RegExp(r'WH(\d+)', caseSensitive: false).firstMatch(line);
      if (whMatch != null) {
        currentWarehouse = 'WH${whMatch.group(1)}/مخزن';
      }

      String condition = 'جديد';
      for (final entry in conditionMap.entries) {
        if (line.toLowerCase().contains(entry.key)) {
          condition = entry.value;
          break;
        }
      }

      String expiry = '';
      final dateMatch = datePattern.firstMatch(line);
      if (dateMatch != null) expiry = dateMatch.group(0)!;

      final serialMatches = serialPattern.allMatches(line).toList();
      if (serialMatches.isEmpty) {
        final cleaned = _cleanName(line);
        if (cleaned.length > 2) currentProduct = cleaned;
        continue;
      }

      String productInLine = line
          .replaceAll(serialPattern, '')
          .replaceAll(datePattern, '')
          .replaceAll(RegExp(r'[\\\/]'), ' ')
          .replaceAll(RegExp(r'\b\d{5,}\b'), '')
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
          'notes': '',
        });
      }
    }

    return items;
  }

  // ============================================================
  // Helper Functions
  // ============================================================

  String _cleanName(String name) {
    return name
        .replaceAll(RegExp(r'[\\\/\|]'), ' ') // لا نمسح الأرقام
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s\-]+|[\s\-]+$'), '')
        .trim();
  }

  String _cleanSerial(String serial) {
    // ✅ إزالة prefix زي "206B:" أو "SN:"
    return serial
        .replaceAll(RegExp(r'^[A-Za-z0-9]+:\s*'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  String _normalizeCondition(String raw) {
    final r = raw.toLowerCase().trim();
    if (r.isEmpty || r == 'جديد' || r == 'new' || r == 'good') return 'جديد';

    // Odoo sometimes puts quantity prefix in the same cell, e.g. "1موجودة".
    final normalized = r.replaceFirst(RegExp(r'^\d+\s*'), '').trim();
    if (normalized.isEmpty) return 'جديد';

    if (normalized.contains('مستخدم') ||
        normalized.contains('used') ||
        normalized.contains('refurb')) {
      return 'مستخدم';
    }

    if (normalized.contains('تالف') ||
        normalized.contains('عاطل') ||
        normalized.contains('damaged') ||
        normalized.contains('broken') ||
        normalized.contains('faulty') ||
        normalized.contains('scrap')) {
      return 'تالف';
    }

    if (normalized.contains('مباع') || normalized.contains('sold')) return 'مستخدم';
    if (normalized.contains('موجود') || normalized.contains('available')) return 'جديد';

    return 'جديد';
  }

  String _extractNotesFromQuantity(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return '';

    final normalized = r.toLowerCase().replaceFirst(RegExp(r'^\d+\s*'), '').trim();
    if (normalized.isEmpty) return '';

    if (normalized.contains('مباع')) return 'مباع';
    if (normalized.contains('لم استلمها ولم تشحن')) return 'لم استلمها ولم تشحن';

    // Pure condition markers should not become notes.
    if (normalized.contains('موجود') ||
        normalized == 'جديد' ||
        normalized.contains('مستخدم') ||
        normalized.contains('تالف') ||
        normalized.contains('عاطل')) {
      return '';
    }

    return normalized;
  }

  String _mergeNotes(String base, String extra) {
    if (base.isEmpty) return extra;
    if (extra.isEmpty) return base;
    if (base == extra) return base;
    return '$base | $extra';
  }

  String _normalizeWarehouse(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return _defaultWarehouse;

    // Odoo location can be hierarchical, keep the last segment as display name.
    if (r.contains('/')) {
      final lastSegment = r.split('/').last.trim();
      if (lastSegment.isNotEmpty) return lastSegment;
    }

    // ✅ normalize أسماء المخازن الشائعة
    if (RegExp(r'WH\s*42', caseSensitive: false).hasMatch(r)) return 'WH42/مخزن محمد مرسي';
    if (RegExp(r'W\\?H\s*32', caseSensitive: false).hasMatch(r)) return 'Stock 1';
    return r;
  }

  String _extractConditionFromHeader(String header) {
    if (header.contains('مستخدم') || header.toLowerCase().contains('used')) return 'مستخدم';
    if (header.contains('تالف') || header.contains('عاطل') || header.toLowerCase().contains('damaged')) return 'تالف';
    return 'جديد';
  }

  String _cleanProductNameFromHeader(String header) {
    return header
        .replaceAll(RegExp(r'\(جديد\)|\(مستخدم\)|\(تالف\)'), '')
        .replaceAll(RegExp(r'جديد|مستخدم|تالف|عاطل'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ============================================================
  // حفظ البيانات — Batch بدل واحد واحد
  // ============================================================
  Future<void> _saveAllItems() async {
    setState(() { _loading = true; _status = 'جاري الحفظ...'; });

    final firestoreItems = _previewItems.map((item) => InventoryItem(
      warehouseName: item['warehouse'] ?? _defaultWarehouse,
      productName: item['product'] ?? 'غير محدد',
      serial: item['serial']?.isEmpty == true ? null : item['serial'],
      condition: item['condition'] ?? 'جديد',
      expiryDate: item['expiry']?.isEmpty == true ? null : item['expiry'],
      notes: item['notes']?.isEmpty == true ? null : item['notes'],
      inventoryDate: _selectedDate,
      addedByUid: _currentUser?.uid,
    )).toList();

    // ✅ Batch insert to Hive first — instant, queued to Firestore
    final saved = await InventoryRepository.instance.insertItemsBatch(firestoreItems);

    setState(() {
      _loading = false;
      _showPreview = false;
      _previewItems = [];
      _detectedFormat = null;
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لأ')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() { _showPreview = false; _previewItems = []; _status = ''; _detectedFormat = null; });
    }
  }

  // ✅ تعديل عنصر في الـ preview
  Future<void> _editItem(int index) async {
    final item = Map<String, String>.from(_previewItems[index]);
    final productCtrl = TextEditingController(text: item['product']);
    final serialCtrl = TextEditingController(text: item['serial']);
    final warehouseCtrl = TextEditingController(text: item['warehouse']);
    String condition = item['condition'] ?? 'جديد';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تعديل العنصر'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: productCtrl,
                  decoration: const InputDecoration(labelText: 'المنتج', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: serialCtrl,
                  decoration: const InputDecoration(labelText: 'السيريال', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: warehouseCtrl,
                  decoration: const InputDecoration(labelText: 'المخزن', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: condition,
                  decoration: const InputDecoration(labelText: 'الحالة', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'جديد', child: Text('جديد')),
                    DropdownMenuItem(value: 'مستخدم', child: Text('مستخدم')),
                    DropdownMenuItem(value: 'تالف', child: Text('تالف')),
                  ],
                  onChanged: (v) => setD(() => condition = v ?? 'جديد'),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _previewItems[index] = {
                      'product': productCtrl.text.trim(),
                      'serial': serialCtrl.text.trim(),
                      'warehouse': warehouseCtrl.text.trim(),
                      'condition': condition,
                      'expiry': item['expiry'] ?? '',
                      'notes': item['notes'] ?? '',
                    };
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('استيراد بيانات'),
          backgroundColor: const Color(0xFF16324F),
          foregroundColor: Colors.white,
        ),
        body: _loading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF16324F)),
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
                    // ── تاريخ الجرد ──
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.calendar_today, color: Color(0xFF16324F)),
                        title: const Text('تاريخ الجرد'),
                        subtitle: Text(_formatDate(_selectedDate!)),
                        trailing: const Icon(Icons.edit, color: Color(0xFF16324F), size: 18),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── المخزن الافتراضي ──
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.warehouse, color: Color(0xFF16324F)),
                        title: const Text('المخزن الافتراضي'),
                        subtitle: Text(_defaultWarehouse),
                        trailing: const Icon(Icons.edit, color: Color(0xFF16324F), size: 18),
                        onTap: () async {
                          final ctrl = TextEditingController(text: _defaultWarehouse);
                          final result = await showDialog<String>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('المخزن الافتراضي'),
                              content: TextField(
                                controller: ctrl,
                                decoration: const InputDecoration(
                                  hintText: 'اسم المخزن اللي هيتحط فيه لو مش محدد',
                                  border: OutlineInputBorder(),
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                                ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('حفظ')),
                              ],
                            ),
                          );
                          if (result != null && result.isNotEmpty) {
                            setState(() => _defaultWarehouse = result);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── معلومة Smart Detection ──
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
                          Text('🧠 كشف تلقائي للأعمدة:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('التطبيق بيتعرف على أي Excel بغض النظر عن اسم أو ترتيب الأعمدة'),
                          Text('يدعم: العربي والإنجليزي والهجين'),
                          SizedBox(height: 4),
                          Text('PDF: Delivery Slip ، SMART CARD ، جرد المخزن'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── أزرار الاستيراد ──
                    ElevatedButton.icon(
                      onPressed: _importFromExcel,
                      icon: const Icon(Icons.table_chart),
                      label: const Text('استيراد من Excel', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    ElevatedButton.icon(
                      onPressed: _importFromPdf,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('استيراد من PDF', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),

                    // ── Status ──
                    if (_status.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _status.contains('✅')
                              ? Colors.green.shade50
                              : _status.contains('خطأ') || _status.contains('مش')
                                  ? Colors.red.shade50
                                  : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _status.contains('✅')
                                ? Colors.green
                                : _status.contains('خطأ') || _status.contains('مش')
                                    ? Colors.red
                                    : Colors.blue,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _status,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                color: _status.contains('✅')
                                    ? Colors.green.shade700
                                    : _status.contains('خطأ') || _status.contains('مش')
                                        ? Colors.red.shade700
                                        : Colors.blue.shade700,
                              ),
                            ),
                            if (_detectedFormat != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                '📋 نوع الملف: $_detectedFormat',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // ── Preview ──
                    if (_showPreview && _previewItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: Text(
                            'معاينة (${_previewItems.length} عنصر)',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _deleteAll,
                          icon: const Icon(Icons.delete_sweep, size: 18, color: Colors.red),
                          label: const Text('حذف الكل', style: TextStyle(color: Colors.red)),
                        ),
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _showPreview = false;
                            _previewItems = [];
                            _status = '';
                            _detectedFormat = null;
                          }),
                          icon: const Icon(Icons.clear, size: 18),
                          label: const Text('إلغاء'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _previewItems.length > 100 ? 100 : _previewItems.length,
                        itemBuilder: (_, i) {
                          final item = _previewItems[i];
                          final condColor = item['condition'] == 'جديد'
                              ? Colors.green
                              : item['condition'] == 'مستخدم'
                                  ? Colors.orange
                                  : Colors.red;

                          return Dismissible(
                            key: Key('${item['serial']}_${item['product']}_$i'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                  color: Colors.red, borderRadius: BorderRadius.circular(10)),
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              child: const Icon(Icons.delete, color: Colors.white, size: 28),
                            ),
                            onDismissed: (_) => _deleteItem(i),
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(children: [
                                  Container(
                                    width: 4, height: 50,
                                    decoration: BoxDecoration(
                                        color: condColor, borderRadius: BorderRadius.circular(4)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['product'] ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${item['serial']?.isEmpty == true ? 'بدون سيريال' : item['serial']} • ${item['warehouse']}',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // ✅ زر تعديل + badge الحالة
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                            color: condColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8)),
                                        child: Text(
                                          item['condition'] ?? 'جديد',
                                          style: TextStyle(color: condColor, fontSize: 11, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Row(mainAxisSize: MainAxisSize.min, children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, size: 18, color: Color(0xFF16324F)),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _editItem(i),
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 18),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _deleteItem(i),
                                        ),
                                      ]),
                                    ],
                                  ),
                                ]),
                              ),
                            ),
                          );
                        },
                      ),
                      if (_previewItems.length > 100)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            '... و ${_previewItems.length - 100} عنصر إضافي',
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
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16324F),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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