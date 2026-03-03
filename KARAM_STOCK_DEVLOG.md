# 📋 Karam Stock — سجل التطوير والمشاكل والحلول

---

## 🏗️ معلومات المشروع

| | |
|---|---|
| **اسم التطبيق** | Karam Stock |
| **التقنية** | Flutter + Firebase (Firestore + Auth) |
| **قاعدة البيانات** | Firestore (بعد migration من SQLite) |
| **المنصة** | Android |
| **المطور** | Kareem Mohamed |

---

## 🔥 مشاكل تم حلها — بالتفصيل

---

### 🔴 مشكلة 1: Auto-Login Bug

**المشكلة:**
عند إنشاء User جديد من Admin، كان التطبيق يعمل auto-login للـ User الجديد ويخرج الـ Admin من حسابه.

**السبب:**
`FirebaseAuth.instance.createUserWithEmailAndPassword()` بتعمل sign-in تلقائي للـ user الجديد في نفس الـ Auth instance.

**الحل:**
استخدام **Secondary Firebase App** — نعمل Firebase app مؤقت منفصل لإنشاء الـ user فيه، فالـ Admin يفضل مسجل دخول في الـ app الأصلي.

```dart
// في auth_service.dart
final tempApp = await Firebase.initializeApp(
  name: 'secondary_${DateTime.now().millisecondsSinceEpoch}',
  options: DefaultFirebaseOptions.currentPlatform,
);
final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
await tempAuth.createUserWithEmailAndPassword(email: email, password: password);
await tempApp.delete();
```

**الملفات المتأثرة:** `auth_service.dart`

---

### 🔴 مشكلة 2: FCM Server Key مطلوب

**المشكلة:**
نظام الإشعارات كان يحتاج Firebase Cloud Messaging Server Key (محظور في client-side).

**الحل:**
استبدال FCM بـ **Firestore Listener** — كل Admin عنده collection `/notifications/{uid}/items`، أي User يكتب فيها والـ Admin بيسمع التغييرات real-time.

```
notifications/
  {adminUid}/
    items/
      {notifId}: { title, body, type, read, createdAt }
```

**الملفات المتأثرة:** `notification_service.dart`

---

### 🔴 مشكلة 3: Build Error — core library desugaring

**المشكلة:**
```
Error: Cannot run with sound null safety
flutter_local_notifications requires core library desugaring
```

**الحل:**
في `build.gradle.kts`:
```kotlin
android {
  compileOptions {
    isCoreLibraryDesugaringEnabled = true
  }
}
dependencies {
  coreLibraryDesugaring("com.android.tools.build:desugaring:2.0.4")
}
```

**الملفات المتأثرة:** `build.gradle.kts`

---

### 🔴 مشكلة 4: User يشوف كل المخزن مش مخزنه بس

**المشكلة:**
كل المستخدمين كانوا يشوفون كل القطع في كل المخازن.

**الحل:**
نظام `assignedWarehouse` — كل User بيتربط بمخزن معين عند الإنشاء، وكل query بيتفلتر تلقائياً:

```dart
// في FirestoreService
if (user != null && !user.isAdmin && user.assignedWarehouse != null) {
  query = query.where('warehouseName', isEqualTo: user.assignedWarehouse);
}
```

**الملفات المتأثرة:** `auth_service.dart`, `firestore_service.dart`, `users_screen.dart`, `inventory_screen.dart`

---

### 🔴 مشكلة 5: Multi-Admin — User يشوف بيانات Admin تاني

**المشكلة:**
كل البيانات كانت في collection واحدة — أي User يقدر يشوف بيانات أي Admin.

**الحل:**
عزل كامل في Firestore — كل Admin عنده sub-collection خاصة:

```
inventory/
  {adminUid}/
    items/         ← قطع المخزون
    deleted_items/ ← المحذوفات
    warehouses/    ← المخازن
    products/      ← المنتجات
```

**الملفات المتأثرة:** `firestore_service.dart`, `auth_service.dart`, `firestore.rules`

---

### 🔴 مشكلة 6: Firestore Rules — أي User يقرأ كل البيانات

**المشكلة:**
```javascript
// ❌ خطير جداً — كان موجود
match /{document=**} {
  allow read, write: if isAuthenticated();
}
```

**الحل:**
Rules محكمة — كل Admin يشوف بياناته بس:

```javascript
function isOwnerOrRelated(adminUid) {
  return request.auth.uid == adminUid ||
         getUserData().adminUid == adminUid ||
         isSuperAdmin();
}

match /inventory/{adminUid}/items/{itemId} {
  allow read: if isOwnerOrRelated(adminUid);
  allow write: if isAuthenticated() &&
    (request.auth.uid == adminUid || getUserData().adminUid == adminUid);
}
```

**الملفات المتأثرة:** `firestore.rules`

---

### 🔴 مشكلة 7: Migration تقفل التطبيق لو المستخدم عمل Skip

**المشكلة:**
```dart
// ❌ كان موجود
if (result != true) return; // بيوقف التطبيق كله!
```

**الحل:**
```dart
// ✅ الحل
try {
  await Navigator.push(context, MaterialPageRoute(builder: (_) => MigrationScreen()));
} catch (_) {}
```

**الملفات المتأثرة:** `main.dart`

---

### 🔴 مشكلة 8: `adminUid` + `createdBy` مش بيتبعتوا عند إنشاء User

**المشكلة:**
`createUser()` كان بيتنادى بدون `adminUid` و`createdBy`، فـ `getUsersByAdmin()` كانت بترجع قائمة فاضية دايماً.

**الحل:**
```dart
await AuthService.instance.createUser(
  email: ..., password: ..., name: ...,
  adminUid: _currentUser!.uid,   // ✅ ضروري
  createdBy: _currentUser!.uid,  // ✅ ضروري
);
```

**الملفات المتأثرة:** `users_screen.dart`

---

### 🔴 مشكلة 9: Activity Logs فاضية — مش بتسجل حاجة (المرة الأولى)

**المشكلة:**
`LogService.instance.log()` كان بيتنادى بدون `actorUid`، فكان بيفشل صامت.

**الحل:**
تمرير بيانات الـ user صراحةً في كل log call:
```dart
final actor = await _getCachedUser();
LogService.instance.log(
  type: LogType.itemAdded,
  actorUid:  actor?.uid,
  actorName: actor?.name,
  actorRole: actor?.role,
  product:   item.productName,
  adminUid:  adminUid,
);
```

**الملفات المتأثرة:** `firestore_service.dart`, `log_service.dart`, `auth_wrapper.dart`, `main.dart`, `users_screen.dart`

---

### 🔴 مشكلة 10: Duplicate Class — Conflict في Imports

**المشكلة:**
```
Error: 'FirestoreService' is imported from both
'firestore_service.dart' and 'users_screen.dart'
```

`users_screen.dart` كانت تحتوي على محتوى `firestore_service.dart` كاملاً بداخلها من جلسة تطوير سابقة.

**الحل:**
حذف كل الـ duplicate classes من `users_screen.dart` والإبقاء على `class UsersScreen` فقط مع `import 'firestore_service.dart';` صح.

**الملفات المتأثرة:** `users_screen.dart`

---

### 🔴 مشكلة 11: Super Admin Dashboard مش ظاهر في الـ Menu

**المشكلة:**
`super_admin_screen.dart` مكانش بيتعمل import في `main.dart`، وما فيش زرار له في الـ Menu.

**السبب:**
في جلسة إصلاح الـ duplicate class، الـ import اتشال بالغلط ومش اتضافش تاني.

**الحل في `main.dart`:**
```dart
// إضافة الـ import
import 'super_admin_screen.dart';

// إضافة زرار في _MenuSheet — بيظهر بس للـ SuperAdmin
if (currentUser?.isSuperAdmin == true)
  _item(
    context,
    Icons.admin_panel_settings_rounded,
    'لوحة Super Admin',
    const Color(0xFF1A237E),
    () => onNavigate(const SuperAdminScreen()),
  ),
```

**الملفات المتأثرة:** `main.dart`

---

### 🔴 مشكلة 12: Logout مش بيرجع لصفحة تسجيل الدخول

**المشكلة:**
بعد الضغط على "نعم، خروج" — التطبيق بيفضل على نفس الصفحة ومش بيروح لـ LoginScreen.

**السبب الجذري:**
`HomeScreen` بتكون مفتوحة **فوق** `AuthWrapper` في الـ Navigation Stack عن طريق `_SplashThenHome.pushReplacement`. لما بيحصل logout، `AuthWrapper` بيرجع `LoginScreen` صح في الـ widget tree — بس `HomeScreen` لسه موجودة في الـ stack فوقيه فالمستخدم مش بيشوفها.

بالإضافة: `AuthWrapper` كان `StatelessWidget` فالـ `popUntil` كان بيتنادى على غلط context.

**الحل في `auth_wrapper.dart`:**
تحويله لـ `StatefulWidget` مع `_wasLoggedIn` flag:

```dart
class AuthWrapper extends StatefulWidget { ... }

class _AuthWrapperState extends State<AuthWrapper> {
  bool _wasLoggedIn = false;

  // لما Firebase يشيل الـ user
  if (firebaseUser == null) {
    if (_wasLoggedIn) {
      _wasLoggedIn = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // ✅ امسح كل الـ stack وافتح LoginScreen جديدة
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      });
    }
    return const LoginScreen();
  }

  // لما يكون مسجل دخول
  _wasLoggedIn = true;
}
```

**الملفات المتأثرة:** `auth_wrapper.dart`

---

### 🔴 مشكلة 13: Activity Logs فاضية — Firestore Rules تمنع الكتابة (المرة الثانية)

**المشكلة:**
حتى بعد إصلاح مشكلة 9، الـ Activity Log لسه فاضي. كل الـ `log()` calls كانت بتفشل بـ **Permission Denied** صامت لأن `firestore.rules` ما كانتش بتسمح بالكتابة على `activity_logs`.

**الكود القديم في Rules:**
```javascript
// ❌ activity_logs مكانتش موجودة في الـ rules
// = Firestore بيرفض كل write بـ Permission Denied
```

**الحل في `firestore.rules`:**
```javascript
match /activity_logs/{dateId} {
  allow read: if isSuperAdmin();     // بس SuperAdmin يقرأ
  allow write: if isAuthenticated(); // ✅ أي user مسجل دخول يكتب

  match /events/{eventId} {
    allow read:   if isSuperAdmin();
    allow create: if isAuthenticated(); // ✅ أي user يضيف event
    allow update, delete: if isSuperAdmin();
  }
}
```

> **⚠️ مهم جداً:** بعد تعديل `firestore.rules`، لازم ترفعه على Firebase Console:
> Firebase Console → Firestore Database → Rules → Paste → Publish

**الملفات المتأثرة:** `firestore.rules`

---

## 📦 هيكل Firestore النهائي

```
firestore/
│
├── users/
│   └── {uid}: { name, email, role, isActive, adminUid, createdBy, assignedWarehouse, permissions }
│
├── inventory/
│   └── {adminUid}/
│       ├── items/         { productName, warehouseName, serial, condition, addedByUid, ... }
│       ├── deleted_items/ { ...+ deleteReason, deletedByUid, deletedAt }
│       ├── warehouses/    { name }
│       └── products/      { name }
│
├── notifications/
│   └── {adminUid}/
│       └── items/ { title, body, type, read, createdAt }
│
└── activity_logs/
    └── {YYYY-MM-DD}/
        ├── { date, count, lastUpdated }
        └── events/ { type, actorUid, actorName, actorRole, adminUid, product, warehouse, serial, reason, ... }
```

---

## 👥 نظام الصلاحيات

| الدور | يشوف | يضيف | يعدل | يحذف | يصدّر | Activity Log |
|---|---|---|---|---|---|---|
| **SuperAdmin** | الكل | ✅ | ✅ | ✅ | ✅ | ✅ يشوف كل شيء |
| **Admin** | مخزنه | ✅ | ✅ | ✅ | ✅ | ❌ |
| **User** | مخزنه المحدد | حسب صلاحيته | حسب صلاحيته | حسب صلاحيته | حسب صلاحيته | ❌ |

---

## ⭐ الميزات المضافة

| الميزة | الوصف |
|---|---|
| **Activity Log** | Super Admin يشوف كل العمليات مرتبة بالتاريخ مع فلتر النوع والبحث |
| **استرجاع المحذوف نهائياً** | في Activity Log ← فلتر "حذف نهائي" ← زر استرجاع |
| **تسجيل Login/Logout** | كل دخول وخروج يتسجل تلقائياً |
| **Super Admin Dashboard** | لوحة تحكم كاملة — Admins + Users + إحصائيات + Activity Log |
| **User Cache** | `_getCachedUser()` يخزن بيانات الـ user 30 ثانية |
| **Language Toggle EN/عر** | زر في الـ AppBar مباشرة |
| **Skeleton Loading** | بدل CircularProgressIndicator |
| **Swipe to Delete** | سحب على القطعة لحذفها |
| **Stats Progress Bar** | نسبة مئوية مع progress bar في كل card |
| **Filter Bottom Sheet** | فلترة متقدمة بالمخزن + الحالة + الترتيب |

---

## 📁 الملفات والوظيفة

| الملف | الوظيفة |
|---|---|
| `main.dart` | الصفحة الرئيسية — إحصائيات + تبويبات التواريخ + القائمة |
| `auth_wrapper.dart` | التحقق من تسجيل الدخول + توجيه المستخدم + logout redirect |
| `auth_service.dart` | Firebase Auth — login, logout, createUser, getCurrentUser |
| `firestore_service.dart` | كل عمليات Firestore — CRUD للمخزون والمحذوفات والمخازن |
| `log_service.dart` | تسجيل كل العمليات في `activity_logs` |
| `inventory_screen.dart` | قائمة القطع مع بحث + فلترة متقدمة |
| `scanner_screen.dart` | إضافة قطعة — Barcode + OCR |
| `deleted_items_screen.dart` | سجل المحذوفات مع استعادة وحذف نهائي |
| `users_screen.dart` | إدارة المستخدمين (Admin) |
| `super_admin_screen.dart` | لوحة تحكم SuperAdmin — Admins + Users + إحصائيات + Activity Log |
| `import_screen.dart` | استيراد Excel/PDF بـ 9 أنماط |
| `export_helper.dart` | تصدير Excel ملون |
| `manage_screen.dart` | إدارة المخازن والمنتجات |
| `migration_screen.dart` | نقل البيانات من SQLite إلى Firestore |
| `notification_service.dart` | إشعارات محلية + Firestore Listener |
| `app_localizations.dart` | ترجمة عربي/إنجليزي |
| `firestore.rules` | قواعد أمان Firestore — ⚠️ لازم ترفعه يدوياً على Firebase Console |

---

## ⚠️ ملاحظات مهمة للـ Deployment

### Firebase Console — خطوات ضرورية:
1. **Firestore Rules** → افتح Firebase Console → Firestore → Rules → انسخ محتوى `firestore.rules` → Publish
2. **Firestore Indexes** → لو ظهر error فيه link لـ index — افتحه وأنشئ الـ index المطلوب

### بعد كل تعديل على `firestore.rules`:
```
Firebase Console → Build → Firestore Database → Rules → Edit → Publish
```

---

*آخر تحديث: مارس 2026 — مشكلة 13*
