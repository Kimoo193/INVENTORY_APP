# Firestore Schema

## 1. Overview
This document describes the effective Firestore data contracts used by the app services.

Primary namespaces:
- `users/{uid}`
- `inventory/{adminUid}/items/{itemId}`
- `inventory/{adminUid}/deleted_items/{docId}`
- `inventory/{adminUid}/warehouses/{docId}`
- `inventory/{adminUid}/products/{docId}`
- `notifications/{uid}/items/{notifId}`
- `activity_logs/{dateKey}` and `activity_logs/{dateKey}/events/{eventId}`

## 2. Collection Contracts

### 2.1 `users/{uid}`
Purpose:
- Identity profile, role, permissions, tenancy assignment

Key fields:
- `email: string`
- `name: string`
- `role: string` (`user|admin|superadmin`)
- `isActive: bool`
- `createdAt: timestamp`
- `adminUid: string|null`
- `createdBy: string|null`
- `assignedWarehouse: string|null`
- `canAdd/canEdit/canDelete/canExport/canImport/canManage/canRestore: bool`
- `fcmToken: string|null`
- `lastLogin: timestamp|null`

Writers:
- `AuthService` create/update/profile updates
- `AuthService.saveFcmToken`

### 2.2 `inventory/{adminUid}/items/{itemId}`
Purpose:
- Active inventory records for one tenant (`adminUid`)

Fields:
- `warehouseName: string`
- `productName: string`
- `serial: string|null`
- `condition: string` (Arabic labels used)
- `expiryDate: string|null`
- `notes: string|null`
- `inventoryDate: string` (`YYYY-MM-DD`)
- `addedByUid: string|null`
- `adminUid: string`
- `createdAt: timestamp`
- `updatedAt: timestamp|null`

Writers:
- `FirestoreService.insertItem`, `updateItem`, `restoreItem`

### 2.3 `inventory/{adminUid}/deleted_items/{docId}`
Purpose:
- Soft-delete archive and delete audit metadata

Fields:
- Core item fields mirrored from `items`
- `deleteReason: string`
- `deleteNotes: string`
- `deletedAt: timestamp`
- `deletedByUid: string|null`
- `addedByUid: string|null`
- `adminUid: string`

Writers:
- `FirestoreService.deleteWithReason`
- `FirestoreService.restoreItem` (updates notes)
- `FirestoreService.permanentDeleteItem` (delete doc)

### 2.4 `inventory/{adminUid}/warehouses/{docId}`
Purpose:
- Warehouse dictionary per tenant

Fields:
- `name: string`
- `createdAt: timestamp`

ID strategy:
- Document ID is sanitized warehouse name.

### 2.5 `inventory/{adminUid}/products/{docId}`
Purpose:
- Product dictionary per tenant

Fields:
- `name: string`
- `createdAt: timestamp`

ID strategy:
- Document ID is sanitized product name (supports Arabic chars).

### 2.6 `notifications/{uid}/items/{notifId}`
Purpose:
- In-app notifications per target user

Fields:
- `title: string`
- `body: string`
- `type: string`
- `read: bool`
- `createdAt: timestamp`
- `extra: map<string,string>`

Writers:
- `NotificationService._notifyAdmins`

Readers:
- `NotificationService.startListening` for same `uid`

### 2.7 `activity_logs/{dateKey}`
Purpose:
- Daily log summary documents

Document ID:
- `dateKey` format `YYYY-MM-DD`

Fields:
- `date: string`
- `count: number`
- `lastUpdated: timestamp`

### 2.8 `activity_logs/{dateKey}/events/{eventId}`
Purpose:
- Detailed event records

Fields:
- `type: string`
- `typeLabel: string`
- `date: string`
- `createdAt: timestamp`
- `createdAtIso: string`
- Optional actor/admin context fields
- Optional domain fields (`product`, `warehouse`, `serial`, `reason`, `details`)
- Optional user target fields (`targetUserName`, `targetUserEmail`)

Writers:
- `LogService.log`, wrapper methods (`logLogin`, `logLogout`, `logUserCreated`)

## 3. Access Patterns and Query Contracts

### Common queries used in code
- `users.where('role', whereIn: ['admin', 'superadmin']).where('isActive', isEqualTo: true)`
- `items.where('inventoryDate', isEqualTo: date)`
- `items.where('warehouseName', isEqualTo: assignedWarehouse)`
- `deleted_items.where('deletedByUid', isEqualTo: uid)`
- `notifications/{uid}/items.where('read', isEqualTo: false).orderBy('createdAt', descending: true)`
- `activity_logs.orderBy('date', descending: true)`

### Composite index considerations
Potential index needs in Firestore console:
- `notifications/{uid}/items`: `read ASC`, `createdAt DESC`
- `users`: `role IN`, `isActive ==`
- `items`: `warehouseName ==`, `inventoryDate ==` (if combined frequently)

## 4. Tenant Boundaries
- Tenant key is `adminUid`.
- Inventory dictionaries and records are always under `inventory/{adminUid}`.
- Users can be bound to one tenant via `users/{uid}.adminUid`.

## 5. Data Lifecycle
- Active item: `items`
- Deleted item: moved to `deleted_items`
- Restore: recreated in `items`, delete notes updated
- Permanent delete: removed from `deleted_items`
- Audit events: immutable write to `activity_logs/.../events`

## 6. Integrity Expectations
- `users.email` should be unique at application level (checked in app with query).
- `items.adminUid` should match parent path `adminUid`.
- `inventoryDate` expected `YYYY-MM-DD` format for date filtering.
- Deleted record should preserve original item context and actor metadata.
