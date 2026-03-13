import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'app_localizations.dart';
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

  static const Color _primary = Color(0xFF16324F);
  static const Color _gold    = Color(0xFFC69749);

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  // ──────────────────── Data ────────────────────────────────
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
      _users       = users;
      _loading     = false;
    });
  }

  Future<void> _toggleActive(AppUser user, bool value) async {
    await AuthService.instance.toggleUserActive(user.uid, value,
        byUid: _currentUser?.uid);
    if (!mounted) return;
    // Fix: show Undo action on toggle so action is reversible
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        value ? AppLocalizations.userActivated : AppLocalizations.userDeactivated,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      backgroundColor: value ? Colors.green : Colors.orange,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      action: SnackBarAction(
        label: AppLocalizations.isArabic ? 'تراجع' : 'Undo',
        textColor: Colors.white,
        onPressed: () async {
          await AuthService.instance.toggleUserActive(user.uid, !value,
              byUid: _currentUser?.uid);
          if (mounted) await _loadUsers();
        },
      ),
    ));
    await _loadUsers();
  }

  Future<void> _togglePermission(AppUser user, String key, bool value) async {
    await AuthService.instance.updateUserPermissions(user.uid, {key: value});
    await _loadUsers();
  }

  // ──────────────────── Helpers ─────────────────────────────
  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      ),
    );
  }

  Future<List<String>> _getWarehouses() async {
    try {
      final currentUser = _currentUser;
      if (currentUser == null) return [];
      final adminUid = currentUser.isAdmin ? currentUser.uid : currentUser.adminUid;
      if (adminUid == null) return [];
      final snap = await FirebaseFirestore.instance
          .collection('inventory')
          .doc(adminUid)
          .collection('warehouses')
          .get();
      return snap.docs
          .map((d) => d.data()['name'] as String? ?? d.id)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ──────────────────── Add User Dialog ─────────────────────
  Future<void> _showAddUserDialog() async {
    final nameCtrl  = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl  = TextEditingController();
    String? selectedWarehouse;
    List<String> warehouses = [];
    bool isAdminAccount = false;
    bool obscure = true;
    String? _passError; // Fix: inline password error — no dialog-on-dialog

    Map<String, bool> permissions = {
      'canAdd': true, 'canEdit': false, 'canDelete': false,
      'canRestore': false, 'canExport': false, 'canImport': false, 'canManage': false,
    };

    try { warehouses = await _getWarehouses(); } catch (_) {}

    final permLabels = {
      'canAdd':    AppLocalizations.permAdd,
      'canEdit':   AppLocalizations.permEdit,
      'canDelete': AppLocalizations.permDelete,
      'canRestore':AppLocalizations.permRestore,
      'canExport': AppLocalizations.permExport,
      'canImport': AppLocalizations.permImport,
      'canManage': AppLocalizations.permManage,
    };

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Directionality(
          textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──────────────────────────────
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_add_rounded, color: _primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppLocalizations.addUser,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          Text(AppLocalizations.isArabic ? 'أدخل بيانات المستخدم الجديد' : 'Enter new user details',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: Icon(Icons.close_rounded, color: Colors.grey.shade400),
                    ),
                  ]),

                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),

                  // ── Name ────────────────────────────────
                  _fieldLabel(AppLocalizations.fullName, Icons.person_outline_rounded),
                  const SizedBox(height: 8),
                  _inputField(ctrl: nameCtrl, hint: AppLocalizations.isArabic ? 'الاسم الكامل' : 'Full name'),

                  const SizedBox(height: 14),

                  // ── Email ────────────────────────────────
                  _fieldLabel(AppLocalizations.email, Icons.email_outlined),
                  const SizedBox(height: 8),
                  _inputField(ctrl: emailCtrl, hint: AppLocalizations.emailHint, isEmail: true),

                  const SizedBox(height: 14),

                  // ── Password ──────────────────────────────
                  _fieldLabel(AppLocalizations.password, Icons.lock_outline_rounded),
                  const SizedBox(height: 8),
                  StatefulBuilder(
                    builder: (_, setSO) => TextField(
                      controller: passCtrl,
                      obscureText: obscure,
                      onChanged: (_) {
                        if (_passError != null) setS(() => _passError = null);
                      },
                      decoration: InputDecoration(
                        hintText: AppLocalizations.isArabic ? 'كلمة السر' : 'Password',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        filled: true,
                        fillColor: _passError != null ? Colors.red.shade50 : Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _passError != null ? Colors.red : _primary, width: 2)),
                        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade400, width: 1.5)),
                        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.red.shade600, width: 2)),
                        errorText: _passError,
                        errorMaxLines: 3,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        suffixIcon: IconButton(
                          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: Colors.grey.shade400),
                          onPressed: () => setSO(() => obscure = !obscure),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ── Account Type ─────────────────────────
                  if (_currentUser?.isSuperAdmin == true) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _primary.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _primary.withValues(alpha: 0.12)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.admin_panel_settings_rounded,
                              size: 18, color: _primary.withValues(alpha: 0.7)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              AppLocalizations.isArabic ? 'حساب مدير (Admin)' : 'Admin Account',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _primary.withValues(alpha: 0.9)),
                            ),
                          ),
                          Switch(
                            value: isAdminAccount,
                            activeColor: _gold,
                            onChanged: (v) => setS(() => isAdminAccount = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── Assigned Warehouse (User only) ───────
                  if (!isAdminAccount) ...[
                    _fieldLabel(AppLocalizations.assignedWarehouse, Icons.warehouse_rounded),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedWarehouse,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 2)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      hint: Text(AppLocalizations.noRestriction,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                      items: [
                        DropdownMenuItem(value: null, child: Text(AppLocalizations.noRestriction, style: const TextStyle(fontSize: 13))),
                        ...warehouses.map((w) => DropdownMenuItem(value: w, child: Text(w, style: const TextStyle(fontSize: 13)))),
                      ],
                      onChanged: (v) => setS(() => selectedWarehouse = v),
                    ),
                    const SizedBox(height: 16),

                    // ── Permissions ──────────────────────
                    _fieldLabel(AppLocalizations.permissions, Icons.security_rounded),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: permLabels.entries.map((e) {
                          final val = permissions[e.key] ?? false;
                          return FilterChip(
                            selected: val,
                            selectedColor: _primary.withValues(alpha: 0.15),
                            checkmarkColor: _primary,
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: val ? _primary.withValues(alpha: 0.4) : Colors.grey.shade300,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            label: Text(e.value, style: TextStyle(fontSize: 12, color: val ? _primary : Colors.grey.shade600, fontWeight: val ? FontWeight.w700 : FontWeight.normal)),
                            onSelected: (v) => setS(() => permissions[e.key] = v),
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // ── Buttons ──────────────────────────────
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: Colors.grey.shade300),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(AppLocalizations.cancel,
                            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        icon: const Icon(Icons.person_add_rounded, size: 18),
                        label: Text(AppLocalizations.create,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
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

    final nameVal  = nameCtrl.text.trim();
    final emailVal = emailCtrl.text.trim();
    final passVal  = passCtrl.text;

    if (nameVal.isEmpty) {
      if (mounted) _showSnack(AppLocalizations.nameRequired, Colors.red);
      return;
    }

    final emailError = AppValidators.validateEmail(emailVal);
    if (emailError != null) {
      if (mounted) _showSnack(emailError, Colors.red);
      return;
    }

    final emailUsedError = await AppValidators.checkEmailNotUsed(emailVal);
    if (emailUsedError != null) {
      if (mounted) _showSnack(emailUsedError, Colors.orange);
      return;
    }

    final passError = AppValidators.validatePassword(passVal);
    if (passError != null) {
      _showSnack(passError, Colors.red);
      return;
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: _primary),
                const SizedBox(height: 12),
                Text(AppLocalizations.loading,
                    style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      );
    }

    try {
      if (isAdminAccount && _currentUser?.isSuperAdmin == true) {
        await AuthService.instance.createAdmin(
          email: emailVal,
          password: passVal,
          name: nameVal,
          createdBy: _currentUser!.uid,
        );
        LogService.instance.logUserCreated(
          createdByUid: _currentUser!.uid, createdByName: _currentUser!.name,
          createdByRole: _currentUser!.role, newUserName: nameVal,
          newUserEmail: emailVal, newUserRole: 'admin', adminUid: _currentUser!.uid,
        );
      } else {
        await AuthService.instance.createUser(
          email: emailVal, password: passVal, name: nameVal,
          permissions: permissions, assignedWarehouse: selectedWarehouse,
          adminUid: _currentUser!.isAdmin ? _currentUser!.uid : _currentUser!.adminUid,
          createdBy: _currentUser!.uid,
        );
        LogService.instance.logUserCreated(
          createdByUid: _currentUser!.uid, createdByName: _currentUser!.name,
          createdByRole: _currentUser!.role, newUserName: nameVal,
          newUserEmail: emailVal, newUserRole: 'user',
          adminUid: _currentUser!.isAdmin ? _currentUser!.uid : _currentUser!.adminUid,
        );
      }

      if (mounted) {
        Navigator.pop(context);
        _showSnack(AppLocalizations.accountCreatedSuccess, Colors.green);
      }
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnack('${AppLocalizations.error}: $e', Colors.red);
      }
    }
  }

  // ──────────────────── UI Helpers ──────────────────────────
  Widget _fieldLabel(String label, IconData icon) => Row(
    children: [
      Icon(icon, size: 15, color: Colors.grey.shade500),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Colors.grey.shade700)),
    ],
  );

  Widget _inputField({
    required TextEditingController ctrl,
    required String hint,
    bool isEmail = false,
  }) {
    return TextField(
      controller: ctrl,
      textDirection: isEmail ? TextDirection.ltr : TextDirection.rtl,
      keyboardType: isEmail ? TextInputType.emailAddress : null,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primary, width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // ──────────────────── Build ───────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isAdmin = _currentUser?.isAdmin ?? false;

    return Directionality(
      textDirection: AppLocalizations.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.isArabic
                    ? 'المستخدمون'
                    : 'Users',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              Text(
                '${_users.length} ${AppLocalizations.isArabic ? "حساب" : "accounts"}',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
        body: _loading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: _primary, strokeWidth: 2.5),
                    const SizedBox(height: 12),
                    Text(AppLocalizations.loading,
                        style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadUsers,
                color: _primary,
                child: _users.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Column(children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: _primary.withValues(alpha: 0.06),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.people_outline_rounded,
                                  size: 36, color: _primary.withValues(alpha: 0.3)),
                            ),
                            const SizedBox(height: 16),
                            Text(AppLocalizations.noUsers,
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            if (isAdmin) ...[
                              const SizedBox(height: 6),
                              Text(
                                AppLocalizations.isArabic ? 'اضغط + لإضافة مستخدم جديد' : 'Tap + to add a new user',
                                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                              ),
                            ],
                          ]),
                        ),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                        itemCount: _users.length,
                        itemBuilder: (_, i) => _buildUserCard(_users[i]),
                      ),
              ),
        floatingActionButton: isAdmin
            ? FloatingActionButton.extended(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  _showAddUserDialog();
                },
                backgroundColor: _gold,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.person_add_rounded, size: 20),
                label: Text(
                  AppLocalizations.isArabic ? 'مستخدم جديد' : 'New User',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              )
            : null,
      ),
    );
  }

  Widget _buildUserCard(AppUser user) {
    final canManage = _currentUser?.isAdmin == true &&
        !user.isSuperAdmin && user.uid != _currentUser?.uid;

    final roleEmoji = user.isSuperAdmin ? '👑' : user.isAdmin ? '🔑' : '👤';
    final roleLabel = user.isSuperAdmin
        ? 'Super Admin'
        : user.isAdmin
            ? (AppLocalizations.isArabic ? 'مدير' : 'Admin')
            : (AppLocalizations.isArabic ? 'مستخدم' : 'User');
    final roleColor = user.isSuperAdmin
        ? _gold
        : user.isAdmin
            ? Colors.blue.shade600
            : Colors.green.shade600;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: _primary.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (user.isActive ? _primary : Colors.grey).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(roleEmoji, style: const TextStyle(fontSize: 20)),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  user.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16, // fixed: was 14px
                    color: user.isActive ? const Color(0xFF1A1A2E) : Colors.grey,
                  ),
                ),
              ),
              // Role badge always visible in title
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: roleColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(roleLabel,
                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
              if (!user.isActive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    AppLocalizations.isArabic ? 'موقوف' : 'Inactive',
                    style: TextStyle(fontSize: 10, color: Colors.red.shade600, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.email,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500), // fixed: was 11px
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    // role tag removed from here — now shown in title row
                    if (user.assignedWarehouse != null)
                      _tag('📦 ${user.assignedWarehouse}', Colors.orange.shade600),
                  ],
                ),
              ],
            ),
          ),
          trailing: canManage
              ? Switch(
                  value: user.isActive,
                  activeColor: _primary,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    _toggleActive(user, v);
                  },
                )
              : null,
          children: [
            if (!user.isAdmin) ...[
              const Divider(height: 16, thickness: 0.5),
              Align(
                alignment: AppLocalizations.isArabic ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(
                  AppLocalizations.permissions,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _permChip(user, 'canAdd',    AppLocalizations.permAdd,     user.canAdd,    canManage),
                  _permChip(user, 'canEdit',   AppLocalizations.permEdit,    user.canEdit,   canManage),
                  _permChip(user, 'canDelete', AppLocalizations.permDelete,  user.canDelete, canManage),
                  _permChip(user, 'canRestore',AppLocalizations.permRestore, user.canRestore,canManage),
                  _permChip(user, 'canExport', AppLocalizations.permExport,  user.canExport, canManage),
                  _permChip(user, 'canImport', AppLocalizations.permImport,  user.canImport, canManage),
                  _permChip(user, 'canManage', AppLocalizations.permManage,  user.canManage, canManage),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
  );

  static const Map<String, String> _permTooltipsAr = {
    'canAdd':     'إضافة قطع جديدة للمخزن',
    'canEdit':    'تعديل بيانات القطع الموجودة',
    'canDelete':  'حذف قطع من المخزن مع سبب',
    'canRestore': 'استعادة قطع محذوفة من السجل',
    'canExport':  'تصدير البيانات لملف Excel',
    'canImport':  'استيراد بيانات من ملف Excel',
    'canManage':  'إدارة المخازن والمنتجات',
  };
  static const Map<String, String> _permTooltipsEn = {
    'canAdd':     'Add new items to inventory',
    'canEdit':    'Edit existing item details',
    'canDelete':  'Delete items with a reason',
    'canRestore': 'Restore deleted items from log',
    'canExport':  'Export data to Excel file',
    'canImport':  'Import data from Excel file',
    'canManage':  'Manage warehouses and products',
  };

  Widget _permChip(AppUser user, String key, String label, bool value, bool canManage) {
    final tooltip = AppLocalizations.isArabic
        ? (_permTooltipsAr[key] ?? label)
        : (_permTooltipsEn[key] ?? label);
    return Tooltip(
      message: tooltip,
      preferBelow: true,
      decoration: BoxDecoration(
        color: const Color(0xFF16324F),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      child: FilterChip(
        selected: value,
        selectedColor: _primary.withValues(alpha: 0.15),
        checkmarkColor: _primary,
        backgroundColor: Colors.white,
        side: BorderSide(
            color: value ? _primary.withValues(alpha: 0.4) : Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        label: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              color: value ? _primary : Colors.grey.shade600,
              fontWeight: value ? FontWeight.w700 : FontWeight.normal),
        ),
        onSelected: canManage ? (v) => _togglePermission(user, key, v) : null,
      ),
    );
  }
}