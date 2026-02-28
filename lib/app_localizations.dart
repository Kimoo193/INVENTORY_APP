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
}