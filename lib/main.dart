import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firestore_service.dart';
import 'migration_screen.dart' show MigrationScreen;
import 'scanner_screen.dart';
import 'inventory_screen.dart';
import 'export_helper.dart';
import 'manage_screen.dart';
import 'import_screen.dart';
import 'deleted_items_screen.dart';
import 'users_screen.dart';
import 'super_admin_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'auth_wrapper.dart';
import 'auth_service.dart';
import 'log_service.dart';
import 'notification_service.dart';
import 'app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.initialize();
  runApp(const InventoryApp());
}

// ============================================================
// App Root
// ============================================================
class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF16324F),
      primary: const Color(0xFF16324F),
      secondary: const Color(0xFFC69749),
      surface: Colors.white,
    );

    return MaterialApp(
      title: 'Karam Stock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F4EE),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF16324F),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: const Color(0xFF16324F).withValues(alpha: 0.10)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: const Color(0xFF16324F).withValues(alpha: 0.10)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF16324F), width: 1.4),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF16324F),
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: AuthWrapper(authenticatedHome: const HomeScreen()),
    );
  }
}

// ============================================================
// HomeScreen
// ============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, int> _stats = {'total': 0, 'good': 0, 'used': 0, 'damaged': 0};
  List<String> _dates = [];
  String? _selectedDate;
  bool _showAllDates = false;
  AppUser? _currentUser;
  AppLanguage _lang = AppLocalizations.current;

  bool get _isAdmin =>
      _currentUser?.role == 'admin' || _currentUser?.role == 'superadmin';

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
    // ✅ تصليح: migration لا يوقف التطبيق
    try {
      final isMigrated = await FirestoreService.instance.isMigrated();
      if (!isMigrated && mounted) {
        final user = await AuthService.instance.getCurrentUser();
        if (!mounted) return;
        if (user != null && user.isAdmin) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MigrationScreen()),
          );
        }
      }
    } catch (_) {}

    final dates = await FirestoreService.instance.getInventoryDates();
    final today = InventoryItem.today();
    if (!dates.contains(today)) dates.insert(0, today);
    final stats = await FirestoreService.instance.getStats(date: _selectedDate ?? today);
    if (mounted) {
      setState(() {
        _dates = dates;
        _selectedDate ??= today;
        _stats = stats;
      });
    }
  }

  Future<void> _refreshStats() async {
    final stats = await FirestoreService.instance.getStats(date: _selectedDate);
    if (mounted) setState(() => _stats = stats);
  }

  Future<void> _addItem() async {
    if (_currentUser != null && !_currentUser!.canAdd) {
      _showSnack(AppLocalizations.noPermissionAdd, Colors.red);
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddItemScreen(selectedDate: _selectedDate)),
    );
    if (result == true) _loadData();
  }

  String _formatDate(String date) {
    final p = date.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : date;
  }

  bool _isToday(String date) => date == InventoryItem.today();

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  // ============================================================
  // ✅ Clear Day — Admin يمسح كل مخزون يوم معين
  // ============================================================
  Future<void> _clearDay(String date) async {
    if (!_isAdmin) return;

    // جيب عدد القطع أولاً
    final count = await FirestoreService.instance.getItemsCountByDate(date);
    if (!mounted) return;

    if (count == 0) {
      _showSnack(
        AppLocalizations.isArabic ? 'لا توجد قطع في هذا اليوم' : 'No items on this day',
        Colors.orange,
      );
      return;
    }

    // Confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppLocalizations.isArabic ? 'مسح مخزون اليوم' : 'Clear Day Inventory',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16324F).withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF16324F).withValues(alpha: 0.12),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _formatDate(date),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: Color(0xFF16324F),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$count ${AppLocalizations.isArabic ? "قطعة" : "items"}',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                AppLocalizations.isArabic
                    ? 'القطع هتتنقل لسجل الحذف وتقدر تستعيدها منه.\nمش هيتحذفوا نهائياً.'
                    : 'Items will be moved to the delete log and can be restored.\nThey will NOT be permanently deleted.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.cancel),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: Text(
                AppLocalizations.isArabic ? 'مسح الكل' : 'Clear All',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    // Progress indicator
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(AppLocalizations.isArabic ? 'جاري المسح...' : 'Clearing...'),
          ],
        ),
        duration: const Duration(seconds: 30),
        backgroundColor: const Color(0xFF16324F),
      ),
    );

    final currentUser = await AuthService.instance.getCurrentUser();
    final deleted = await FirestoreService.instance.clearItemsByDate(
      date,
      deletedByUid: currentUser?.uid,
    );

    messenger.clearSnackBars();
    if (!mounted) return;

    if (deleted < 0) {
      _showSnack(
        AppLocalizations.isArabic ? 'حدث خطأ أثناء المسح' : 'Error while clearing',
        Colors.red,
      );
      return;
    }

    _showSnack(
      AppLocalizations.isArabic
          ? 'تم نقل $deleted قطعة لسجل الحذف ✅'
          : 'Moved $deleted items to delete log ✅',
      Colors.green,
    );

    // Refresh
    await _loadData();
    // لو اليوم المحذوف كان selected والقطع فيه وصلت 0، انتقل لـ today
    if (_dates.isNotEmpty && !_dates.contains(date)) {
      setState(() => _selectedDate = _dates.first);
    }
    await _refreshStats();
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(AppLocalizations.logoutTitle),
          content: Text(AppLocalizations.logoutConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: Text(AppLocalizations.cancel)),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: Text(AppLocalizations.logoutYes),
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      // ✅ Log logout قبل الخروج
      if (_currentUser != null) {
        try {
          await LogService.instance.logLogout(_currentUser!);
        } catch (_) {}
      }
      // ✅ logout — AuthWrapper هيسمع authStateChanges تلقائياً ويعمل redirect
      await AuthService.instance.logout();
    }
  }

  void _toggleLanguage() {
    HapticFeedback.lightImpact();
    setState(() {
      AppLocalizations.toggle();
      _lang = AppLocalizations.current;
    });
  }

  String _roleLabel() {
    if (_currentUser?.isSuperAdmin == true) {
      return AppLocalizations.superAdmin;
    }
    if (_currentUser?.isAdmin == true) {
      return AppLocalizations.admin;
    }
    return AppLocalizations.userRole;
  }

  Color _roleTint() {
    if (_currentUser?.isSuperAdmin == true) {
      return const Color(0xFFC69749);
    }
    if (_currentUser?.isAdmin == true) {
      return const Color(0xFF4FC3F7);
    }
    return const Color(0xFF4DB6AC);
  }

  // ============================================================
  // Beautiful Menu Bottom Sheet
  // ============================================================
  void _showMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (bsCtx) => _MenuSheet(
        isAdmin: _isAdmin,
        currentUser: _currentUser,
        lang: _lang,
        onToggleLanguage: _toggleLanguage,
        onNavigate: (widget) async {
          Navigator.pop(bsCtx);
          await Navigator.push(context, MaterialPageRoute(builder: (_) => widget));
          _loadData();
        },
        onExportToday: () async {
          Navigator.pop(bsCtx);
          if (_selectedDate == null) return;
          final items = await FirestoreService.instance.getItemsByDate(_selectedDate!);
          if (items.isEmpty) { _showSnack(AppLocalizations.noDataToday, Colors.orange); return; }
          ExportHelper.exportToExcel(items, _selectedDate);
        },
        onExportAll: () async {
          Navigator.pop(bsCtx);
          final items = await FirestoreService.instance.getAllItems();
          if (items.isEmpty) { _showSnack(AppLocalizations.noData, Colors.orange); return; }
          ExportHelper.exportToExcel(items, null);
        },
        onLogout: () async {
          Navigator.pop(bsCtx); // ✅ أغلق الـ sheet أولاً
          await Future.delayed(const Duration(milliseconds: 300));
          if (mounted) _confirmLogout();
        },
      ),
    );
  }

  // ============================================================
  // Build
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final total = _stats['total'] ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: _buildAppBar(),
      body: Directionality(
        textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Container(
          color: const Color(0xFFF5F5F7),
          child: Column(
            children: [
              _buildDateTabs(),
              _buildStatsCards(total),
              // ✅ Clear Day button — Admin only, shown when date selected & items exist
              if (_isAdmin && _selectedDate != null && (total > 0))
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: InkWell(
                    onTap: () => _clearDay(_selectedDate!),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Text(
                            AppLocalizations.isArabic
                                ? 'مسح مخزون هذا اليوم ($total قطعة)'
                                : 'Clear this day\'s inventory ($total items)',
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: InventoryScreen(
                  selectedDate: _selectedDate,
                  onRefresh: _refreshStats,
                  currentUser: _currentUser,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: (_currentUser == null || _currentUser!.canAdd)
          ? FloatingActionButton.extended(
              onPressed: _addItem,
              backgroundColor: const Color(0xFF16324F),
              foregroundColor: Colors.white,
              elevation: 2,
              extendedPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                AppLocalizations.addItem,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  AppBar _buildAppBar() {
    final roleTint = _roleTint();
    return AppBar(
      backgroundColor: const Color(0xFF16324F),
      foregroundColor: Colors.white,
      elevation: 0,
      toolbarHeight: 82,
      titleSpacing: 16,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      title: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Center(
              child: Text(
                _currentUser?.name.isNotEmpty == true
                    ? _currentUser!.name[0].toUpperCase()
                    : 'K',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Karam Stock',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _currentUser?.name ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ),
                    if (_currentUser != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: roleTint.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: roleTint.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          _roleLabel(),
                          style: TextStyle(
                            color: roleTint,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: _toggleLanguage,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 18),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Center(
                child: Text(
                  AppLocalizations.isArabic ? 'EN' : 'عر',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: _showMenu,
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _buildDateTabs() {
    final visibleDates = _showAllDates ? _dates : _dates.take(5).toList();
    final selectedLabel = _selectedDate == null
        ? AppLocalizations.today
        : (_isToday(_selectedDate!) ? AppLocalizations.today : _formatDate(_selectedDate!));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF16324F), Color(0xFF23476B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF16324F).withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.isArabic ? 'الفترة المعروضة' : 'Visible Snapshot',
                          style: const TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${_dates.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          AppLocalizations.isArabic ? 'يوم' : 'dates',
                          style: const TextStyle(color: Colors.white60, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 58,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: visibleDates.length,
                itemBuilder: (_, i) {
                  final date = visibleDates[i];
                  final isSelected = date == _selectedDate;
                  final isToday = _isToday(date);
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedDate = date);
                      _refreshStats();
                    },
                    onLongPress: _isAdmin
                        ? () {
                            HapticFeedback.heavyImpact();
                            setState(() => _selectedDate = date);
                            _clearDay(date);
                          }
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.14),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isToday)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFC69749) : Colors.white70,
                                shape: BoxShape.circle,
                              ),
                            ),
                          Text(
                            isToday ? AppLocalizations.today : _formatDate(date),
                            style: TextStyle(
                              color: isSelected ? const Color(0xFF16324F) : Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          // ✅ إشارة للـ Admin إن في long-press action
                          if (_isAdmin && isSelected) ...[
                            const SizedBox(width: 5),
                            Icon(
                              Icons.delete_sweep_rounded,
                              size: 13,
                              color: const Color(0xFF16324F).withValues(alpha: 0.45),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_dates.length > 5)
              TextButton.icon(
                onPressed: () => setState(() => _showAllDates = !_showAllDates),
                icon: Icon(
                  _showAllDates ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                label: Text(
                  _showAllDates
                      ? (AppLocalizations.isArabic ? 'عرض أقل' : 'Show Less')
                      : (AppLocalizations.isArabic
                          ? 'عرض كل التواريخ (${_dates.length})'
                          : 'Show All Dates (${_dates.length})'),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: cardWidth,
                child: _statCard(
                  AppLocalizations.total,
                  _stats['total']!,
                  total,
                  const Color(0xFF16324F),
                  Icons.inventory_2_rounded,
                  isTotal: true,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _statCard(
                  AppLocalizations.newCond,
                  _stats['good']!,
                  total,
                  const Color(0xFF2E7D32),
                  Icons.check_circle_rounded,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _statCard(
                  AppLocalizations.used,
                  _stats['used']!,
                  total,
                  const Color(0xFFC27A2C),
                  Icons.loop_rounded,
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _statCard(
                  AppLocalizations.damaged,
                  _stats['damaged']!,
                  total,
                  const Color(0xFFC62828),
                  Icons.warning_rounded,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(String label, int value, int total, Color color, IconData icon,
      {bool isTotal = false}) {
    final pct = total > 0 && !isTotal ? value / total : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 19),
              ),
              const Spacer(),
              if (pct != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${(pct * 100).round()}%',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: isTotal ? const Color(0xFF16324F) : color,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (pct != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: color.withValues(alpha: 0.10),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// Menu Bottom Sheet — Widget مستقل وجميل
// ============================================================
class _MenuSheet extends StatelessWidget {
  final bool isAdmin;
  final AppUser? currentUser;
  final AppLanguage lang;
  final VoidCallback onToggleLanguage;
  final Future<void> Function(Widget) onNavigate;
  final VoidCallback onExportToday;
  final VoidCallback onExportAll;
  final VoidCallback onLogout;

  const _MenuSheet({
    required this.isAdmin,
    required this.currentUser,
    required this.lang,
    required this.onToggleLanguage,
    required this.onNavigate,
    required this.onExportToday,
    required this.onExportAll,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = AppLocalizations.isArabic;
    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
            ),

            // Header — user info + language
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(children: [
                // User Avatar
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      currentUser?.name.isNotEmpty == true
                          ? currentUser!.name[0].toUpperCase()
                          : 'K',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(currentUser?.name ?? 'Karam Stock',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(
                      currentUser?.email ?? '',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
                ),
                // Language Toggle — EN/عر
                GestureDetector(
                  onTap: () {
                    onToggleLanguage();
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.language, color: Colors.white, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        isAr ? 'English' : 'عربي',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),

            const Divider(height: 1),

            // Menu Items

            // ✅ Super Admin Panel
            if (currentUser?.isSuperAdmin == true)
              _item(
                context,
                Icons.admin_panel_settings_rounded,
                AppLocalizations.isArabic ? 'لوحة Super Admin' : 'Super Admin Panel',
                const Color(0xFF1A237E),
                () => onNavigate(const SuperAdminScreen()),
              ),

            _item(context, Icons.delete_sweep_rounded, AppLocalizations.deleteLog,
                Colors.orange, () => onNavigate(const DeletedItemsScreen())),

            if (isAdmin)
              _item(context, Icons.people_alt_rounded, AppLocalizations.manageUsers,
                  Colors.blue, () => onNavigate(const UsersScreen())),

            _item(context, Icons.upload_file_rounded, AppLocalizations.importData,
                Colors.purple, () => onNavigate(const ImportScreen())),

            _item(context, Icons.tune_rounded, AppLocalizations.manageLists,
                Colors.teal, () => onNavigate(const ManageScreen())),

            const Divider(height: 1, indent: 20, endIndent: 20),

            // Excel exports — 2 columns side by side
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Expanded(child: _excelBtn(
                  icon: Icons.table_chart_rounded,
                  label: AppLocalizations.isArabic ? 'Excel - اليوم' : 'Excel - Today',
                  color: Colors.green,
                  onTap: onExportToday,
                )),
                const SizedBox(width: 8),
                Expanded(child: _excelBtn(
                  icon: Icons.table_chart_outlined,
                  label: AppLocalizations.isArabic ? 'Excel - الكل' : 'Excel - All',
                  color: Colors.indigo,
                  onTap: onExportAll,
                )),
              ]),
            ),

            const Divider(height: 1, indent: 20, endIndent: 20),

            // Logout
            _item(context, Icons.logout_rounded, AppLocalizations.logout,
                Colors.red, onLogout),

            // Safe area padding
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label, Color color,
      VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 18),
        ]),
      ),
    );
  }

  Widget _excelBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
    );
  }
}