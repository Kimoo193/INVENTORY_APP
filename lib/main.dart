import 'package:flutter/material.dart';
import 'firestore_service.dart';
import 'migration_screen.dart' show MigrationScreen;
import 'scanner_screen.dart';
import 'inventory_screen.dart';
import 'export_helper.dart';
import 'manage_screen.dart';
import 'import_screen.dart';
import 'delete_dialog.dart';
import 'deleted_items_screen.dart';
import 'users_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'auth_wrapper.dart';
import 'auth_service.dart';
import 'notification_service.dart'; // ✅ جديد

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // ✅ تهيئة Local Notifications (Channel + Plugin)
  await NotificationService.instance.initialize();
  runApp(const InventoryApp());
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A237E),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.inventory_2,
                    size: 70, color: Color(0xFF1A237E)),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Karam Stock',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: Colors.white24),
              ),
              child: const Text(
                '🤍  اللهم صلِّ وسلم على نبينا محمد  🤍',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text(
                'BY : Kareem Mohamed',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Karam Stock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: const Color(0xFF1A237E)),
        useMaterial3: true,
      ),
      home: AuthWrapper(authenticatedHome: const HomeScreen()),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, int> _stats = {
    'total': 0,
    'good': 0,
    'used': 0,
    'damaged': 0
  };
  List<String> _dates = [];
  String? _selectedDate;
  bool _showAllDates = false;
  AppUser? _currentUser;

  bool get _isAdmin =>
      _currentUser?.role == 'admin' || _currentUser?.role == 'superadmin';

  String _roleLabel(String? role) {
    switch (role) {
      case 'superadmin':
        return '\u{1F451} Super Admin';
      case 'admin':
        return '\u{1F511} مدير';
      default:
        return '\u{1F464} مستخدم';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadData();
  }

  Future<void> _loadCurrentUser() async {
    final user = await AuthService.instance.getCurrentUser();
    if (mounted) setState(() => _currentUser = user);
  }

  Future<void> _loadData() async {
    // ✅ تحقق لو في migration محتاج يتعمل
    final isMigrated = await FirestoreService.instance.isMigrated();
    if (!isMigrated && mounted) {
      final user = await AuthService.instance.getCurrentUser();
      if (user != null && user.isAdmin) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MigrationScreen()),
        );
        if (result != true) return; // لو ما اتعملش migration نوقف
      }
    }
    final dates = await FirestoreService.instance.getInventoryDates();
    final today = InventoryItem.today();
    if (!dates.contains(today)) dates.insert(0, today);
    final selected = _selectedDate ?? today;
    final stats = await FirestoreService.instance.getStats(date: selected);
    setState(() {
      _dates = dates;
      _selectedDate ??= today;
      _stats = stats;
    });
  }

  Future<void> _refreshStats() async {
    final stats = await FirestoreService.instance.getStats(date: _selectedDate);
    setState(() => _stats = stats);
  }

  Future<void> _addItem() async {
    if (_currentUser != null && !_currentUser!.canAdd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('مش عندك صلاحية الإضافة'),
            backgroundColor: Colors.red),
      );
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              AddItemScreen(selectedDate: _selectedDate)),
    );
    if (result == true) _loadData();
  }

  String _formatDate(String date) {
    final parts = date.split('-');
    if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    return date;
  }

  bool _isToday(String date) => date == InventoryItem.today();

  // ✅ تأكيد تسجيل الخروج
  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تسجيل الخروج'),
          content: const Text('هتخرج من حسابك؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white),
              child: const Text('خروج'),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      await AuthService.instance.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Karam Stock',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 17)),
            if (_currentUser != null)
              Text(
                '${_currentUser!.name}  ${_roleLabel(_currentUser!.role)}',
                style: const TextStyle(
                    fontSize: 11, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) async {
              switch (val) {
                case 'deleted':
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const DeletedItemsScreen()));
                  break;
                case 'users':
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const UsersScreen()));
                  break;
                case 'import':
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ImportScreen()),
                  );
                  _loadData();
                  break;
                case 'manage':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ManageScreen()),
                  );
                  break;
                case 'excel_today':
                  if (_selectedDate == null) return;
                  final items = await FirestoreService.instance
                      .getItemsByDate(_selectedDate!);
                  if (items.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('لا توجد بيانات في هذا اليوم')));
                    return;
                  }
                  ExportHelper.exportToExcel(items, _selectedDate);
                  break;
                case 'excel_all':
                  final items =
                      await FirestoreService.instance.getAllItems();
                  if (items.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('لا توجد بيانات')));
                    return;
                  }
                  ExportHelper.exportToExcel(items, null);
                  break;
                case 'logout':
                  await _confirmLogout(); // ✅ مع تأكيد
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                  value: 'deleted',
                  child: Row(children: [
                    Icon(Icons.delete_sweep, size: 20),
                    SizedBox(width: 12),
                    Text('سجل الحذف')
                  ])),
              if (_isAdmin)
                const PopupMenuItem(
                    value: 'users',
                    child: Row(children: [
                      Icon(Icons.people, size: 20),
                      SizedBox(width: 12),
                      Text('إدارة المستخدمين')
                    ])),
              const PopupMenuItem(
                  value: 'import',
                  child: Row(children: [
                    Icon(Icons.upload_file, size: 20),
                    SizedBox(width: 12),
                    Text('استيراد البيانات')
                  ])),
              const PopupMenuItem(
                  value: 'manage',
                  child: Row(children: [
                    Icon(Icons.settings, size: 20),
                    SizedBox(width: 12),
                    Text('إدارة القوائم')
                  ])),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'excel_today',
                  child: Row(children: [
                    Icon(Icons.table_chart,
                        size: 20, color: Colors.green),
                    SizedBox(width: 12),
                    Text('Excel - اليوم المحدد')
                  ])),
              const PopupMenuItem(
                  value: 'excel_all',
                  child: Row(children: [
                    Icon(Icons.table_chart_outlined,
                        size: 20, color: Colors.blue),
                    SizedBox(width: 12),
                    Text('Excel - كل الأيام')
                  ])),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [
                    Icon(Icons.logout, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('تسجيل الخروج',
                        style: TextStyle(color: Colors.red))
                  ])),
            ],
          ),
        ],
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // تبويبات التواريخ
            Container(
              color: const Color(0xFF1A237E),
              child: Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      itemCount: _showAllDates
                          ? _dates.length
                          : (_dates.length > 5 ? 5 : _dates.length),
                      itemBuilder: (_, i) {
                        final date = _dates[i];
                        final isSelected = date == _selectedDate;
                        return GestureDetector(
                          onTap: () async {
                            setState(() => _selectedDate = date);
                            _refreshStats();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white24,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _isToday(date) ? 'اليوم' : _formatDate(date),
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF1A237E)
                                    : Colors.white,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_dates.length > 5)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showAllDates = !_showAllDates),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _showAllDates
                              ? '▲ أقل'
                              : '▼ كل التواريخ (${_dates.length})',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // الإحصائيات
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(
                  vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(children: [
                _statCard('الإجمالي', _stats['total']!,
                    const Color(0xFF1A237E), Icons.inventory_2),
                _divider(),
                _statCard('جديد', _stats['good']!, Colors.green,
                    Icons.check_circle),
                _divider(),
                _statCard('مستخدم', _stats['used']!, Colors.orange,
                    Icons.refresh),
                _divider(),
                _statCard(
                    'تالف', _stats['damaged']!, Colors.red, Icons.warning),
              ]),
            ),

            // القائمة
            Expanded(
              child: InventoryScreen(
                selectedDate: _selectedDate,
                onRefresh: _refreshStats,
                currentUser: _currentUser, // ✅ نبعت المستخدم الحالي
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          (_currentUser == null || _currentUser!.canAdd)
              ? FloatingActionButton.extended(
                  onPressed: _addItem,
                  backgroundColor: const Color(0xFF1A237E),
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة قطعة'),
                )
              : null,
    );
  }

  Widget _statCard(
      String label, int value, Color color, IconData icon) {
    return Expanded(
      child: Column(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(value.toString(),
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }

  Widget _divider() => Container(
      width: 1, height: 40, color: Colors.grey.shade200);
}