// ============================================================
// app_localizations.dart — عربي ↔ إنجليزي
// ============================================================

enum AppLanguage { arabic, english }

class AppLocalizations {
  static AppLanguage _current = AppLanguage.arabic;

  static AppLanguage get current => _current;
  static bool get isArabic => _current == AppLanguage.arabic;
  static bool get isEnglish => _current == AppLanguage.english;

  static void toggle() {
    _current = isArabic ? AppLanguage.english : AppLanguage.arabic;
  }
  static void set(AppLanguage lang) => _current = lang;

  // ---- General ----
  static String get appName => 'Karam Stock';
  static String get today => isArabic ? 'اليوم' : 'Today';
  static String get allDates => isArabic ? 'كل التواريخ' : 'All Dates';
  static String get addItem => isArabic ? 'إضافة قطعة' : 'Add Item';
  static String get noItems => isArabic ? 'لا توجد عناصر' : 'No items found';
  static String get search => isArabic ? 'بحث...' : 'Search...';
  static String get pieces => isArabic ? 'قطعة' : 'items';
  static String get total => isArabic ? 'الإجمالي' : 'Total';
  static String get newCond => isArabic ? 'جديد' : 'New';
  static String get used => isArabic ? 'مستخدم' : 'Used';
  static String get damaged => isArabic ? 'تالف' : 'Damaged';

  // ---- Menu ----
  static String get menu => isArabic ? 'القائمة' : 'Menu';
  static String get deleteLog => isArabic ? 'سجل الحذف' : 'Delete Log';
  static String get manageUsers => isArabic ? 'إدارة المستخدمين' : 'Manage Users';
  static String get importData => isArabic ? 'استيراد البيانات' : 'Import Data';
  static String get manageLists => isArabic ? 'إدارة القوائم' : 'Manage Lists';
  static String get excelToday => isArabic ? 'Excel - اليوم المحدد' : 'Excel - Today';
  static String get excelAll => isArabic ? 'Excel - كل الأيام' : 'Excel - All Days';
  static String get logout => isArabic ? 'تسجيل الخروج' : 'Logout';
  static String get language => isArabic ? '🌐 English' : '🌐 عربي';
  static String get superAdminPanel => isArabic ? 'لوحة Super Admin' : 'Super Admin Panel';

  // ---- Filter ----
  static String get filter => isArabic ? 'فلترة' : 'Filter';
  static String get filterTitle => isArabic ? 'فلترة وترتيب' : 'Filter & Sort';
  static String get filterByWarehouse => isArabic ? 'المخزن' : 'Warehouse';
  static String get filterByCondition => isArabic ? 'الحالة' : 'Condition';
  static String get sortBy => isArabic ? 'الترتيب' : 'Sort By';
  static String get sortDate => isArabic ? 'التاريخ' : 'Date';
  static String get sortProduct => isArabic ? 'المنتج' : 'Product';
  static String get sortWarehouse => isArabic ? 'المخزن' : 'Warehouse';
  static String get allWarehouses => isArabic ? 'كل المخازن' : 'All';
  static String get allConditions => isArabic ? 'الكل' : 'All';
  static String get applyFilter => isArabic ? 'تطبيق الفلتر' : 'Apply Filter';
  static String get resetFilter => isArabic ? 'إعادة ضبط' : 'Reset';
  static String get activeFilter => isArabic ? 'فلتر مفعّل' : 'Filter active';

  // ---- Items ----
  static String get productName => isArabic ? 'المنتج' : 'Product';
  static String get warehouse => isArabic ? 'المخزن' : 'Warehouse';
  static String get serial => isArabic ? 'السيريال' : 'Serial';
  static String get condition => isArabic ? 'الحالة' : 'Condition';
  static String get expiryDate => isArabic ? 'الصلاحية' : 'Expiry';
  static String get notes => isArabic ? 'ملاحظات' : 'Notes';
  static String get expiry => isArabic ? 'صلاحية:' : 'Expiry:';

  // ---- Roles ----
  static String get superAdmin => '👑 Super Admin';
  static String get admin => isArabic ? '🔑 مدير' : '🔑 Admin';
  static String get userRole => isArabic ? '👤 مستخدم' : '👤 User';

  // ---- Actions ----
  static String get confirm => isArabic ? 'تأكيد' : 'Confirm';
  static String get cancel => isArabic ? 'إلغاء' : 'Cancel';
  static String get save => isArabic ? 'حفظ' : 'Save';
  static String get delete => isArabic ? 'حذف' : 'Delete';
  static String get edit => isArabic ? 'تعديل' : 'Edit';
  static String get restore => isArabic ? 'استعادة' : 'Restore';
  static String get move => isArabic ? 'نقل' : 'Move';
  static String get moveTo => isArabic ? 'نقل إلى مخزن' : 'Move to Warehouse';
  static String get from => isArabic ? 'من:' : 'From:';
  static String get noOtherWarehouses => isArabic ? 'لا يوجد مخازن أخرى' : 'No other warehouses';
  static String get noPermissionDelete => isArabic ? 'ليس لديك صلاحية الحذف' : 'No permission to delete';
  static String get noPermissionAdd => isArabic ? 'مش عندك صلاحية الإضافة' : 'No permission to add';
  static String get noData => isArabic ? 'لا توجد بيانات' : 'No data found';
  static String get noDataToday => isArabic ? 'لا توجد بيانات في هذا اليوم' : 'No data for today';

  // ---- Logout ----
  static String get logoutTitle => isArabic ? 'تسجيل الخروج' : 'Logout';
  static String get logoutConfirm =>
      isArabic ? 'هل أنت متأكد من تسجيل الخروج؟' : 'Are you sure you want to logout?';
  static String get logoutYes => isArabic ? 'نعم، خروج' : 'Yes, Logout';

  // ---- Deleted Items ----
  static String get deleted => isArabic ? 'حذف:' : 'Deleted:';
  static String get permanentDelete => isArabic ? 'حذف نهائي' : 'Permanent Delete';
  static String get deleteLog2 => isArabic ? 'سجل الحذف' : 'Delete Log';

  // ---- Add Item Screen ----
  static String get selectWarehouse => isArabic ? 'اختار المخزن' : 'Select Warehouse';
  static String get selectProduct => isArabic ? 'اختار المنتج' : 'Select Product';
  static String get addNew => isArabic ? 'جديد' : 'New';
  static String get scanBarcode => isArabic ? 'اقرأ الباركود' : 'Scan Barcode';
  static String get itemCondition => isArabic ? 'حالة القطعة' : 'Item Condition';
  static String get expiryOptional => isArabic ? 'تاريخ الصلاحية (اختياري)' : 'Expiry Date (optional)';
  static String get notesOptional => isArabic ? 'ملاحظات (اختياري)' : 'Notes (optional)';
  static String get update => isArabic ? 'تحديث' : 'Update';
  static String get addPiece => isArabic ? 'إضافة قطعة' : 'Add Item';
  static String get editPiece => isArabic ? 'تعديل قطعة' : 'Edit Item';
  static String get loginFirst => isArabic ? 'يجب تسجيل الدخول أولاً' : 'Please login first';
  static String get noEditPermission => isArabic ? 'ليس لديك صلاحية التعديل' : 'No edit permission';
  static String get noAddPermission => isArabic ? 'ليس لديك صلاحية الإضافة' : 'No add permission';
  static String get selectWarehouseFirst => isArabic ? 'اختار المخزن والمنتج أولاً' : 'Select warehouse and product first';
  static String get serialBarcode => isArabic ? 'السريال / Barcode' : 'Serial / Barcode';

  // ---- Setup / Invitation Screen ----
  static String get createAccount => isArabic ? 'إنشاء حساب جديد' : 'Create New Account';
  static String get invitationVerified => isArabic ? 'تم التحقق من رمز الدعوة' : 'Invitation code verified';
  static String get fullName => isArabic ? 'الاسم الكامل' : 'Full Name';
  static String get email => isArabic ? 'البريد الإلكتروني' : 'Email Address';
  static String get emailHint => isArabic ? 'مثال: name@domain.com' : 'Example: name@domain.com';
  static String get password => isArabic ? 'كلمة السر' : 'Password';
  static String get confirmPassword => isArabic ? 'تأكيد كلمة السر' : 'Confirm Password';
  static String get createAccountBtn => isArabic ? 'إنشاء الحساب' : 'Create Account';
  static String get accountCreated => isArabic ? 'تم إنشاء الحساب بنجاح!' : 'Account created successfully!';
  static String get loginNow => isArabic ? 'تسجيل الدخول الآن' : 'Login Now';
  static String get pendingReview => isArabic
      ? 'تم إنشاء حسابك بنجاح، يمكنك تسجيل الدخول الآن\n\n⚠️ ملاحظة: حسابك قيد المراجعة من قبل المسؤول'
      : 'Your account has been created.\n\n⚠️ Note: Your account is pending review by the admin.';

  // ---- Password Rules ----
  static String get passwordRequirements => isArabic ? 'متطلبات كلمة السر:' : 'Password requirements:';
  static String get passMin8 => isArabic ? '8 أحرف على الأقل' : 'At least 8 characters';
  static String get passUppercase => isArabic ? 'حرف كبير (A-Z)' : 'Uppercase letter (A-Z)';
  static String get passLowercase => isArabic ? 'حرف صغير (a-z)' : 'Lowercase letter (a-z)';
  static String get passNumber => isArabic ? 'رقم (0-9)' : 'Number (0-9)';
  static String get passSpecial => isArabic ? 'علامة مميزة (! @ # \$ %)' : 'Special character (! @ # \$ %)';
  static String get passwordMismatch => isArabic ? 'كلمتا السر غير متطابقتين' : 'Passwords do not match';
  static String get passwordWrong => isArabic ? 'كلمة السر غير صحيحة' : 'Invalid password';
  static String get okFix => isArabic ? 'حسناً، سأعدلها' : 'OK, I\'ll fix it';

  // ---- Email Rules ----
  static String get emailRequired => isArabic ? 'البريد الإلكتروني مطلوب' : 'Email is required';
  static String get emailMustHaveAt => isArabic ? 'البريد يجب أن يحتوي على @' : 'Email must contain @';
  static String get emailInvalid => isArabic ? 'صيغة البريد غير صحيحة' : 'Invalid email format';
  static String get emailInvalidFull => isArabic
      ? 'صيغة البريد غير صحيحة (مثال: name@domain.com)'
      : 'Invalid email format (example: name@domain.com)';
  static String get emailTooLong => isArabic ? 'البريد طويل جداً' : 'Email is too long';
  static String get emailAlreadyUsed => isArabic ? 'هذا البريد الإلكتروني مستخدم بالفعل' : 'This email is already in use';

  // ---- Users Management ----
  static String get addUser => isArabic ? 'إضافة مستخدم جديد' : 'Add New User';
  static String get accountType => isArabic ? 'نوع الحساب:' : 'Account Type:';
  static String get assignedWarehouse => isArabic ? 'المخزن المخصص:' : 'Assigned Warehouse:';
  static String get noRestriction => isArabic ? 'بدون تقييد (كل المخازن)' : 'No restriction (all warehouses)';
  static String get permissions => isArabic ? 'الصلاحيات:' : 'Permissions:';
  static String get nameRequired => isArabic ? 'الاسم مطلوب' : 'Name is required';
  static String get fillAllFields => isArabic ? 'ارجاء ملء كل الحقول المطلوبة' : 'Please fill all required fields';
  static String get accountCreatedSuccess => isArabic ? 'تم إنشاء الحساب بنجاح ✅' : 'Account created successfully ✅';
  static String get upgradeToAdmin => isArabic ? 'ترقية لـ Admin' : 'Upgrade to Admin';
  static String get upgradeConfirm => isArabic ? 'ترقية لـ Admin' : 'Upgrade to Admin';
  static String get upgradeSuccess => isArabic ? 'تم الترقية بنجاح ✅' : 'Upgraded successfully ✅';
  static String get stop => isArabic ? 'إيقاف' : 'Deactivate';

  // ---- Permissions Labels ----
  static String get permAdd => isArabic ? 'إضافة' : 'Add';
  static String get permEdit => isArabic ? 'تعديل' : 'Edit';
  static String get permDelete => isArabic ? 'حذف' : 'Delete';
  static String get permRestore => isArabic ? 'استعادة من الحذف' : 'Restore deleted';
  static String get permExport => isArabic ? 'تصدير Excel' : 'Export Excel';
  static String get permImport => isArabic ? 'استيراد' : 'Import';
  static String get permManage => isArabic ? 'إدارة القوائم' : 'Manage Lists';

  // ---- Login Screen ----
  static String get loginTitle => isArabic ? 'تسجيل الدخول' : 'Sign In';
  static String get loginBtn => isArabic ? 'دخول' : 'Login';
  static String get loginContinue => isArabic ? 'سجّل دخولك للمتابعة' : 'Sign in to continue';
  static String get loginFailed => isArabic ? 'فشل تسجيل الدخول' : 'Login failed';
  static String get loginWrongCredentials =>
      isArabic ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة' : 'Incorrect email or password';
  static String get loginInvalidEmail =>
      isArabic ? 'صيغة البريد الإلكتروني غير صحيحة' : 'Invalid email format';
  static String get loginUnexpectedError =>
      isArabic ? 'حدث خطأ غير متوقع' : 'An unexpected error occurred';
  static String get enterEmailAndPass =>
      isArabic ? 'ادخل البريد وكلمة السر' : 'Enter email and password';
}