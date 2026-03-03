import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'log_service.dart';
import 'firestore_service.dart' show InventoryItem;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

// ============================================================
// Super Admin Dashboard — يرى كل Admins + Users + مخازنهم
// ============================================================
class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _db = FirebaseFirestore.instance;

  List<AppUser> _admins = [];
  List<AppUser> _allUsers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final all = await AuthService.instance.getAllUsers();
      final admins = all.where((u) => u.isAdmin && !u.isSuperAdmin).toList();
      setState(() {
        _admins = admins;
        _allUsers = all.where((u) => !u.isSuperAdmin).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // ---- إنشاء Admin جديد ----
  Future<void> _showCreateAdminDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool obscure = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A237E).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.admin_panel_settings, color: Color(0xFF1A237E)),
                    ),
                    const SizedBox(width: 12),
                    const Text('إنشاء Admin جديد',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      labelText: 'الاسم',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  StatefulBuilder(builder: (_, setSub) => TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'كلمة السر',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setSub(() => obscure = !obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('إنشاء', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result != true) return;
    if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ارجاء ملء كل الحقول')));
      return;
    }

    final currentUser = await AuthService.instance.getCurrentUser();
    if (currentUser == null) return;

    if (mounted) showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      await AuthService.instance.createAdmin(
        email: emailCtrl.text.trim(),
        password: passCtrl.text,
        name: nameCtrl.text.trim(),
        createdBy: currentUser.uid,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إنشاء Admin بنجاح ✅'),
                backgroundColor: Colors.green));
      }
      _loadAll();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ---- تعديل بيانات User/Admin ----
  Future<void> _editUser(AppUser user) async {
    final nameCtrl = TextEditingController(text: user.name);
    final passCtrl = TextEditingController();
    bool obscure = true;
    bool isActive = user.isActive;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFF1A237E).withOpacity(0.1),
                      child: Text(user.isAdmin ? '🔑' : '👤',
                          style: const TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('تعديل الحساب',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        Text(user.email,
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // الاسم
                  TextField(
                    controller: nameCtrl,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      labelText: 'الاسم',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // كلمة سر جديدة (اختياري)
                  StatefulBuilder(builder: (_, setSub) => TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'كلمة سر جديدة (اختياري)',
                      hintText: 'اتركها فارغة لو مش عايز تغيير',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setSub(() => obscure = !obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  )),
                  const SizedBox(height: 12),

                  // تفعيل/تعطيل الحساب
                  StatefulBuilder(builder: (_, setSub) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(isActive ? 'الحساب مفعّل' : 'الحساب موقوف',
                        style: TextStyle(
                            color: isActive ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w600)),
                    value: isActive,
                    activeColor: Colors.green,
                    onChanged: (v) => setSub(() => isActive = v),
                  )),
                  const SizedBox(height: 16),

                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A237E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('حفظ', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result != true) return;

    if (mounted) showDialog(context: context, barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      // تحديث الاسم والـ isActive
      await _db.collection('users').doc(user.uid).update({
        'name': nameCtrl.text.trim(),
        'isActive': isActive,
      });

      // لو في كلمة سر جديدة — عمل reset
      if (passCtrl.text.isNotEmpty) {
        await _resetPassword(user.email, passCtrl.text);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم التحديث بنجاح ✅'),
                backgroundColor: Colors.green));
      }
      _loadAll();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ---- Reset Password via Firebase ----
  Future<void> _resetPassword(String email, String newPassword) async {
    FirebaseApp? tempApp;
    try {
      tempApp = await Firebase.initializeApp(
        name: 'resetApp_${DateTime.now().millisecondsSinceEpoch}',
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final cred = await tempAuth.signInWithEmailAndPassword(
          email: email, password: 'CANNOT_KNOW_OLD_PASS');
      await cred.user?.updatePassword(newPassword);
    } catch (_) {
      // لو مش عارف يعمل sign in بكلمة السر القديمة
      // بعمل generatePasswordResetEmail عوضاً
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    } finally {
      await tempApp?.delete();
    }
  }

  // ---- حذف Admin (مع تحذير) ----
  Future<void> _confirmDeleteUser(AppUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الحساب'),
          content: Text(
              'هتحذف حساب "${user.name}"؟\n\nتحذير: مش هتقدر ترجعه وكل بياناته هتتأثر!'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    await _db.collection('users').doc(user.uid).update({'isActive': false});
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إيقاف الحساب')));
    _loadAll();
  }

  // ---- عرض مخزون Admin ----
  void _viewAdminInventory(AppUser admin) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AdminInventoryView(admin: admin),
      ),
    );
  }

  // ---- عرض Logs ----
  void _viewLogs() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _ActivityLogsView()),
    );
  }

  // ============================================================
  // Build
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('لوحة تحكم Super Admin',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Text('إدارة كاملة للنظام',
                  style: TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: _viewLogs,
              tooltip: 'Activity Logs',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadAll,
              tooltip: 'تحديث',
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: [
              Tab(icon: const Icon(Icons.admin_panel_settings, size: 18),
                  text: 'Admins (${_admins.length})'),
              Tab(icon: const Icon(Icons.people, size: 18),
                  text: 'Users (${_allUsers.where((u) => !u.isAdmin).length})'),
              Tab(icon: const Icon(Icons.bar_chart, size: 18),
                  text: 'إحصائيات'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
            : TabBarView(
                controller: _tabController,
                children: [
                  _AdminsTab(
                    admins: _admins,
                    onEdit: _editUser,
                    onDelete: _confirmDeleteUser,
                    onViewInventory: _viewAdminInventory,
                  ),
                  _UsersTab(
                    users: _allUsers.where((u) => !u.isAdmin).toList(),
                    admins: _admins,
                    onEdit: _editUser,
                    onDelete: _confirmDeleteUser,
                  ),
                  _StatsTab(admins: _admins),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showCreateAdminDialog,
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.admin_panel_settings),
          label: const Text('Admin جديد', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

// ============================================================
// Admins Tab
// ============================================================
class _AdminsTab extends StatelessWidget {
  final List<AppUser> admins;
  final Function(AppUser) onEdit;
  final Function(AppUser) onDelete;
  final Function(AppUser) onViewInventory;

  const _AdminsTab({
    required this.admins,
    required this.onEdit,
    required this.onDelete,
    required this.onViewInventory,
  });

  @override
  Widget build(BuildContext context) {
    if (admins.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.admin_panel_settings_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('لا يوجد Admins',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
          const SizedBox(height: 8),
          Text('اضغط + لإضافة Admin جديد',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: admins.length,
      itemBuilder: (_, i) {
        final admin = admins[i];
        return _AdminCard(
          admin: admin,
          onEdit: () => onEdit(admin),
          onDelete: () => onDelete(admin),
          onViewInventory: () => onViewInventory(admin),
        );
      },
    );
  }
}

class _AdminCard extends StatefulWidget {
  final AppUser admin;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewInventory;

  const _AdminCard({
    required this.admin,
    required this.onEdit,
    required this.onDelete,
    required this.onViewInventory,
  });

  @override
  State<_AdminCard> createState() => _AdminCardState();
}

class _AdminCardState extends State<_AdminCard> {
  int _userCount = 0;
  int _itemCount = 0;
  int _warehouseCount = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final db = FirebaseFirestore.instance;
    try {
      // عدد المستخدمين
      final usersSnap = await db.collection('users')
          .where('adminUid', isEqualTo: widget.admin.uid).get();
      final usersSnap2 = await db.collection('users')
          .where('createdBy', isEqualTo: widget.admin.uid).get();
      final uids = <String>{};
      for (final d in [...usersSnap.docs, ...usersSnap2.docs]) {
        uids.add(d.id);
      }

      // عدد القطع
      final itemsSnap = await db.collection('inventory')
          .doc(widget.admin.uid).collection('items').count().get();

      // عدد المخازن
      final whSnap = await db.collection('inventory')
          .doc(widget.admin.uid).collection('warehouses').count().get();

      if (mounted) {
        setState(() {
          _userCount = uids.length;
          _itemCount = itemsSnap.count ?? 0;
          _warehouseCount = whSnap.count ?? 0;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: widget.admin.isActive
                  ? const Color(0xFF1A237E).withOpacity(0.05)
                  : Colors.red.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: widget.admin.isActive
                    ? const Color(0xFF1A237E).withOpacity(0.15)
                    : Colors.red.shade100,
                child: const Text('🔑', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.admin.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(widget.admin.email,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  if (!widget.admin.isActive)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                      child: Text('موقوف',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 11)),
                    ),
                ]),
              ),
              // Action buttons
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                onSelected: (v) {
                  if (v == 'edit') widget.onEdit();
                  if (v == 'delete') widget.onDelete();
                  if (v == 'inventory') widget.onViewInventory();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'inventory',
                      child: Row(children: [
                        Icon(Icons.inventory_2, size: 18, color: Color(0xFF1A237E)),
                        SizedBox(width: 8), Text('مشاهدة المخزون')])),
                  const PopupMenuItem(value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit, size: 18, color: Colors.orange),
                        SizedBox(width: 8), Text('تعديل')])),
                  const PopupMenuItem(value: 'delete',
                      child: Row(children: [
                        Icon(Icons.block, size: 18, color: Colors.red),
                        SizedBox(width: 8), Text('إيقاف/حذف',
                            style: TextStyle(color: Colors.red))])),
                ],
              ),
            ]),
          ),

          // Stats
          if (_loaded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(children: [
                _statMini(Icons.people, '$_userCount', 'مستخدم', Colors.blue),
                const SizedBox(width: 8),
                _statMini(Icons.inventory_2, '$_itemCount', 'قطعة', Colors.green),
                const SizedBox(width: 8),
                _statMini(Icons.warehouse, '$_warehouseCount', 'مخزن', Colors.orange),
                const Spacer(),
                TextButton.icon(
                  onPressed: widget.onViewInventory,
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('المخزون', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1A237E),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ]),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _statMini(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text('$value $label',
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ============================================================
// Users Tab
// ============================================================
class _UsersTab extends StatelessWidget {
  final List<AppUser> users;
  final List<AppUser> admins;
  final Function(AppUser) onEdit;
  final Function(AppUser) onDelete;

  const _UsersTab({
    required this.users,
    required this.admins,
    required this.onEdit,
    required this.onDelete,
  });

  String _getAdminName(String? adminUid) {
    if (adminUid == null) return 'غير مرتبط';
    final admin = admins.where((a) => a.uid == adminUid).firstOrNull;
    return admin?.name ?? 'غير معروف';
  }

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('لا يوجد مستخدمون',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: users.length,
      itemBuilder: (_, i) {
        final user = users[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: user.isActive
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              child: Icon(Icons.person,
                  color: user.isActive ? Colors.green : Colors.red, size: 20),
            ),
            title: Text(user.name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.email,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Row(children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('🔑 ${_getAdminName(user.adminUid ?? user.createdBy)}',
                        style: TextStyle(fontSize: 10, color: Colors.blue.shade700,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (user.assignedWarehouse != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('📦 ${user.assignedWarehouse}',
                          style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                    ),
                  ],
                ]),
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (v) {
                if (v == 'edit') onEdit(user);
                if (v == 'delete') onDelete(user);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit, size: 18, color: Colors.orange),
                      SizedBox(width: 8), Text('تعديل')])),
                const PopupMenuItem(value: 'delete',
                    child: Row(children: [
                      Icon(Icons.block, size: 18, color: Colors.red),
                      SizedBox(width: 8), Text('إيقاف',
                          style: TextStyle(color: Colors.red))])),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }
}

// ============================================================
// Stats Tab
// ============================================================
class _StatsTab extends StatefulWidget {
  final List<AppUser> admins;
  const _StatsTab({required this.admins});

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  final _db = FirebaseFirestore.instance;
  Map<String, Map<String, int>> _adminStats = {};
  int _totalUsers = 0;
  int _totalItems = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    int totalItems = 0;
    final Map<String, Map<String, int>> stats = {};

    for (final admin in widget.admins) {
      try {
        final items = await _db.collection('inventory')
            .doc(admin.uid).collection('items').count().get();
        final deleted = await _db.collection('inventory')
            .doc(admin.uid).collection('deleted_items').count().get();
        final wh = await _db.collection('inventory')
            .doc(admin.uid).collection('warehouses').count().get();
        stats[admin.uid] = {
          'items': items.count ?? 0,
          'deleted': deleted.count ?? 0,
          'warehouses': wh.count ?? 0,
        };
        totalItems += items.count ?? 0;
      } catch (_) {}
    }

    final usersSnap = await _db.collection('users')
        .where('role', isEqualTo: 'user').count().get();

    if (mounted) setState(() {
      _adminStats = stats;
      _totalItems = totalItems;
      _totalUsers = usersSnap.count ?? 0;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Overall Stats ----
          Row(children: [
            Expanded(child: _bigStat('الإجمالي', '$_totalItems', 'قطعة', Icons.inventory_2, Colors.blue)),
            const SizedBox(width: 12),
            Expanded(child: _bigStat('المستخدمون', '$_totalUsers', 'مستخدم', Icons.people, Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: _bigStat('Admins', '${widget.admins.length}', 'مدير', Icons.admin_panel_settings, Colors.orange)),
          ]),
          const SizedBox(height: 20),

          // ---- Per Admin Stats ----
          const Text('إحصائيات كل Admin:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ...widget.admins.map((admin) {
            final s = _adminStats[admin.uid];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('🔑', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(admin.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: admin.isActive
                              ? Colors.green.withOpacity(0.1)
                              : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(admin.isActive ? 'مفعّل' : 'موقوف',
                            style: TextStyle(
                                fontSize: 11,
                                color: admin.isActive ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (s != null)
                      Row(children: [
                        _miniStat('${s['items']}', 'قطعة', Colors.blue),
                        const SizedBox(width: 8),
                        _miniStat('${s['warehouses']}', 'مخزن', Colors.orange),
                        const SizedBox(width: 8),
                        _miniStat('${s['deleted']}', 'محذوف', Colors.red),
                      ])
                    else
                      const LinearProgressIndicator(),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _bigStat(String title, String value, String sub, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 2),
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _miniStat(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text('$value $label',
          style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

// ============================================================
// Admin Inventory View — Super Admin يشوف مخزون Admin معين
// ============================================================
class _AdminInventoryView extends StatefulWidget {
  final AppUser admin;
  const _AdminInventoryView({required this.admin});

  @override
  State<_AdminInventoryView> createState() => _AdminInventoryViewState();
}

class _AdminInventoryViewState extends State<_AdminInventoryView> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  List<String> _warehouses = [];
  String? _selectedWarehouse;

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    setState(() => _loading = true);
    try {
      final itemsSnap = await _db.collection('inventory')
          .doc(widget.admin.uid).collection('items')
          .orderBy('createdAt', descending: true).get();
      final whSnap = await _db.collection('inventory')
          .doc(widget.admin.uid).collection('warehouses').get();

      final items = itemsSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

      final warehouses = whSnap.docs
          .map((d) => (d.data()['name'] as String?) ?? d.id)
          .toList();

      setState(() {
        _items = items;
        _filtered = items;
        _warehouses = warehouses;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    var r = List<Map<String, dynamic>>.from(_items);
    final q = _searchCtrl.text.toLowerCase();
    if (q.isNotEmpty) {
      r = r.where((i) =>
          (i['productName'] as String? ?? '').toLowerCase().contains(q) ||
          (i['serial'] as String? ?? '').toLowerCase().contains(q) ||
          (i['warehouseName'] as String? ?? '').toLowerCase().contains(q)).toList();
    }
    if (_selectedWarehouse != null) {
      r = r.where((i) => i['warehouseName'] == _selectedWarehouse).toList();
    }
    setState(() => _filtered = r);
  }

  Color _condColor(String? c) {
    switch (c) {
      case 'جديد': return Colors.green;
      case 'مستخدم': return Colors.orange;
      case 'تالف': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مخزون: ${widget.admin.name}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            Text('${_filtered.length} قطعة',
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        body: Column(children: [
          // Search + warehouse filter
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => _applyFilter(),
                decoration: InputDecoration(
                  hintText: 'بحث...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true, fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              if (_warehouses.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _whChip('الكل', _selectedWarehouse == null,
                          () { setState(() => _selectedWarehouse = null); _applyFilter(); }),
                      ..._warehouses.map((w) => _whChip(w, _selectedWarehouse == w,
                          () { setState(() => _selectedWarehouse = w); _applyFilter(); })),
                    ],
                  ),
                ),
              ],
            ]),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('لا توجد عناصر',
                            style: TextStyle(color: Colors.grey.shade400)),
                      ]))
                    : RefreshIndicator(
                        onRefresh: _loadInventory,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) {
                            final item = _filtered[i];
                            final cc = _condColor(item['condition']);
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 1.5,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(children: [
                                  Container(width: 4, height: 48,
                                      decoration: BoxDecoration(color: cc,
                                          borderRadius: BorderRadius.circular(4))),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['productName'] ?? '',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold, fontSize: 14)),
                                      Row(children: [
                                        Icon(Icons.warehouse, size: 12, color: Colors.grey.shade500),
                                        const SizedBox(width: 3),
                                        Text(item['warehouseName'] ?? '',
                                            style: TextStyle(fontSize: 11,
                                                color: Colors.grey.shade600)),
                                      ]),
                                      if (item['serial'] != null)
                                        Text(item['serial'],
                                            style: TextStyle(fontSize: 11,
                                                color: Colors.grey.shade600)),
                                    ],
                                  )),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                        color: cc.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Text(item['condition'] ?? '',
                                        style: TextStyle(color: cc,
                                            fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                ]),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _whChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1A237E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? const Color(0xFF1A237E) : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : Colors.grey.shade700,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }
}

// ============================================================
// ============================================================
// Activity Logs View — نظام Logs يومي متكامل
// ============================================================
class _ActivityLogsView extends StatefulWidget {
  const _ActivityLogsView();
  @override
  State<_ActivityLogsView> createState() => _ActivityLogsViewState();
}

class _ActivityLogsViewState extends State<_ActivityLogsView> {
  List<Map<String, dynamic>> _dates = [];
  String? _selectedDate;
  List<Map<String, dynamic>> _logs = [];
  bool _loadingDates = true;
  bool _loadingLogs  = false;
  String _typeFilter = 'all';
  final _searchCtrl  = TextEditingController();
  String _searchQ    = '';

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDates() async {
    setState(() => _loadingDates = true);
    final dates = await LogService.instance.getLogDates();
    if (!mounted) return;
    setState(() {
      _dates = dates;
      _loadingDates = false;
    });
    // اختار اليوم الأول تلقائياً
    if (dates.isNotEmpty) {
      _selectDate(dates.first['date'] as String);
    }
  }

  void _selectDate(String dateKey) {
    setState(() => _selectedDate = dateKey);
    _loadLogs(dateKey);
  }

  Future<void> _loadLogs(String dateKey) async {
    setState(() { _loadingLogs = true; _logs = []; });
    final logs = await LogService.instance.getEventsByDate(dateKey);
    if (!mounted) return;
    setState(() { _logs = logs; _loadingLogs = false; });
  }

  // ✅ استرجاع قطعة محذوفة نهائياً من الـ Log
  Future<void> _recoverItem(Map<String, dynamic> log) async {
    final productName = log['product'] as String? ?? 'غير معروف';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(children: [
            Icon(Icons.restore_from_trash, color: Colors.blue),
            SizedBox(width: 8),
            Text('استرجاع القطعة'),
          ]),
          content: Text('هتسترجع "$productName" وتضيفها للمخزن؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('استرجاع'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    
    // ✅ أضف القطعة للمخزن مرة تانية
    final db = FirebaseFirestore.instance;
    final adminUid = log['adminUid'] as String?;
    if (adminUid == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر الاسترجاع — بيانات ناقصة')));
      return;
    }
    try {
      await db.collection('inventory').doc(adminUid).collection('items').add({
        'productName': log['product'],
        'warehouseName': log['warehouse'] ?? 'غير محدد',
        'serial': log['serial'],
        'condition': 'غير محدد',
        'notes': 'مستعاد من سجل الحذف النهائي — ${DateTime.now().toString().substring(0,16)}',
        'inventoryDate': InventoryItem.today(),
        'adminUid': adminUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم استرجاع "$productName" ✅'),
                backgroundColor: Colors.green));
        _loadLogs(_selectedDate!);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var r = _logs;
    if (_typeFilter != 'all') {
      r = r.where((l) => l['type'] == _typeFilter).toList();
    }
    if (_searchQ.isNotEmpty) {
      final q = _searchQ.toLowerCase();
      r = r.where((l) {
        return [
          l['product'] ?? '', l['warehouse'] ?? '',
          l['actorName'] ?? '', l['adminName'] ?? '',
          l['targetUserName'] ?? '', l['reason'] ?? '',
          l['typeLabel'] ?? '',
        ].join(' ').toLowerCase().contains(q);
      }).toList();
    }
    return r;
  }

  String _dateLabel(String dateKey) {
    try {
      final p = dateKey.split('-');
      if (p.length != 3) return dateKey;
      final dt = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day)
        return 'اليوم';
      final yes = now.subtract(const Duration(days: 1));
      if (dt.year == yes.year && dt.month == yes.month && dt.day == yes.day)
        return 'أمس';
      return '${p[2]}/${p[1]}';
    } catch (_) {
      return dateKey;
    }
  }

  String _timeStr(Map<String, dynamic> log) {
    try {
      final iso = log['createdAtIso'] as String?;
      if (iso == null) return '';
      final dt = DateTime.parse(iso);
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('سجل النشاط',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                _selectedDate != null
                    ? '${_filtered.length} حدث — ${_dateLabel(_selectedDate!)}'
                    : 'جاري التحميل...',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: () {
                _loadDates();
              },
            ),
          ],
        ),
        body: _loadingDates
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF1A237E)))
            : _dates.isEmpty
                ? _buildEmpty()
                : Column(children: [
                    // ---- شريط اختيار اليوم ----
                    _buildDateBar(),

                    // ---- بحث ----
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _searchQ = v),
                        decoration: InputDecoration(
                          hintText: 'بحث في الأحداث...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchQ.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQ = '');
                                  })
                              : null,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),

                    // ---- فلتر النوع ----
                    _buildTypeFilter(),

                    // ---- القائمة ----
                    Expanded(
                      child: _loadingLogs
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Color(0xFF1A237E)))
                          : _filtered.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off,
                                          size: 48,
                                          color: Colors.grey.shade300),
                                      const SizedBox(height: 12),
                                      Text('لا توجد أحداث مطابقة',
                                          style: TextStyle(
                                              color: Colors.grey.shade400)),
                                    ],
                                  ))
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 8, 12, 24),
                                  itemCount: _filtered.length,
                                  itemBuilder: (_, i) => _LogCard(
                                    log: _filtered[i],
                                    timeStr: _timeStr(_filtered[i]),
                                    onRecover: _filtered[i]['type'] == LogType.itemPermanentDeleted
                                        ? () => _recoverItem(_filtered[i])
                                        : null,
                                  ),
                                ),
                    ),
                  ]),
      ),
    );
  }

  Widget _buildDateBar() {
    return Container(
      color: Colors.white,
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _dates.length,
        itemBuilder: (_, i) {
          final d = _dates[i];
          final dateKey = d['date'] as String;
          final count   = d['count'] as int;
          final selected = dateKey == _selectedDate;
          return GestureDetector(
            onTap: () => _selectDate(dateKey),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(left: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1A237E)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: selected
                        ? const Color(0xFF1A237E)
                        : Colors.transparent),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _dateLabel(dateKey),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? Colors.white : Colors.grey.shade700,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withOpacity(0.3)
                          : const Color(0xFF1A237E).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF1A237E),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTypeFilter() {
    final filters = [
      ('الكل',          'all',                         Colors.grey.shade600),
      ('➕ إضافة',      LogType.itemAdded,              Colors.green),
      ('🗑️ حذف',       LogType.itemDeleted,            Colors.red),
      ('❌ حذف نهائي',  LogType.itemPermanentDeleted,   Colors.red.shade900),
      ('↩️ استعادة',    LogType.itemRestored,           Colors.blue),
      ('✏️ تعديل',     LogType.itemEdited,             Colors.orange),
      ('👤 مستخدم',    LogType.userCreated,            Colors.purple),
      ('🔑 دخول',      LogType.userLogin,              Colors.teal),
      ('🚪 خروج',      LogType.userLogout,             Colors.grey),
    ];

    return Container(
      color: Colors.white,
      height: 42,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: filters.length,
        itemBuilder: (_, i) {
          final label  = filters[i].$1;
          final value  = filters[i].$2;
          final color  = filters[i].$3;
          final sel    = _typeFilter == value;
          return GestureDetector(
            onTap: () => setState(() => _typeFilter = value),
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              decoration: BoxDecoration(
                color: sel ? color.withOpacity(0.12) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: sel ? color : Colors.transparent, width: 1.5),
              ),
              child: Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    color: sel ? color : Colors.grey.shade600,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  )),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.history, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('لا توجد سجلات بعد',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
        const SizedBox(height: 8),
        Text('ستظهر هنا كل العمليات تلقائياً من الآن',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      ]),
    );
  }
}

class _LogCard extends StatelessWidget {
  final Map<String, dynamic> log;
  final String timeStr;
  final VoidCallback? onRecover; // ✅ استرجاع محذوف نهائياً
  const _LogCard({required this.log, this.timeStr = '', this.onRecover});

  @override
  Widget build(BuildContext context) {
    final type = log['type'] as String? ?? '';

    IconData icon;
    Color color;
    switch (type) {
      case LogType.itemAdded:
        icon = Icons.add_circle_outline; color = Colors.green; break;
      case LogType.itemDeleted:
        icon = Icons.delete_outline; color = Colors.red; break;
      case LogType.itemRestored:
        icon = Icons.restore; color = Colors.blue; break;
      case LogType.itemEdited:
        icon = Icons.edit_outlined; color = Colors.orange; break;
      case LogType.userCreated:
        icon = Icons.person_add_outlined; color = Colors.purple; break;
      case LogType.adminCreated:
        icon = Icons.admin_panel_settings_outlined; color = const Color(0xFF1A237E); break;
      case LogType.userActivated:
        icon = Icons.check_circle_outline; color = Colors.green; break;
      case LogType.userDeactivated:
        icon = Icons.block; color = Colors.red; break;
      case LogType.userLogin:
        icon = Icons.login; color = Colors.teal; break;
      case LogType.userLogout:
        icon = Icons.logout; color = Colors.grey; break;
      default:
        icon = Icons.info_outline; color = Colors.grey;
    }

    final typeLabel  = log['typeLabel']      as String? ?? LogType.label(type);
    final actorName  = log['actorName']      as String?;
    final actorRole  = log['actorRole']      as String?;
    final adminName  = log['adminName']      as String?;
    final product    = log['product']        as String?;
    final warehouse  = log['warehouse']      as String?;
    final serial     = log['serial']         as String?;
    final reason     = log['reason']         as String?;
    final tUserName  = log['targetUserName'] as String?;
    final tUserEmail = log['targetUserEmail']as String?;

    final lines = <String>[];
    if (product   != null && product.isNotEmpty)    lines.add('📦 $product');
    if (warehouse != null && warehouse.isNotEmpty)  lines.add('🏪 $warehouse');
    if (serial    != null && serial.isNotEmpty)     lines.add('# $serial');
    if (reason    != null && reason.isNotEmpty)     lines.add('السبب: $reason');
    if (tUserName != null && tUserName.isNotEmpty)  lines.add('👤 $tUserName');
    if (tUserEmail!= null && tUserEmail.isNotEmpty) lines.add('📧 $tUserEmail');
    if (actorName != null && actorName.isNotEmpty) {
      final rl = (actorRole == 'admin' || actorRole == 'superadmin') ? '🔑' : '👤';
      lines.add('$rl $actorName');
    }
    if (adminName != null && adminName.isNotEmpty && adminName != actorName) {
      lines.add('Admin: $adminName');
    }

    final isPermanentDeleted = type == LogType.itemPermanentDeleted;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isPermanentDeleted ? 2 : 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isPermanentDeleted
            ? BorderSide(color: Colors.red.shade200, width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(typeLabel,
                      style: TextStyle(
                          fontSize: 10, color: color, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                if (timeStr.isNotEmpty)
                  Text(timeStr,
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ]),
              const SizedBox(height: 4),
              ...lines.map((l) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(l,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              )),
              // ✅ زر استرجاع للمحذوف نهائياً — Super Admin بس
              if (isPermanentDeleted && onRecover != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 30,
                  child: OutlinedButton.icon(
                    onPressed: onRecover,
                    icon: const Icon(Icons.restore_from_trash, size: 14),
                    label: const Text('استرجاع', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}