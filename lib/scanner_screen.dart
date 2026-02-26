import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'database.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _scanned = false;
  bool _processing = false;
  final MobileScannerController _controller = MobileScannerController(
    formats: [BarcodeFormat.all],
    returnImage: true,
  );

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned || _processing) return;
    if (capture.barcodes.isNotEmpty) {
      final barcode = capture.barcodes.first;
      if (barcode.rawValue != null && barcode.rawValue!.isNotEmpty) {
        setState(() => _scanned = true);
        Navigator.pop(context, barcode.rawValue);
      }
    }
  }

Future<void> _captureAndOCR() async {
  if (_processing) return;
  setState(() => _processing = true);

  try {
    // التقط صورة من الكاميرا
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );

    if (photo == null) {
      setState(() => _processing = false);
      return;
    }

    final textRecognizer = TextRecognizer();
    final inputImage = InputImage.fromFilePath(photo.path);
    final recognized = await textRecognizer.processImage(inputImage);
    await textRecognizer.close();

    if (recognized.text.isNotEmpty && mounted) {
      final lines = recognized.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.length > 2)
          .toList();

      if (lines.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('مش قادر يقرأ النص، جرب تقرّب الكاميرا'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _processing = false);
        }
        return;
      }

      if (lines.length == 1) {
        setState(() => _scanned = true);
        if (mounted) Navigator.pop(context, lines.first);
      } else {
        setState(() => _processing = false);
        if (!mounted) return;
        final selected = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (ctx) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('اختار النص الصح',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView(
                    shrinkWrap: true,
                    children: lines.map((line) => ListTile(
                      title: Text(line, textDirection: TextDirection.ltr),
                      leading: const Icon(Icons.text_fields, color: Color(0xFF1A237E)),
                      onTap: () => Navigator.pop(ctx, line),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
        if (selected != null && mounted) {
          setState(() => _scanned = true);
          Navigator.pop(context, selected);
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('مش قادر يقرأ النص، جرب تقرّب الكاميرا'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _processing = false);
      }
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
      setState(() => _processing = false);
    }
  }
}

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('امسح الباركود أو النص'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // إطار التصويب
          Center(
            child: Container(
              width: 280,
              height: 180,
              decoration: BoxDecoration(
                border:
                    Border.all(color: Colors.greenAccent, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // مؤشر التحميل
          if (_processing)
            Container(
              color: Colors.black38,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      'جاري القراءة...',
                      style: TextStyle(
                          color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          // زرار OCR
          Positioned(
            bottom: 110,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: _processing ? null : _captureAndOCR,
                icon: _processing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.text_fields),
                label: const Text('اقرأ النص'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  textStyle: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          // تعليمات
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Container(
              margin:
                  const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'الباركود يُقرأ تلقائياً • اضغط "اقرأ النص" للنصوص المكتوبة',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AddItemScreen extends StatefulWidget {
  final String? initialSerial;
  final InventoryItem? itemToEdit;
  final String? selectedDate;

  const AddItemScreen(
      {super.key,
      this.initialSerial,
      this.itemToEdit,
      this.selectedDate});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serialController = TextEditingController();
  final _expiryController = TextEditingController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();

  List<String> _warehouses = [];
  List<String> _products = [];
  List<String> _filteredProducts = [];
  String? _selectedWarehouse;
  String? _selectedProduct;
  String _condition = 'جديد';
  bool _loading = false;

  final List<String> _conditions = ['جديد', 'مستخدم', 'تالف'];

  @override
  void initState() {
    super.initState();
    _loadDropdowns();
    if (widget.initialSerial != null)
      _serialController.text = widget.initialSerial!;
    if (widget.itemToEdit != null) {
      final item = widget.itemToEdit!;
      _selectedWarehouse = item.warehouseName;
      _selectedProduct = item.productName;
      _serialController.text = item.serial ?? '';
      _condition = item.condition;
      _expiryController.text = item.expiryDate ?? '';
      _notesController.text = item.notes ?? '';
    }
  }

  Future<void> _loadDropdowns() async {
    final warehouses = await DatabaseHelper.instance.getWarehouses();
    final products = await DatabaseHelper.instance.getProducts();
    setState(() {
      _warehouses = warehouses;
      _products = products;
      _filteredProducts = List.from(products);
      if (_selectedWarehouse == null && warehouses.isNotEmpty) {
        _selectedWarehouse = warehouses.first;
      }
    });
  }

  Future<void> _showProductPicker() async {
    _searchController.clear();
    _filteredProducts = List.from(_products);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin:
                    const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Text('اختار المنتج',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _addNewProduct();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('جديد'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: (q) {
                    setModalState(() {
                      _filteredProducts = q.isEmpty
                          ? List.from(_products)
                          : _products
                              .where((p) => p
                                  .toLowerCase()
                                  .contains(q.toLowerCase()))
                              .toList();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'بحث...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                    contentPadding:
                        const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _filteredProducts.length,
                  itemBuilder: (_, i) {
                    final p = _filteredProducts[i];
                    final isSelected = p == _selectedProduct;
                    return ListTile(
                      title: Text(p,
                          textDirection: TextDirection.rtl),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle,
                              color: Color(0xFF1A237E))
                          : null,
                      tileColor: isSelected
                          ? const Color(0xFF1A237E)
                              .withOpacity(0.08)
                          : null,
                      onTap: () {
                        setState(
                            () => _selectedProduct = p);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showWarehousePicker() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin:
                  const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Text('اختار المخزن',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _addNewWarehouse();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('جديد'),
                  ),
                ],
              ),
            ),
            ..._warehouses.map(
              (w) => ListTile(
                title:
                    Text(w, textDirection: TextDirection.rtl),
                trailing: w == _selectedWarehouse
                    ? const Icon(Icons.check_circle,
                        color: Color(0xFF1A237E))
                    : null,
                tileColor: w == _selectedWarehouse
                    ? const Color(0xFF1A237E)
                        .withOpacity(0.08)
                    : null,
                onTap: () {
                  setState(() => _selectedWarehouse = w);
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _addNewWarehouse() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مخزن جديد'),
        content: TextField(
          controller: controller,
          decoration:
              const InputDecoration(hintText: 'اسم المخزن'),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim()),
              child: const Text('إضافة')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await DatabaseHelper.instance.addWarehouse(result);
      await _loadDropdowns();
      setState(() => _selectedWarehouse = result);
    }
  }

  Future<void> _addNewProduct() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة منتج جديد'),
        content: TextField(
          controller: controller,
          decoration:
              const InputDecoration(hintText: 'اسم المنتج'),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, controller.text.trim()),
              child: const Text('إضافة')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await DatabaseHelper.instance.addProduct(result);
      await _loadDropdowns();
      setState(() => _selectedProduct = result);
    }
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (result != null)
      setState(() => _serialController.text = result);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedWarehouse == null || _selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اختار المخزن والمنتج أولاً')));
      return;
    }
    setState(() => _loading = true);
    final item = InventoryItem(
      id: widget.itemToEdit?.id,
      warehouseName: _selectedWarehouse!,
      productName: _selectedProduct!,
      serial: _serialController.text.trim().isEmpty
          ? null
          : _serialController.text.trim(),
      condition: _condition,
      expiryDate: _expiryController.text.trim().isEmpty
          ? null
          : _expiryController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      inventoryDate:
          widget.itemToEdit?.inventoryDate ?? widget.selectedDate,
    );
    if (widget.itemToEdit != null) {
      await DatabaseHelper.instance.updateItem(item);
    } else {
      await DatabaseHelper.instance.insertItem(item);
    }
    setState(() => _loading = false);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itemToEdit != null
            ? 'تعديل قطعة'
            : 'إضافة قطعة'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // المخزن
                GestureDetector(
                  onTap: _showWarehousePicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warehouse,
                            color: Color(0xFF1A237E)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedWarehouse ??
                                'اختار المخزن',
                            style: TextStyle(
                              fontSize: 15,
                              color: _selectedWarehouse != null
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down,
                            color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // المنتج
                GestureDetector(
                  onTap: _showProductPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2,
                            color: Color(0xFF1A237E)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedProduct ?? 'اختار المنتج',
                            style: TextStyle(
                              fontSize: 15,
                              color: _selectedProduct != null
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down,
                            color: Colors.grey),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // السريال
                TextFormField(
                  controller: _serialController,
                  decoration: InputDecoration(
                    labelText: 'السريال / Barcode',
                    prefixIcon: const Icon(Icons.qr_code,
                        color: Color(0xFF1A237E)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner,
                          color: Color(0xFF1A237E)),
                      onPressed: _scanBarcode,
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF1A237E), width: 2),
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: 12),

                // الحالة
                const Text('حالة القطعة',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15)),
                const SizedBox(height: 8),
                Row(
                  children: _conditions.map((c) {
                    Color color = c == 'جديد'
                        ? Colors.green
                        : c == 'مستخدم'
                            ? Colors.orange
                            : Colors.red;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4),
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _condition = c),
                          child: AnimatedContainer(
                            duration: const Duration(
                                milliseconds: 200),
                            padding:
                                const EdgeInsets.symmetric(
                                    vertical: 12),
                            decoration: BoxDecoration(
                              color: _condition == c
                                  ? color
                                  : Colors.grey.shade100,
                              borderRadius:
                                  BorderRadius.circular(12),
                              border: Border.all(
                                  color: _condition == c
                                      ? color
                                      : Colors.grey.shade300),
                            ),
                            child: Text(
                              c,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _condition == c
                                    ? Colors.white
                                    : Colors.grey,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // تاريخ الصلاحية
                TextFormField(
                  controller: _expiryController,
                  decoration: InputDecoration(
                    labelText: 'تاريخ الصلاحية (اختياري)',
                    prefixIcon: const Icon(Icons.calendar_today,
                        color: Color(0xFF1A237E)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (date != null) {
                      _expiryController.text =
                          '${date.day}/${date.month}/${date.year}';
                    }
                  },
                ),
                const SizedBox(height: 12),

                // ملاحظات
                TextFormField(
                  controller: _notesController,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    prefixIcon: const Icon(Icons.notes,
                        color: Color(0xFF1A237E)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF1A237E), width: 2),
                    ),
                  ),
                  textDirection: TextDirection.rtl,
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                ElevatedButton.icon(
                  onPressed: _loading ? null : _save,
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(widget.itemToEdit != null
                      ? 'تحديث'
                      : 'حفظ'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 16),
                    textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}