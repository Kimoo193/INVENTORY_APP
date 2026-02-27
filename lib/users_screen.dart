import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'database.dart';
import 'notification_service.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<AppUser> _users = [];
  bool _loading = true;
  AppUser? _currentUser;
  List<String> _warehouses = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _currentUser = await AuthService.instance.getCurrentUser();
    final users = await AuthService.instance.getAllUsers();
    final warehouses = await DatabaseHelper.instance.getWarehouses();
    setState(() {
      _users = users;
      _warehouses = warehouses;
      _loading = false;
    });
  }

  Future<void> _createUser() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String role = 'user';
    String? selectedWarehouse;
    Map<String, bool> perms = {
      'canAdd': true, 'canEdit': false, 'canDelete': false,
      'canExport': false, 'canImport': false, 'canManage': false,
    };
    final labels = {
      'canAdd': 'إضافة', 'canEdit': 'تعديل', 'canDelete': 'حذف',
      'canExport': 'تصدير Excel', 'canImport': 'استيراد', 'canManage': 'إدارة القوائم',
    };

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('إضافة مستخدم جديد'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(labelText: 'الاسم',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: 'البريد الإلكتروني',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: 'كلمة السر',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                  const SizedBox(height: 12),
                  if (_currentUser?.isSuperAdmin == true) ...[
                    Row(children: [
                      const Text('الدور: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      ChoiceChip(
                          label: const Text('مستخدم'),
                          selected: role == 'user',
                          onSelected: (_) => setS(() => role = 'user')),
                      const SizedBox(width: 8),
                      ChoiceChip(
                          label: const Text('مدير'),
                          selected: role == 'admin',
                          onSelected: (_) => setS(() {
                            role = 'admin';
                            selectedWarehouse = null;
                          })),
                    ]),
                    const SizedBox(height: 10),
                  ],
                  // ✅ تحديد المخزن للـ User فقط
                  if (role == 'user') ...[
                    const Text('المخزن المخصص:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedWarehouse,
                          hint: const Text('اختر مخزن...'),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('بدون تقييد (كل المخازن)')),
                            ..._warehouses.map((w) => DropdownMenuItem(value: w, child: Text(w))),
                          ],
                          onChanged: (v) => setS(() => selectedWarehouse = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (selectedWarehouse != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A237E).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          const Icon(Icons.warehouse, size: 16, color: Color(0xFF1A237E)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            'هيشوف بس قطعه في: $selectedWarehouse',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF1A237E)),
                          )),
                        ]),
                      ),
                    const SizedBox(height: 10),
                    const Align(
                        alignment: Alignment.centerRight,
                        child: Text('الصلاحيات:', style: TextStyle(fontWeight: FontWeight.bold))),
                    ...labels.entries.map((e) => SwitchListTile(
                          dense: true,
                          title: Text(e.value, style: const TextStyle(fontSize: 13)),
                          value: perms[e.key] ?? false,
                          onChanged: (v) => setS(() => perms[e.key] = v),
                          activeColor: const Color(0xFF1A237E),
                        )),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.isEmpty || emailCtrl.text.isEmpty || passCtrl.text.isEmpty) return;
                  Navigator.pop(ctx);
                  setState(() => _loading = true);
                  try {
                    AppUser newUser;
                    if (role == 'admin') {
                      newUser = await AuthService.instance.createAdmin(
                        email: emailCtrl.text, password: passCtrl.text, name: nameCtrl.text,
                      );
                    } else {
                      newUser = await AuthService.instance.createUser(
                        email: emailCtrl.text, password: passCtrl.text, name: nameCtrl.text,
                        permissions: perms,
                        assignedWarehouse: selectedWarehouse, // ✅ المخزن المخصص
                      );
                    }
                    if (_currentUser != null) {
                      NotificationService.instance.notifyUserCreated(
                        newUserName: newUser.name, newUserEmail: newUser.email,
                        createdByName: _currentUser!.name,
                      );
                    }
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم إنشاء الحساب ✅'), backgroundColor: Colors.green));
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                  }
                  _load();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
                child: const Text('إنشاء'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editPermissions(AppUser user) async {
    if (user.isSuperAdmin) return;
    Map<String, bool> perms = {
      'canAdd': user.canAdd, 'canEdit': user.canEdit, 'canDelete': user.canDelete,
      'canExport': user.canExport, 'canImport': user.canImport, 'canManage': user.canManage,
    };
    final labels = {
      'canAdd': 'إضافة', 'canEdit': 'تعديل', 'canDelete': 'حذف',
      'canExport': 'تصدير Excel', 'canImport': 'استيراد', 'canManage': 'إدارة القوائم',
    };
    String? selectedWarehouse = user.assignedWarehouse;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text('صلاحيات ${user.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✅ تغيير المخزن المخصص
                  if (user.role == 'user') ...[
                    const Align(
                        alignment: Alignment.centerRight,
                        child: Text('المخزن المخصص:', style: TextStyle(fontWeight: FontWeight.bold))),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedWarehouse,
                          hint: const Text('بدون تقييد'),
                          isExpanded: true,
                          items: [
                            const DropdownMenuItem(value: null, child: Text('بدون تقييد')),
                            ..._warehouses.map((w) => DropdownMenuItem(value: w, child: Text(w))),
                          ],
                          onChanged: (v) => setS(() => selectedWarehouse = v),
                        ),
                      ),
                    ),
                    const Divider(height: 20),
                  ],
                  ...labels.entries.map((e) => SwitchListTile(
                        dense: true,
                        title: Text(e.value),
                        value: perms[e.key] ?? false,
                        onChanged: (v) => setS(() => perms[e.key] = v),
                        activeColor: const Color(0xFF1A237E),
                      )),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  await AuthService.instance.updateUserPermissions(user.uid, {
                    ...perms,
                    'assignedWarehouse': selectedWarehouse,
                  });
                  Navigator.pop(ctx);
                  _load();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم التحديث ✅'), backgroundColor: Colors.green));
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E), foregroundColor: Colors.white),
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleActive(AppUser user) async {
    if (user.isSuperAdmin) return;
    await AuthService.instance.toggleUserActive(user.uid, !user.isActive);
    _load();
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'superadmin': return Colors.purple;
      case 'admin': return const Color(0xFF1A237E);
      default: return Colors.teal;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'superadmin': return '👑 Super Admin';
      case 'admin': return '🔑 مدير';
      default: return '👤 مستخدم';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('المستخدمون (${_users.length})'),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _createUser,
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          icon: const Icon(Icons.person_add),
          label: const Text('مستخدم جديد'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A237E)))
            : _users.isEmpty
                ? const Center(child: Text('لا يوجد مستخدمين'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                    itemCount: _users.length,
                    itemBuilder: (_, i) {
                      final user = _users[i];
                      final roleColor = _roleColor(user.role);
                      final isMe = user.uid == _currentUser?.uid;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                CircleAvatar(
                                  backgroundColor: roleColor.withOpacity(0.15),
                                  child: Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                                      style: TextStyle(color: roleColor, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(user.name,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                        if (isMe) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(6)),
                                            child: const Text('أنت',
                                                style: TextStyle(fontSize: 10, color: Colors.blue)),
                                          ),
                                        ],
                                      ]),
                                      Text(user.email,
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                      color: roleColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Text(_roleLabel(user.role),
                                      style: TextStyle(
                                          color: roleColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ]),
                              // ✅ عرض المخزن المخصص
                              if (user.role == 'user' && user.assignedWarehouse != null) ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  const Icon(Icons.warehouse, size: 13, color: Color(0xFF1A237E)),
                                  const SizedBox(width: 4),
                                  Text(user.assignedWarehouse!,
                                      style: const TextStyle(
                                          fontSize: 12, color: Color(0xFF1A237E),
                                          fontWeight: FontWeight.w500)),
                                ]),
                              ],
                              if (user.role == 'user') ...[
                                const SizedBox(height: 8),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  if (user.canAdd) _permChip('إضافة', Colors.green),
                                  if (user.canEdit) _permChip('تعديل', Colors.blue),
                                  if (user.canDelete) _permChip('حذف', Colors.red),
                                  if (user.canExport) _permChip('تصدير', Colors.purple),
                                  if (user.canImport) _permChip('استيراد', Colors.orange),
                                  if (user.canManage) _permChip('إدارة', Colors.teal),
                                ]),
                              ],
                              if (!user.isActive)
                                Container(
                                  margin: const EdgeInsets.only(top: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                      color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                                  child: const Text('⛔ موقوف',
                                      style: TextStyle(color: Colors.red, fontSize: 12)),
                                ),
                              if (!user.isSuperAdmin && !isMe) ...[
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (user.role == 'user')
                                      TextButton.icon(
                                        onPressed: () => _editPermissions(user),
                                        icon: const Icon(Icons.edit, size: 16, color: Color(0xFF1A237E)),
                                        label: const Text('الصلاحيات',
                                            style: TextStyle(color: Color(0xFF1A237E), fontSize: 13)),
                                      ),
                                    TextButton.icon(
                                      onPressed: () => _toggleActive(user),
                                      icon: Icon(user.isActive ? Icons.block : Icons.check_circle,
                                          size: 16, color: user.isActive ? Colors.red : Colors.green),
                                      label: Text(user.isActive ? 'تعطيل' : 'تفعيل',
                                          style: TextStyle(
                                              color: user.isActive ? Colors.red : Colors.green,
                                              fontSize: 13)),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
      ),
    );
  }

  Widget _permChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }
}