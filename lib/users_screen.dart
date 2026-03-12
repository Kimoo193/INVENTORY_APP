import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'log_service.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool _loading = true;
  List<AppUser> _users = [];
  AppUser? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    final currentUser = await AuthService.instance.getCurrentUser();
    List<AppUser> users = [];
    if (currentUser != null) {
      users = currentUser.isSuperAdmin
          ? await AuthService.instance.getAllUsers()
          : await AuthService.instance.getUsersByAdmin(currentUser.uid);
    }
    if (!mounted) return;
    setState(() {
      _currentUser = currentUser;
      _users = users;
      _loading = false;
    });
  }

  Future<void> _toggleActive(AppUser user, bool value) async {
    await AuthService.instance.toggleUserActive(user.uid, value);
    await _loadUsers();
  }

  Future<void> _togglePermission(AppUser user, String key, bool value) async {
    await AuthService.instance.updateUserPermissions(user.uid, {key: value});
    await _loadUsers();
  }

  // ============================================================
  // ✅ Dialog شرح قواعد كلمة السر
  // ============================================================
  void _showPasswordRulesDialog(String specificError) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [
            Icon(Icons.lock_outline, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Text('كلمة السر غير صحيحة'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(specificError,
                    style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 14),
              const Text('متطلبات كلمة السر:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...[
                '8 أحرف على الأقل',
                'حرف كبير (A-Z)',
                'حرف صغير (a-z)',
                'رقم (0-9)',
                'علامة مميزة مثل: ! @ # \$ %',
              ].map((rule) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(Icons.check_circle_outline, size: 16, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text(rule, style: const TextStyle(fontSize: 13)),
                ]),
              )),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
              ),
              child: const Text('حسناً، سأعدلها'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ Dialog إضافة مستخدم جديد
  // ============================================================
  Future<void> _showAddUserDialog() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String? selectedWarehouse;
    List<String> warehouses = [];
    bool isAdmin = false;
    bool obscure = true;

    Map<String, bool> permissions = {
      'canAdd': true,
      'canEdit': false,
      'canDelete': false,
      'canRestore': false,
      'canExport': false,
      'canImport': false,
      'canManage': false,
    };

    // جيب المخازن للـ dropdown
    try {
      // نستورد FirestoreService هنا بشكل dynamic
      final fs = await _getWarehouses();
      warehouses = fs;
    } catch (_) {}

    final permLabels = {
      'canAdd': 'إضافة',
      'canEdit': 'تعديل',
      'canDelete': 'حذف',
      'canRestore': 'استعادة من الحذف',
      'canExport': 'تصدير Excel',
      'canImport': 'استيراد',
      'canManage': 'إدارة القوائم',
    };

    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Directionality(
          textDirection: TextDirection.rtl,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_add, color: Color(0xFF1A237E)),
                      ),
                      const SizedBox(width: 12),
                      const Text('إضافة مستخدم جديد',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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

                    // البريد
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

                    // كلمة السر
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
                    const SizedBox(height: 16),

                    // نوع الحساب (User / Admin) - للـ SuperAdmin بس
                    if (_currentUser?.isSuperAdmin == true) ...[
                      Row(children: [
                        const Text('نوع الحساب:', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('🔑 مدير'),
                          selected: isAdmin,
                          onSelected: (v) => setS(() => isAdmin = v),
                          selectedColor: const Color(0xFF1A237E).withValues(alpha: 0.15),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('👤 مستخدم'),
                          selected: !isAdmin,
                          onSelected: (v) => setS(() => isAdmin = !v),
                          selectedColor: const Color(0xFF1A237E).withValues(alpha: 0.15),
                        ),
                      ]),
                      const SizedBox(height: 12),
                    ],

                    // المخزن المخصص (للـ User فقط)
                    if (!isAdmin) ...[
                      const Text('المخزن المخصص:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: selectedWarehouse,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        hint: const Text('بدون تقييد (كل المخازن)'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('بدون تقييد (كل المخازن)')),
                          ...warehouses.map((w) => DropdownMenuItem(value: w, child: Text(w))),
                        ],
                        onChanged: (v) => setS(() => selectedWarehouse = v),
                      ),
                      const SizedBox(height: 16),

                      // الصلاحيات
                      const Text('الصلاحيات:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ...permLabels.entries.map((e) => SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value, style: const TextStyle(fontSize: 14)),
                        value: permissions[e.key] ?? false,
                        activeThumbColor: const Color(0xFF1A237E),
                        onChanged: (v) => setS(() => permissions[e.key] = v),
                      )),
                    ],

                    const SizedBox(height: 20),

                    // Buttons
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
      ),
    );

    if (result != true) return;

    // ✅ Validate جميع الحقول مع القواعد
    final nameVal  = nameCtrl.text.trim();
    final emailVal = emailCtrl.text.trim();
    final passVal  = passCtrl.text;

    if (nameVal.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الاسم مطلوب'), backgroundColor: Colors.red));
      }
      return;
    }

    final emailError = AppValidators.validateEmail(emailVal);
    if (emailError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emailError), backgroundColor: Colors.red));
      }
      return;
    }

    // ✅ تحقق إن البريد مش مستخدم من قبل
    final emailUsedError = await AppValidators.checkEmailNotUsed(emailVal);
    if (emailUsedError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emailUsedError), backgroundColor: Colors.orange));
      }
      return;
    }

    final passError = AppValidators.validatePassword(passVal);
    if (passError != null) {
      if (mounted) _showPasswordRulesDialog(passError);
      return;
    }

    // Show loading
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      if (isAdmin && _currentUser?.isSuperAdmin == true) {
        // ✅ إنشاء Admin
        await AuthService.instance.createAdmin(
          email: emailCtrl.text.trim(),
          password: passCtrl.text,
          name: nameCtrl.text.trim(),
          createdBy: _currentUser!.uid,
        );
        // ✅ Log
        LogService.instance.logUserCreated(
          createdByUid:   _currentUser!.uid,
          createdByName:  _currentUser!.name,
          createdByRole:  _currentUser!.role,
          newUserName:    nameCtrl.text.trim(),
          newUserEmail:   emailCtrl.text.trim(),
          newUserRole:    'admin',
          adminUid:       _currentUser!.uid,
        );
      } else {
        // ✅ إنشاء User عادي
        await AuthService.instance.createUser(
          email: emailCtrl.text.trim(),
          password: passCtrl.text,
          name: nameCtrl.text.trim(),
          permissions: permissions,
          assignedWarehouse: selectedWarehouse,
          adminUid: _currentUser!.isAdmin ? _currentUser!.uid : _currentUser!.adminUid,
          createdBy: _currentUser!.uid,
        );
        // ✅ Log
        LogService.instance.logUserCreated(
          createdByUid:   _currentUser!.uid,
          createdByName:  _currentUser!.name,
          createdByRole:  _currentUser!.role,
          newUserName:    nameCtrl.text.trim(),
          newUserEmail:   emailCtrl.text.trim(),
          newUserRole:    'user',
          adminUid:       _currentUser!.isAdmin ? _currentUser!.uid : _currentUser!.adminUid,
        );
      }

      if (mounted) {
        Navigator.pop(context); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء الحساب بنجاح ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // جيب المخازن من Firestore
  Future<List<String>> _getWarehouses() async {
    try {
      final db = FirebaseFirestore.instance;
      final currentUser = _currentUser;
      if (currentUser == null) return [];
      
      // جيب adminUid
      String? adminUid;
      if (currentUser.isAdmin) {
        adminUid = currentUser.uid;
      } else {
        adminUid = currentUser.adminUid;
      }
      if (adminUid == null) return [];

      final snap = await db
          .collection('inventory')
          .doc(adminUid)
          .collection('warehouses')
          .get();
      return snap.docs.map((d) => d.data()['name'] as String? ?? d.id).toList();
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  // Build
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isAdmin = _currentUser?.isAdmin ?? false;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('المستخدمون (${_users.length})'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadUsers,
                child: _users.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Column(
                              children: [
                                Icon(Icons.people_outline, size: 60, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text('لا يوجد مستخدمون',
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 16)),
                                const SizedBox(height: 8),
                                if (isAdmin)
                                  Text('اضغط + لإضافة مستخدم جديد',
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                        itemCount: _users.length,
                        itemBuilder: (_, i) {
                          final user = _users[i];
                          final canManage = _currentUser?.isAdmin == true &&
                              !user.isSuperAdmin &&
                              user.uid != _currentUser?.uid;

                          // أيقونة الدور
                          final roleIcon = user.isSuperAdmin
                              ? '👑'
                              : user.isAdmin
                                  ? '🔑'
                                  : '👤';
                          final roleLabel = user.isSuperAdmin
                              ? 'Super Admin'
                              : user.isAdmin
                                  ? 'مدير'
                                  : 'مستخدم';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            elevation: 1.5,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: user.isActive
                                    ? const Color(0xFF1A237E).withValues(alpha: 0.1)
                                    : Colors.grey.shade200,
                                child: Text(roleIcon,
                                    style: const TextStyle(fontSize: 18)),
                              ),
                              title: Text(user.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user.email,
                                      style: TextStyle(
                                          fontSize: 11, color: Colors.grey.shade600)),
                                  Row(children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 3),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: user.isAdmin
                                            ? Colors.blue.withValues(alpha: 0.1)
                                            : Colors.green.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(roleLabel,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: user.isAdmin
                                                  ? Colors.blue.shade700
                                                  : Colors.green.shade700,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    if (user.assignedWarehouse != null) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        margin: const EdgeInsets.only(top: 3),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text('📦 ${user.assignedWarehouse}',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange.shade700)),
                                      ),
                                    ],
                                  ]),
                                ],
                              ),
                              trailing: canManage
                                  ? Switch(
                                      value: user.isActive,
                                      activeThumbColor: const Color(0xFF1A237E),
                                      onChanged: (v) => _toggleActive(user, v),
                                    )
                                  : null,
                              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              children: [
                                if (!user.isAdmin) ...[
                                  const Divider(),
                                  const Align(
                                    alignment: Alignment.centerRight,
                                    child: Text('الصلاحيات:',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Colors.grey)),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _permChip(user, 'canAdd', 'إضافة', user.canAdd, canManage),
                                      _permChip(user, 'canEdit', 'تعديل', user.canEdit, canManage),
                                      _permChip(user, 'canDelete', 'حذف', user.canDelete, canManage),
                                      _permChip(user, 'canRestore', 'استعادة', user.canRestore, canManage),
                                      _permChip(user, 'canExport', 'تصدير', user.canExport, canManage),
                                      _permChip(user, 'canImport', 'استيراد', user.canImport, canManage),
                                      _permChip(user, 'canManage', 'إدارة', user.canManage, canManage),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
        // ✅ FAB إضافة مستخدم — للـ Admin و SuperAdmin فقط
        floatingActionButton: isAdmin
            ? FloatingActionButton.extended(
                onPressed: _showAddUserDialog,
                backgroundColor: const Color(0xFF1A237E),
                foregroundColor: Colors.white,
                icon: const Icon(Icons.person_add),
                label: const Text('مستخدم جديد',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              )
            : null,
      ),
    );
  }

  Widget _permChip(
      AppUser user, String key, String label, bool value, bool canManage) {
    return FilterChip(
      selected: value,
      selectedColor: const Color(0xFF1A237E).withValues(alpha: 0.15),
      checkmarkColor: const Color(0xFF1A237E),
      onSelected: canManage ? (v) => _togglePermission(user, key, v) : null,
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}