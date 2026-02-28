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
import 'users_screen.dart' hide FirestoreService, InventoryItem;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'auth_wrapper.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'super_admin_screen.dart';
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
    return MaterialApp(
      title: 'Karam Stock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A237E)),
        useMaterial3: true,
        fontFamily: 'Roboto',
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
    if (confirm == true) await AuthService.instance.logout();
  }

  void _toggleLanguage() {
    HapticFeedback.lightImpact();
    setState(() {
      AppLocalizations.toggle();
      _lang = AppLocalizations.current;
    });
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
        onLogout: () { Navigator.pop(bsCtx); _confirmLogout(); },
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
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: _buildAppBar(),
      body: Directionality(
        textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Column(children: [
          _buildDateTabs(),
          _buildStatsCards(total),
          Expanded(
            child: InventoryScreen(
              selectedDate: _selectedDate,
              onRefresh: _refreshStats,
              currentUser: _currentUser,
            ),
          ),
        ]),
      ),
      floatingActionButton: (_currentUser == null || _currentUser!.canAdd)
          ? FloatingActionButton.extended(
              onPressed: _addItem,
              backgroundColor: const Color(0xFF1A237E),
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add),
              label: Text(AppLocalizations.addItem,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1A237E),
      foregroundColor: Colors.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      title: Row(children: [
        // ✅ Avatar للمستخدم
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              _currentUser?.name.isNotEmpty == true
                  ? _currentUser!.name[0].toUpperCase()
                  : 'K',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Karam Stock',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          if (_currentUser != null)
            Text(
              _currentUser!.name,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
        ]),
      ]),
      actions: [
        // ✅ Language toggle في الـ AppBar مباشرة
        GestureDetector(
          onTap: _toggleLanguage,
          child: Container(
            margin: const EdgeInsets.only(left: 4, right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white30),
            ),
            child: Text(
              AppLocalizations.isArabic ? 'EN' : 'عر',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.menu_rounded, color: Colors.white),
          onPressed: _showMenu,
        ),
      ],
    );
  }

  // ============================================================
  // Date Tabs — Chips Style
  // ============================================================
  Widget _buildDateTabs() {
    final visibleDates = _showAllDates
        ? _dates
        : _dates.take(5).toList();

    return Container(
      color: const Color(0xFF1A237E),
      child: Column(children: [
        SizedBox(
          height: 48,
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
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.white38,
                      width: 1.5,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isToday && isSelected)
                      Container(
                        width: 6, height: 6,
                        margin: const EdgeInsets.only(left: 5, right: 1),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                    Text(
                      isToday ? AppLocalizations.today : _formatDate(date),
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF1A237E) : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
        if (_dates.length > 5)
          GestureDetector(
            onTap: () => setState(() => _showAllDates = !_showAllDates),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_showAllDates ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white60, size: 16),
                const SizedBox(width: 4),
                Text(
                  _showAllDates
                      ? (AppLocalizations.isArabic ? 'أقل' : 'Less')
                      : (AppLocalizations.isArabic
                          ? 'كل التواريخ (${_dates.length})'
                          : 'All Dates (${_dates.length})'),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ]),
            ),
          ),
      ]),
    );
  }

  // ============================================================
  // Stats Cards — bigger with progress bar
  // ============================================================
  Widget _buildStatsCards(int total) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(children: [
        _statCard(AppLocalizations.total, _stats['total']!, total,
            const Color(0xFF1A237E), Icons.inventory_2_rounded, isTotal: true),
        const SizedBox(width: 8),
        _statCard(AppLocalizations.newCond, _stats['good']!, total,
            const Color(0xFF2E7D32), Icons.check_circle_rounded),
        const SizedBox(width: 8),
        _statCard(AppLocalizations.used, _stats['used']!, total,
            const Color(0xFFE65100), Icons.loop_rounded),
        const SizedBox(width: 8),
        _statCard(AppLocalizations.damaged, _stats['damaged']!, total,
            const Color(0xFFC62828), Icons.warning_rounded),
      ]),
    );
  }

  Widget _statCard(String label, int value, int total, Color color, IconData icon,
      {bool isTotal = false}) {
    final pct = total > 0 && !isTotal ? value / total : null;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2))
          ],
        ),
        child: Column(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            value.toString(),
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          Text(label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (pct != null) ...[
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 3,
                backgroundColor: color.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${(pct * 100).round()}%',
              style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.bold),
            ),
          ],
        ]),
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
            // ✅ Super Admin Dashboard — للـ Super Admin فقط
            if (currentUser?.isSuperAdmin == true)
              _item(context, Icons.admin_panel_settings_rounded,
                  'لوحة Super Admin', const Color(0xFF1A237E),
                  () => onNavigate(const SuperAdminScreen())),

            _item(context, Icons.delete_sweep_rounded, AppLocalizations.deleteLog,
                Colors.orange, () => onNavigate(const DeletedItemsScreen())),

            if (isAdmin)
              _item(context, Icons.people_alt_rounded, AppLocalizations.manageUsers,
                  Colors.blue, () => onNavigate(UsersScreen())),

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
                color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
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
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
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