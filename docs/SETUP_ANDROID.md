# Android Setup

## 1. Prerequisites
- Flutter SDK installed
- Android SDK and platform tools
- Java 17 (project uses Java 17 in Gradle)
- Firebase project already created

## 2. Package and Firebase App Mapping
From project config:
- Android application ID: `com.Kammr3.inventory_app`
- Firebase app options in `lib/firebase_options.dart`
- Google services file path: `android/app/google-services.json`

These values must stay aligned:
- `applicationId` in `android/app/build.gradle.kts`
- `package_name` in `android/app/google-services.json`
- Firebase Android app registration

## 3. Add SHA Keys in Firebase Console
Required for stable Android auth integrations.

### 3.1 Debug SHA keys
Run:
```bash
keytool -list -v \
  -alias androiddebugkey \
  -keystore ~/.android/debug.keystore \
  -storepass android \
  -keypass android
```
Copy SHA-1 and SHA-256 into Firebase Console:
- Project Settings -> Your Android app -> Add fingerprint

### 3.2 Release SHA keys
Use your release keystore values from `android/app/key.properties`:
```bash
keytool -list -v \
  -alias <your-release-alias> \
  -keystore <path-to-release-keystore>
```
Add SHA-1 and SHA-256 for release as well.

### 3.3 Refresh config
After adding fingerprints:
1. Download updated `google-services.json` from Firebase Console.
2. Replace `android/app/google-services.json`.
3. Run clean and build again.

## 4. Gradle Configuration Notes
File: `android/app/build.gradle.kts`

Key settings already present:
- Plugins: `com.google.gms.google-services`, Flutter, Kotlin Android
- Java/Kotlin target: 17
- Firebase BOM and libraries
- Desugaring enabled

## 5. Android Manifest Requirements
File: `android/app/src/main/AndroidManifest.xml`

Current key flags/permissions:
- `POST_NOTIFICATIONS`
- `RECEIVE_BOOT_COMPLETED`
- `VIBRATE`
- `android:enableOnBackInvokedCallback="true"`

## 6. Signing Setup
File: `android/app/build.gradle.kts`
- Release signing config reads from `android/app/key.properties`

Best practice:
- Keep `key.properties` and keystore outside VCS.
- Project `.gitignore` already excludes them.

## 7. Build and Run Commands
```bash
flutter clean
flutter pub get
flutter run
```

Release build:
```bash
flutter build appbundle --release
# or
flutter build apk --release
```

## 8. Common Android/Firebase Errors

### 8.1 `DEVELOPER_ERROR`
Usually means SHA/package mismatch.
Fix:
- Verify fingerprints in Firebase.
- Re-download `google-services.json`.
- Confirm package name consistency.

### 8.2 Firestore `PERMISSION_DENIED`
Backend rules are not permitting your query/write.
Fix:
- Update and deploy Firestore rules in Firebase Console.

### 8.3 Notification listener errors
If `notifications` query denied:
- Validate rules for `notifications/{uid}/items`
- Ensure authenticated user ID matches document path.

## 9. Production Readiness Checklist
1. Correct release SHA keys in Firebase.
2. Updated `google-services.json` committed/deployed securely.
3. Hardened Firestore rules deployed.
4. Release signing keys stored in secure vault.
5. Release build tested on clean device.
