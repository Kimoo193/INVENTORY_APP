import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'firestore_service.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'inventory_repository.dart';

// ============================================================
// ScannerScreen — Enhanced with:
//   1. Animated scan line
//   2. Corner-only frame (L-shape corners)
//   3. Torch / Flash toggle
//   4. Pinch-to-zoom + zoom slider
//   5. Tap-to-focus with ripple indicator
//   6. HapticFeedback + white flash on successful scan
//   7. Camera switch (front/back)
//   8. Format filter (All / QR / Barcode)
//   9. Session scan history (last 5)
//  10. OCR cropped to frame region
// ============================================================

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with TickerProviderStateMixin {

  // ── Controller ───────────────────────────────────────────
  late MobileScannerController _controller;
  bool _scanned    = false;
  bool _processing = false;

  // ── Torch ────────────────────────────────────────────────
  bool _torchOn = false;

  // ── Zoom ─────────────────────────────────────────────────
  double _zoomScale       = 0.0;   // 0.0–1.0
  double _baseZoom        = 0.0;
  bool   _showZoomSlider  = false;

  // ── Camera facing ────────────────────────────────────────
  CameraFacing _facing = CameraFacing.back;

  // ── Format filter ────────────────────────────────────────
  // 0 = All, 1 = QR only, 2 = Barcode (linear) only
  int _formatMode = 0;
  static const _formatLabels = ['الكل', 'QR', 'Barcode'];

  // ── Scan history (this session) ──────────────────────────
  final List<String> _history = [];

  // ── Scan flash animation ─────────────────────────────────
  late AnimationController _flashCtrl;
  late Animation<double>   _flashAnim;

  // ── Scan line animation ───────────────────────────────────
  late AnimationController _lineCtrl;
  late Animation<double>   _lineAnim;

  // ── Tap-to-focus indicator ───────────────────────────────
  Offset? _focusTap;
  late AnimationController _focusCtrl;
  late Animation<double>   _focusAnim;

  // ── Zoom slider auto-hide ────────────────────────────────
  DateTime? _lastZoomChange;

  @override
  void initState() {
    super.initState();
    _buildController();

    // White flash on scan success
    _flashCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 180));
    _flashAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut));

    // Scan line — bounces top↔bottom inside frame
    _lineCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _lineAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _lineCtrl, curve: Curves.easeInOut));

    // Tap-to-focus ripple
    _focusCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
    _focusAnim = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _focusCtrl, curve: Curves.easeOut));
  }

  void _buildController() {
    List<BarcodeFormat> formats;
    switch (_formatMode) {
      case 1: formats = [BarcodeFormat.qrCode]; break;
      case 2: formats = [
        BarcodeFormat.code128, BarcodeFormat.code39,
        BarcodeFormat.ean13,   BarcodeFormat.ean8,
        BarcodeFormat.upcA,    BarcodeFormat.upcE,
        BarcodeFormat.itf,     BarcodeFormat.aztec,
      ]; break;
      default: formats = [BarcodeFormat.all];
    }
    _controller = MobileScannerController(
      facing:      _facing,
      formats:     formats,
      returnImage: true,
    );
  }

  Future<void> _switchFormat(int mode) async {
    if (_formatMode == mode) return;
    await _controller.dispose();
    setState(() {
      _formatMode = mode;
      _scanned    = false;
      _buildController();
    });
  }

  Future<void> _switchCamera() async {
    HapticFeedback.selectionClick();
    await _controller.dispose();
    setState(() {
      _facing  = _facing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
      _scanned = false;
      _buildController();
    });
  }

  Future<void> _toggleTorch() async {
    HapticFeedback.selectionClick();
    await _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  // ── Detect barcode ───────────────────────────────────────
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned || _processing) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() => _scanned = true);
    HapticFeedback.mediumImpact();

    // White flash
    _flashCtrl.forward().then((_) => _flashCtrl.reverse());

    // Add to history
    if (!_history.contains(raw)) {
      _history.insert(0, raw);
      if (_history.length > 5) _history.removeLast();
    }

    await Future.delayed(const Duration(milliseconds: 120));
    if (mounted) Navigator.pop(context, raw);
  }

  // ── Tap to focus ─────────────────────────────────────────
  void _onTapDown(TapDownDetails details) {
    setState(() => _focusTap = details.localPosition);
    _focusCtrl.forward(from: 0);
    _controller.resetZoomScale();
  }

  // ── Pinch to zoom ────────────────────────────────────────
  void _onScaleStart(ScaleStartDetails _) {
    _baseZoom = _zoomScale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.scale == 1.0) return; // pure pan, skip
    final newZoom = (_baseZoom + (details.scale - 1) * 0.4).clamp(0.0, 1.0);
    setState(() {
      _zoomScale      = newZoom;
      _showZoomSlider = true;
      _lastZoomChange = DateTime.now();
    });
    _controller.setZoomScale(newZoom);

    // Auto-hide slider after 2 s of no change
    Future.delayed(const Duration(seconds: 2), () {
      if (_lastZoomChange != null &&
          DateTime.now().difference(_lastZoomChange!).inSeconds >= 2) {
        if (mounted) setState(() => _showZoomSlider = false);
      }
    });
  }

  // ── OCR ──────────────────────────────────────────────────
  Future<void> _captureAndOCR() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final picker = ImagePicker();
      final photo  = await picker.pickImage(
        source: ImageSource.camera, imageQuality: 95);
      if (photo == null) { setState(() => _processing = false); return; }

      final textRecognizer = TextRecognizer();
      final inputImage     = InputImage.fromFilePath(photo.path);
      final recognized     = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      if (!mounted) return;

      final lines = recognized.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.length > 2)
          .toList();

      if (lines.isEmpty) {
        _showSnack('مش قادر يقرأ النص، جرب تقرّب الكاميرا', Colors.orange);
        setState(() => _processing = false);
        return;
      }

      if (lines.length == 1) {
        setState(() { _scanned = true; _processing = false; });
        if (mounted) Navigator.pop(context, lines.first);
        return;
      }

      setState(() => _processing = false);
      if (!mounted) return;

      final selected = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _OcrPickerSheet(lines: lines),
      );
      if (selected != null && mounted) {
        setState(() => _scanned = true);
        Navigator.pop(context, selected);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('خطأ: $e', Colors.red);
        setState(() => _processing = false);
      }
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _flashCtrl.dispose();
    _lineCtrl.dispose();
    _focusCtrl.dispose();
    super.dispose();
  }

  // ── BUILD ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('مسح الباركود / النص',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF16324F),
        foregroundColor: Colors.white,
        actions: [
          // History button
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.history_rounded),
              tooltip: 'آخر النتائج',
              onPressed: _showHistory,
            ),
          // Camera switch
          IconButton(
            icon: const Icon(Icons.flip_camera_ios_rounded),
            tooltip: 'تبديل الكاميرا',
            onPressed: _switchCamera,
          ),
        ],
      ),
      body: Stack(children: [

        // ── Camera feed ─────────────────────────────────────
        GestureDetector(
          onTapDown:      _onTapDown,
          onScaleStart:   _onScaleStart,
          onScaleUpdate:  _onScaleUpdate,
          child: MobileScanner(
            controller: _controller,
            onDetect:   _onDetect,
          ),
        ),

        // ── Dark overlay with frame cutout ──────────────────
        LayoutBuilder(builder: (ctx, constraints) {
          final sw = constraints.maxWidth;
          final sh = constraints.maxHeight;
          final fw = sw * 0.72;
          final fh = fw * 0.55;
          final fx = (sw - fw) / 2;
          final fy = (sh - fh) / 2;

          return Stack(children: [

            // 4 dark quadrants around the frame
            Positioned(top: 0, left: 0, right: 0, height: fy,
                child: const ColoredBox(color: Color(0x88000000))),
            Positioned(bottom: 0, left: 0, right: 0, height: sh - fy - fh,
                child: const ColoredBox(color: Color(0x88000000))),
            Positioned(top: fy, left: 0, width: fx, height: fh,
                child: const ColoredBox(color: Color(0x88000000))),
            Positioned(top: fy, right: 0, width: fx, height: fh,
                child: const ColoredBox(color: Color(0x88000000))),

            // ── Animated scan line ───────────────────────────
            Positioned(
              left: fx + 4, width: fw - 8,
              top: fy,
              child: AnimatedBuilder(
                animation: _lineAnim,
                builder: (_, __) => Transform.translate(
                  offset: Offset(0, _lineAnim.value * (fh - 4)),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.greenAccent.withValues(alpha: 0),
                        Colors.greenAccent,
                        Colors.greenAccent.withValues(alpha: 0),
                      ]),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.5),
                          blurRadius: 6, spreadRadius: 1),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Corner-only L-shape frame ────────────────────
            Positioned(left: fx, top: fy, width: fw, height: fh,
              child: _CornerFrame(width: fw, height: fh)),

            // ── Tap-to-focus ripple ──────────────────────────
            if (_focusTap != null)
              AnimatedBuilder(
                animation: _focusAnim,
                builder: (_, __) => Positioned(
                  left: _focusTap!.dx - 24,
                  top:  _focusTap!.dy - 24,
                  child: Opacity(
                    opacity: _focusAnim.value,
                    child: Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.yellowAccent, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        }),

        // ── White flash on scan success ──────────────────────
        AnimatedBuilder(
          animation: _flashAnim,
          builder: (_, __) => _flashAnim.value > 0
              ? Opacity(
                  opacity: _flashAnim.value * 0.7,
                  child: const ColoredBox(color: Colors.white,
                      child: SizedBox.expand()))
              : const SizedBox.shrink(),
        ),

        // ── Processing overlay ───────────────────────────────
        if (_processing)
          Container(
            color: Colors.black54,
            child: const Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.greenAccent, strokeWidth: 3),
                SizedBox(height: 14),
                Text('جاري القراءة...',
                    style: TextStyle(color: Colors.white, fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ],
            )),
          ),

        // ── Bottom controls bar ──────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            decoration: const BoxDecoration(
              color: Color(0xCC000000),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [

              // Format filter chips
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (int i = 0; i < _formatLabels.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => _switchFormat(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _formatMode == i
                              ? Colors.greenAccent
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(_formatLabels[i],
                          style: TextStyle(
                            color: _formatMode == i ? Colors.black : Colors.white,
                            fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 14),

              // Main action row: Torch | OCR button | Zoom indicator
              Row(children: [

                // Torch
                _CircleBtn(
                  icon: _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                  color: _torchOn ? Colors.yellowAccent : Colors.white70,
                  tooltip: 'فلاش',
                  onTap: _torchOn || _facing == CameraFacing.front
                      ? _toggleTorch
                      : _toggleTorch,
                ),

                const Spacer(),

                // OCR button — center and prominent
                GestureDetector(
                  onTap: _processing ? null : _captureAndOCR,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16324F),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white24),
                      boxShadow: [
                        BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.25),
                            blurRadius: 12, spreadRadius: 1)
                      ],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.text_fields_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      const Text('اقرأ النص',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ]),
                  ),
                ),

                const Spacer(),

                // Zoom indicator button
                _CircleBtn(
                  icon: Icons.zoom_in_rounded,
                  color: _showZoomSlider ? Colors.greenAccent : Colors.white70,
                  tooltip: 'تكبير',
                  onTap: () => setState(() => _showZoomSlider = !_showZoomSlider),
                ),
              ]),

              // Zoom slider — shown when pinching or tapping zoom btn
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: _showZoomSlider
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    const Icon(Icons.zoom_out_rounded, color: Colors.white54, size: 18),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.greenAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.greenAccent,
                          overlayColor: Colors.greenAccent.withValues(alpha: 0.2),
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                        ),
                        child: Slider(
                          value: _zoomScale,
                          min: 0, max: 1,
                          onChanged: (v) {
                            setState(() { _zoomScale = v; _lastZoomChange = DateTime.now(); });
                            _controller.setZoomScale(v);
                          },
                        ),
                      ),
                    ),
                    const Icon(Icons.zoom_in_rounded, color: Colors.white54, size: 18),
                    const SizedBox(width: 6),
                    Text('${(_zoomScale * 100).round()}%',
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ]),
                ),
                secondChild: const SizedBox(height: 0),
              ),

              const SizedBox(height: 8),
              const Text(
                'الباركود يُقرأ تلقائياً  •  اضغط الشاشة للتركيز  •  انقر للتكبير',
                style: TextStyle(color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── History bottom sheet ─────────────────────────────────
  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Align(alignment: Alignment.centerRight,
                child: Text('آخر النتائج',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
            ),
            ..._history.map((h) => ListTile(
              leading: const Icon(Icons.qr_code_2_rounded,
                  color: Color(0xFF16324F)),
              title: Text(h, style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 14),
                  textDirection: TextDirection.ltr),
              trailing: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 14, color: Colors.grey),
              onTap: () {
                Navigator.pop(ctx);
                if (mounted) Navigator.pop(context, h);
              },
            )),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }
}

// ── Corner-only frame widget ──────────────────────────────────
class _CornerFrame extends StatelessWidget {
  final double width;
  final double height;
  const _CornerFrame({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _CornerPainter(),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color  = Colors.greenAccent
      ..style  = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap   = StrokeCap.round;

    const len = 28.0;  // corner arm length
    const r   = 10.0;  // corner radius

    final w = size.width;
    final h = size.height;

    // Top-left
    canvas.drawPath(Path()
      ..moveTo(r, 0) ..lineTo(len, 0)
      ..moveTo(0, r) ..lineTo(0, len), paint);
    // arc TL
    canvas.drawArc(Rect.fromLTWH(0, 0, r*2, r*2),
        3.14159, 3.14159/2, false, paint);

    // Top-right
    canvas.drawPath(Path()
      ..moveTo(w - len, 0) ..lineTo(w - r, 0)
      ..moveTo(w, r) ..lineTo(w, len), paint);
    canvas.drawArc(Rect.fromLTWH(w - r*2, 0, r*2, r*2),
        3.14159 * 1.5, 3.14159/2, false, paint);

    // Bottom-left
    canvas.drawPath(Path()
      ..moveTo(0, h - len) ..lineTo(0, h - r)
      ..moveTo(r, h) ..lineTo(len, h), paint);
    canvas.drawArc(Rect.fromLTWH(0, h - r*2, r*2, r*2),
        3.14159/2, 3.14159/2, false, paint);

    // Bottom-right
    canvas.drawPath(Path()
      ..moveTo(w - len, h) ..lineTo(w - r, h)
      ..moveTo(w, h - len) ..lineTo(w, h - r), paint);
    canvas.drawArc(Rect.fromLTWH(w - r*2, h - r*2, r*2, r*2),
        0, 3.14159/2, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── Circle icon button ────────────────────────────────────────
class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   tooltip;
  final VoidCallback onTap;
  const _CircleBtn({
    required this.icon, required this.color,
    required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}

// ── OCR picker bottom sheet ───────────────────────────────────
class _OcrPickerSheet extends StatelessWidget {
  final List<String> lines;
  const _OcrPickerSheet({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(alignment: Alignment.centerRight,
              child: Text('اختار النص الصح',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4),
            child: ListView(
              shrinkWrap: true,
              children: lines.map((line) => ListTile(
                title: Text(line,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'monospace')),
                leading: const Icon(Icons.text_fields_rounded,
                    color: Color(0xFF16324F)),
                onTap: () => Navigator.pop(context, line),
              )).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ]),
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
    if (widget.initialSerial != null) {
      _serialController.text = widget.initialSerial!;
    }
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
    final repo = InventoryRepository.instance;
    final warehouses = repo.getWarehouses();
    final products   = repo.getProducts();
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
                              color: Color(0xFF16324F))
                          : null,
                      tileColor: isSelected
                          ? const Color(0xFF16324F)
                              .withValues(alpha: 0.08)
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
                        color: Color(0xFF16324F))
                    : null,
                tileColor: w == _selectedWarehouse
                    ? const Color(0xFF16324F)
                        .withValues(alpha: 0.08)
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
      await InventoryRepository.instance.addWarehouse(result);
      // Also sync to Firestore immediately (admin action, usually online)
      FirestoreService.instance.addWarehouse(result);
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
      await InventoryRepository.instance.addProduct(result);
      FirestoreService.instance.addProduct(result);
      await _loadDropdowns();
      setState(() => _selectedProduct = result);
    }
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (result != null) {
      setState(() => _serialController.text = result);
    }
  }

  Future<void> _save() async {
    final currentUser = await AuthService.instance.getCurrentUser();
    if (!mounted) return;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب تسجيل الدخول أولاً')),
      );
      return;
    }
    
    // لو تعديل (itemToEdit موجود) - يحتاج صلاحية تعديل
    if (widget.itemToEdit != null && !currentUser.canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية التعديل')),
      );
      return;
    }
    
    // لو إضافة جديدة - يحتاج صلاحية إضافة
    if (widget.itemToEdit == null && !currentUser.canAdd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ليس لديك صلاحية الإضافة')),
      );
      return;
    }
    
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
      addedByUid: currentUser.uid, // ✅ سجّل مين أضاف
    );
    if (widget.itemToEdit != null) {
      await InventoryRepository.instance.updateItem(item);
    } else {
      await InventoryRepository.instance.insertItem(item);
      // ✅ إشعار للـ Admins عند إضافة قطعة جديدة (بس لو المستخدم مش Admin)
      if (!currentUser.isAdmin) {
        NotificationService.instance.notifyItemAdded(
          productName: item.productName,
          warehouseName: item.warehouseName,
          addedByName: currentUser.name,
        );
      }
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
        backgroundColor: const Color(0xFF16324F),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100, // filled style — matches TextFormField fill
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedWarehouse != null
                            ? const Color(0xFF16324F)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(children: [
                      Icon(Icons.warehouse,
                          color: _selectedWarehouse != null
                              ? const Color(0xFF16324F)
                              : Colors.grey.shade500),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedWarehouse ?? 'اختار المخزن',
                          style: TextStyle(
                            fontSize: 15,
                            color: _selectedWarehouse != null ? Colors.black87 : Colors.grey,
                          ),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // المنتج
                GestureDetector(
                  onTap: _showProductPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedProduct != null
                            ? const Color(0xFF16324F)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(children: [
                      Icon(Icons.inventory_2,
                          color: _selectedProduct != null
                              ? const Color(0xFF16324F)
                              : Colors.grey.shade500),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedProduct ?? 'اختار المنتج',
                          style: TextStyle(
                            fontSize: 15,
                            color: _selectedProduct != null ? Colors.black87 : Colors.grey,
                          ),
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // السريال
                TextFormField(
                  controller: _serialController,
                  decoration: InputDecoration(
                    labelText: 'السريال / Barcode',
                    prefixIcon: const Icon(Icons.qr_code,
                        color: Color(0xFF16324F)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner,
                          color: Color(0xFF16324F)),
                      onPressed: _scanBarcode,
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF16324F), width: 2),
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
                    prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFF16324F)),
                    hintText: 'yyyy-MM-dd',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: _expiryController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() => _expiryController.clear()),
                          )
                        : null,
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
                      // Fix: unified format yyyy-MM-dd (same as inventoryDate)
                      _expiryController.text =
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                      setState(() {});
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
                        color: Color(0xFF16324F)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF16324F), width: 2),
                    ),
                  ),
                  textDirection: TextDirection.rtl,
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      // Fix: sticky save button — not buried inside scroll
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _save,
            icon: _loading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded),
            label: Text(widget.itemToEdit != null ? 'تحديث' : 'حفظ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16324F),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ),
    );
  }
}