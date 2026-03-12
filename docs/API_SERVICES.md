# API Services

This document describes behavior contracts for service-layer APIs used by the app.

## 1. `AuthService` (`lib/auth_service.dart`)

### Purpose
- Authentication orchestration
- User profile retrieval
- Role and permission administration

### `Future<AppUser?> login(String email, String password)`
- Signs in with Firebase Auth.
- Loads user profile from `users/{uid}`.
- Rejects inactive accounts and signs out.
- Updates `lastLogin` best-effort.
- Writes login event through `LogService`.
- Throws mapped Arabic message on auth errors.

### `Future<void> logout()`
- Deletes `fcmToken` best-effort.
- Signs out current auth session.

### `Future<AppUser?> getCurrentUser()`
- Returns current Firebase user profile from Firestore.
- Returns `null` when not logged in.

### `Future<void> saveFcmToken(String token)`
- Upserts user `fcmToken` and `lastLogin`.

### `Future<List<String>> getAdminFcmTokens()`
- Fetches active admin/superadmin tokens from `users`.

### `Future<AppUser> createAdmin(...)`
- Calls `_createUserSafely` with admin role and full permissions.

### `Future<AppUser> createUser(...)`
- Calls `_createUserSafely` with user role and provided permissions.

### `Future<AppUser> _createUserSafely(...)`
- Creates user with secondary Firebase app to avoid switching primary session.
- Writes new user doc via secondary app Firestore context.
- Applies tenant/admin relationship (`adminUid`) logic.
- Logs user/admin creation event.
- Cleans up temporary app.

### `Future<void> upgradeUserToAdmin(String uid)`
- Sets role to admin and enables admin-like permissions.
- Clears `adminUid` association.

### `Future<void> downgradeAdminToUser(String uid, String adminUid)`
- Sets role to user with reduced default permissions.
- Assigns `adminUid`.

### `Future<List<AppUser>> getUsersByAdmin(String adminUid)`
- Merges users by `adminUid` and legacy `createdBy` fallback.
- Deduplicates and excludes superadmin/self rows.

### `Future<List<AppUser>> getAllUsers()`
- Returns all user profiles ordered by `createdAt` descending.

### `Future<void> updateUserPermissions(String uid, Map<String,dynamic> data)`
- Partial update on user doc.

### `Future<void> toggleUserActive(String uid, bool isActive, {String? byUid})`
- Updates `isActive` and logs activation/deactivation event.

### `Future<void> changePassword(String newPassword)`
- Updates password of currently signed-in user.

### `Future<void> ensureUserDocument(dynamic firebaseUser)`
- Creates profile doc if missing.
- Auto-promotes configured superadmin email.

### `Future<void> initSuperAdmin()`
- Ensures bootstrap superadmin account and profile exist.

## 2. `FirestoreService` (`lib/firestore_service.dart`)

### Purpose
- Main domain data API for inventory and dictionaries
- Tenant-scoped access and migration support

### Internal tenancy behavior
- `_getAdminUid()`:
- admin/superadmin -> own `uid`
- user -> `adminUid`

All domain collections are partitioned under `inventory/{adminUid}`.

### Inventory CRUD
- `insertItem(InventoryItem item)`:
- Writes item, ensures warehouse/product dictionaries exist, logs add event.

- `getAllItems()`:
- Reads all tenant items or only assigned warehouse for user role.

- `getItemsByDate(String date)`:
- Date-filtered read with role warehouse scoping.

- `getInventoryDates()`:
- Distinct date extraction from tenant items.

- `updateItem(InventoryItem item)`:
- Updates mutable item fields and logs edit event.

- `deleteWithReason(...)`:
- Moves item to `deleted_items`, deletes from active `items`, logs deletion.

### Deleted items
- `getDeletedItems()`:
- Returns tenant deleted archive, ordered by `deletedAt`.

- `getDeletedItemsByUser(String uid)`:
- Reads deleted rows by actor uid with fallback strategy.

- `_getDeletedItemsByUserFallback(String uid)`:
- Cross-admin scan fallback when admin mapping is unavailable.

- `restoreItem(Map deletedItem)`:
- Recreates active item and appends restore note in deleted record.

- `permanentDeleteItem(String docId)`:
- Removes deleted record permanently and logs permanent deletion.

### Warehouses/Products dictionary
- `addWarehouse`, `getWarehouses`, `deleteWarehouse`, `updateWarehouse`
- `addProduct`, `getProducts`, `deleteProduct`, `updateProduct`

Behavior:
- Deterministic/sanitized doc IDs to reduce duplicates.

### Stats
- `getStats({String? date})`:
- Returns counts (`total`, `good`, `used`, `damaged`, `deleted`) with role filters.

### Migration
- `migrateFromSQLite(...)`:
- Migrates warehouses/products/items/deleted in batches.
- Sets migration marker at `inventory/{adminUid}`.

- `isMigrated()`:
- Returns migration marker status.

## 3. `LogService` (`lib/log_service.dart`)

### Purpose
- Structured daily audit logging with retrieval helpers

### `Future<void> log({...})`
- Writes event into `activity_logs/{date}/events`.
- Auto-fills actor/admin context when missing.
- Increments daily summary counter doc.

### `Future<void> logLogin(AppUser user)`
### `Future<void> logLogout(AppUser user)`
### `Future<void> logUserCreated({...})`
- Typed convenience wrappers around `log()`.

### `Future<List<Map<String,dynamic>>> getLogDates()`
- Returns available date buckets and counts (up to 90).

### `Future<List<Map<String,dynamic>>> getEventsByDate(String dateKey)`
- Returns all events for date, sorted by `createdAtIso` descending in Dart.

### `Future<List<Map<String,dynamic>>> getPermanentlyDeletedItems({int limitDays = 365})`
- Searches date buckets and event subcollections for `item_permanent_deleted`.

### `Future<int> deleteOldLogs({int olderThanDays = 365})`
- Deletes old date docs and their event subcollections.

## 4. `NotificationService` (`lib/notification_service.dart`)

### Purpose
- Firestore-backed in-app notification pipeline
- Android local notification display

### `Future<void> initialize()`
- Initializes local notifications plugin once.
- Creates Android notification channel.

### `Future<void> startListening(String uid)`
- Subscribes to unread notifications under `notifications/{uid}/items`.
- Shows local notification for new docs.
- Marks consumed docs as `read = true` best-effort.

### `Future<void> stopListening()`
- Cancels listener and clears local tracking state.

### `Future<void> notifyItemAdded(...)`
### `Future<void> notifyItemDeleted(...)`
### `Future<void> notifyUserCreated(...)`
- Typed wrappers calling `_notifyAdmins`.

### `_notifyAdmins(...)` behavior
- Fetches active admins and superadmins from `users`.
- Batch writes notifications to each target admin path.
- Skips notifying current listener owner (`_currentUserUid`).

## 5. Validation Utilities (`AppValidators`)

Located in `auth_service.dart`.

- `validateEmail(String email)` -> sync format/length checks
- `checkEmailNotUsed(String email)` -> async Firestore uniqueness check
- `validatePassword(String password)` -> complexity rules
- `passwordRules`, `emailRules` -> user-facing guidance strings

## 6. API Error Handling Convention
- Most service methods catch exceptions and return safe defaults (`[]`, `null`, `false`) for resilience.
- Auth entry points throw mapped Arabic exceptions for user-visible failures.
- Logging intentionally suppresses failures to avoid blocking primary flows.
