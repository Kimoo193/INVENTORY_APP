# Runbook

## 1. Daily Developer Workflow

### Start app
```bash
flutter pub get
flutter run
```

### Static checks
```bash
flutter analyze
```

## 2. Deploy Firestore Rules
The file `lib/firestore.rules` is source-only until deployed.

Typical deployment options:
1. Firebase Console Rules editor (paste and publish)
2. Firebase CLI with `firebase.json` + `firestore.rules` at repo root

Recommended:
- Add CI step to deploy rules from versioned file.

## 3. Release Deployment (Android)
1. Ensure release SHA fingerprints are added in Firebase.
2. Use release keystore config in `android/app/key.properties`.
3. Build release artifact:
```bash
flutter build appbundle --release
```
4. Upload to Play Console internal track first.

## 4. Migration Runbook (SQLite -> Firestore)
Trigger path:
- `HomeScreen._loadData()` checks `FirestoreService.isMigrated()`.
- Admins can run `MigrationScreen`.

Steps:
1. Login as admin/superadmin.
2. Start migration from migration screen.
3. Verify summary counts for:
- items
- warehouses
- products
- deleted items
4. Confirm marker document:
- `inventory/{adminUid}.migrated == true`

Rollback strategy:
- Keep SQLite backup before migration rollout.
- If migration fails, inspect counts and rerun.

## 5. Backup Strategy
Firestore recommended backups:
1. Scheduled export using GCP Firestore export.
2. Keep periodic snapshots by environment.
3. Store metadata including date and project id.

Manual lightweight backup option:
- Export critical collections via scripts/tools.

Minimum collections to preserve:
- `users`
- `inventory/*/items`
- `inventory/*/deleted_items`
- `inventory/*/warehouses`
- `inventory/*/products`
- `activity_logs`
- `notifications` (optional; operational, not always business-critical)

## 6. Monitoring and Health Checks

### Auth health
- Login/logout succeeds for each role.
- Disabled account is blocked and signed out.

### Rules health
- No unexpected `permission-denied` for valid user actions.
- Invalid actions are denied as expected.

### Data health
- Item writes appear in proper `adminUid` partition.
- Logs written under current date bucket.

## 7. Troubleshooting

### Build fails in Flutter/Dart
- Run `flutter analyze` and fix compile errors first.
- Run `flutter clean` then rebuild.

### Android `DEVELOPER_ERROR`
- Check SHA-1/SHA-256 in Firebase Android app.
- Re-download and replace `google-services.json`.

### Firestore `PERMISSION_DENIED`
- Confirm deployed rules, not just local file.
- Verify auth state (`request.auth != null`).
- Validate role and tenant (`adminUid`) assumptions.

### No notifications shown
- Confirm current user is admin when starting listener.
- Verify writes to `notifications/{uid}/items`.
- Check notification permission on Android.

### Missing logs
- Check `activity_logs/{date}/events` write permissions.
- Inspect debug print from `LogService` assert block.

## 8. Incident Playbook

### Permission regression incident
1. Capture failing query path and user role.
2. Temporarily relax only the failing path if necessary.
3. Patch and redeploy rules with test matrix.
4. Confirm with real role-based smoke tests.

### Data inconsistency incident
1. Identify affected `adminUid` partition.
2. Compare active items vs deleted archive.
3. Restore from backup/export when needed.
4. Add guard checks in service methods for recurrence.

## 9. Operational Checklists

### Pre-release checklist
1. `flutter analyze` clean of errors.
2. Rules deployed and tested.
3. Auth, inventory CRUD, delete/restore, import/export tested.
4. Superadmin and admin/user boundaries tested.
5. Release signing and Firebase config validated.

### Post-release checklist
1. Crash/error logs reviewed.
2. Permission-denied rates monitored.
3. Data write/read sanity checks on production project.
