# Security

## 1. Security Model in This App
Security is implemented across three layers:
- Firebase Authentication (who is logged in)
- Firestore Rules (what data can be read/written)
- App-level authorization (role and capability checks in UI/services)

## 2. Current Identity and Role Strategy
Source: `lib/auth_service.dart`

- User profile is stored in `users/{uid}`.
- Role is one of `user`, `admin`, `superadmin`.
- Capability flags are booleans (`canAdd`, `canEdit`, etc.).
- Tenant binding is `adminUid` for non-admin users.

Superadmin bootstrap:
- `initSuperAdmin()` creates or validates initial superadmin account and profile.

## 3. Firestore Rules Model (Current)
Source: `lib/firestore.rules`

Defined helpers:
- `isAuthenticated()`
- `getUserData()`
- `isAdmin()`
- `isSuperAdmin()`

Current rule highlights:
- `users/{userId}`: read self/admin, create authenticated, update admin (except superadmin role row), delete superadmin only.
- `notifications/{userId}/items/{notifId}`: create authenticated, read/update owner only, delete admin.
- `activity_logs/**`: write authenticated, read admin.
- Global fallback currently allows all authenticated read/write on unmatched paths.

## 4. Hardening Recommendations

### 4.1 Remove broad fallback
Current fallback:
- `match /{document=**} { allow read, write: if isAuthenticated(); }`

Risk:
- Any authenticated user may access unintended collections.

Action:
- Replace with explicit, per-collection rules only.

### 4.2 Enforce tenant checks in rules
For `inventory/{adminUid}/...` collections, enforce:
- admins can access their own partition (`request.auth.uid == adminUid`)
- users can access only if their `users/{uid}.adminUid == adminUid`

### 4.3 Restrict client-side notification fan-out
Current model writes notification docs from client.

Risk:
- Any authenticated client can generate notification documents.

Action:
- Preferred: move fan-out to server-side Cloud Functions/Admin SDK.

### 4.4 Reduce write scope for logs
Current rules allow all authenticated users to write all log paths.

Action:
- Keep write allowed only if payload actor matches `request.auth.uid`, or route logging through trusted backend.

### 4.5 Validate immutable fields
In rules, lock sensitive fields where possible:
- prevent normal users from changing `role`, permission booleans, `adminUid`, `isActive`

## 5. Android Secrets and Signing
Sensitive files observed:
- `android/app/key.properties`
- keystore file path in that properties file

Actions:
- Never commit keystore or credentials.
- Rotate credentials if exposed.
- Keep signing keys in secret storage (CI variables or encrypted vault).

## 6. Operational Security Checklist
Before release:
1. Deploy hardened Firestore rules.
2. Verify Email/Password auth provider settings.
3. Add SHA-1/SHA-256 for debug and release signatures.
4. Rotate any leaked keys/passwords.
5. Confirm no plaintext secrets in repo history.
6. Test role boundaries with real users.

## 7. Abuse and Failure Controls
- Handle `permission-denied` and surface user-friendly messages.
- Avoid infinite retry loops on denied listeners/queries.
- Log security-relevant failures (without exposing secrets).

## 8. Incident Response (Minimal)
If unauthorized access is suspected:
1. Lock down rules to deny broad access.
2. Disable risky write paths temporarily.
3. Rotate credentials and regenerate keystores if needed.
4. Audit logs in `activity_logs` and Firebase console.
5. Re-enable with hardened rules and tested paths.
